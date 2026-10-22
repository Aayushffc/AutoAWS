#!/usr/bin/env node

/**
 * AutoAWS Onboarding & Cost Estimation Engine
 * 
 * Takes in client workloads, sizes infrastructure, calculates transparent
 * 730-hour AWS monthly baseline costs, validates guardrails, and emits
 * clients/<client_name>-<environment>.tfvars.json.
 */

const fs = require('fs');
const path = require('path');

// AWS 730-hour Monthly Cost Benchmarks (us-east-1 / us-west-1)
const RATES = {
  ALB_BASE: 22.00, // $16.50 base ($0.0225/hr) + $5.50 estimated LCU
  FARGATE_VCPU_HOUR: 0.04048,
  FARGATE_RAM_GB_HOUR: 0.004445,
  FARGATE_PUBLIC_IPV4_HOUR: 0.005, // ~$3.65/mo per task (Zero-NAT)
  RDS_RATES: {
    'db.t4g.micro': { compute: 11.68, storageGb: 0.115 }, // ~$14.00/mo with 20GB
    'db.t4g.small': { compute: 23.36, storageGb: 0.115 }, // ~$25.60/mo with 20GB
    'db.t4g.medium': { compute: 46.72, storageGb: 0.115 },
    'db.t3.micro': { compute: 12.41, storageGb: 0.115 },
    'db.t3.small': { compute: 24.82, storageGb: 0.115 },
  },
  NAT_GATEWAY: 32.85, // $0.045/hr * 730 hrs
  HOURS_PER_MONTH: 730
};

// Sizing presets
const SIZING_PRESETS = {
  dev: { cpu: 512, memory: 1024, tasks: 1, vcpu: 0.5, ramGb: 1.0, rds: 'db.t4g.micro', desc: '512 CPU / 1024 MB (API: 384/768, Worker: 128/256)' },
  staging: { cpu: 512, memory: 1024, tasks: 1, vcpu: 0.5, ramGb: 1.0, rds: 'db.t4g.micro', desc: '512 CPU / 1024 MB (API: 384/768, Worker: 128/256)' },
  production: { cpu: 1024, memory: 2048, tasks: 2, vcpu: 1.0, ramGb: 2.0, rds: 'db.t4g.small', desc: '1024 CPU / 2048 MB (API: 768/1536, Worker: 256/512)' }
};

function parseArgs() {
  const args = process.argv.slice(2);
  const options = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      const key = args[i].substring(2);
      const val = args[i + 1] && !args[i + 1].startsWith('--') ? args[++i] : true;
      options[key] = val;
    }
  }
  return options;
}

function calculateCost(config) {
  const items = [];
  let total = 0;

  // 1. ALB
  items.push({
    component: 'Application Load Balancer (ALB)',
    details: 'Single multi-AZ ingress (HTTP/HTTPS, TLS 1.3/1.2, Swagger rules)',
    monthly: RATES.ALB_BASE
  });
  total += RATES.ALB_BASE;

  // 2. ECS Fargate Compute (Dual Container: API + Worker)
  const vcpu = config.ecs_task_cpu / 1024;
  const ramGb = config.ecs_task_memory / 1024;
  const hourlyPerTask = (vcpu * RATES.FARGATE_VCPU_HOUR) + (ramGb * RATES.FARGATE_RAM_GB_HOUR);
  const monthlyFargate = parseFloat((hourlyPerTask * RATES.HOURS_PER_MONTH * config.ecs_desired_count).toFixed(2));

  items.push({
    component: `ECS Fargate Compute (${config.ecs_desired_count} task${config.ecs_desired_count > 1 ? 's' : ''})`,
    details: `${vcpu} vCPU / ${ramGb} GB RAM (API + Worker) @ ${config.ecs_desired_count} task(s)`,
    monthly: monthlyFargate
  });
  total += monthlyFargate;

  // 3. Networking: Zero-NAT IPv4 vs NAT Gateway
  if (config.enable_nat_gateway === true) {
    items.push({
      component: 'VPC NAT Gateway (1 shared)',
      details: 'Outbound internet for private subnets (~$0.045/hr)',
      monthly: RATES.NAT_GATEWAY
    });
    total += RATES.NAT_GATEWAY;
  } else {
    const ipv4Cost = parseFloat((RATES.FARGATE_PUBLIC_IPV4_HOUR * RATES.HOURS_PER_MONTH * config.ecs_desired_count).toFixed(2));
    items.push({
      component: `Public IPv4 [Zero-NAT] (${config.ecs_desired_count} task${config.ecs_desired_count > 1 ? 's' : ''})`,
      details: `$0.005/hr IPv4 x 730 hrs (Saves ~$${(RATES.NAT_GATEWAY - ipv4Cost).toFixed(2)}/mo vs NAT Gateway)`,
      monthly: ipv4Cost
    });
    total += ipv4Cost;
  }

  // 4. Amazon RDS PostgreSQL
  if (config.enable_rds) {
    const rate = RATES.RDS_RATES[config.rds_instance_class] || { compute: 11.68, storageGb: 0.115 };
    const computeCost = config.environment === 'production' ? rate.compute * 2 : rate.compute;
    const storageCost = config.rds_allocated_storage * rate.storageGb;
    const monthlyRds = parseFloat((computeCost + storageCost).toFixed(2));

    items.push({
      component: `RDS PostgreSQL (${config.rds_instance_class})`,
      details: `${config.rds_allocated_storage} GB gp3 in isolated DB subnets (${config.environment === 'production' ? 'Multi-AZ' : 'Single-AZ'})`,
      monthly: monthlyRds
    });
    total += monthlyRds;
  }

  // 5. Storage & CDN baseline
  items.push({
    component: 'S3 & CloudFront CDN',
    details: 'Media uploads + OAC SigV4 global edge delivery',
    monthly: 2.50
  });
  total += 2.50;

  return { items, total: parseFloat(total.toFixed(2)) };
}

function printCostTable(costData) {
  console.log('\n| Component | Configuration Details | Est. Monthly Cost |');
  console.log('| :--- | :--- | :--- |');
  costData.items.forEach(item => {
    console.log(`| **${item.component}** | ${item.details} | ~$${item.monthly.toFixed(2)}/mo |`);
  });
  console.log(`| **TOTAL ESTIMATED BASELINE** | Cost-Optimized Zero-NAT Architecture | **~$${costData.total.toFixed(2)}/mo** |\n`);
}

function validateSlug(name) {
  return /^[a-z0-9-]+$/.test(name);
}

function generateConfig(params) {
  const client = (params.client || params.client_name || 'tapsy').toLowerCase().trim();
  if (!validateSlug(client)) {
    throw new Error(`Invalid client_name '${client}'. Must contain lowercase alphanumeric characters and hyphens only.`);
  }

  let env = (params.env || params.environment || 'staging').toLowerCase().trim();
  if (!['dev', 'staging', 'production', 'prod'].includes(env)) {
    env = 'staging';
  }

  const preset = SIZING_PRESETS[env === 'prod' ? 'production' : env] || SIZING_PRESETS.staging;

  const config = {
    client_name: client,
    environment: env,
    aws_region: params.region || params.aws_region || 'us-west-1',
    container_port: parseInt(params.port || params.container_port || 3000, 10),
    enable_nat_gateway: params.nat === 'true' || params.enable_nat_gateway === true,
    certificate_arn: params.certificate_arn || '',
    enable_swagger_protection: params.enable_swagger_protection !== false && params.swagger !== 'false',
    swagger_whitelist_ips: [
      '122.168.85.82/32',
      '202.89.77.27/32',
      '122.168.82.7/32',
      '122.168.81.182/32',
      '202.89.67.216/32'
    ],
    ecs_task_cpu: parseInt(params.cpu || params.ecs_task_cpu || preset.cpu, 10),
    ecs_task_memory: parseInt(params.memory || params.ecs_task_memory || preset.memory, 10),
    ecs_desired_count: parseInt(params.tasks || params.ecs_desired_count || preset.tasks, 10),
    enable_rds: params.rds !== 'false' && params.enable_rds !== false,
    rds_instance_class: params.rds_class || params.rds_instance_class || preset.rds,
    rds_allocated_storage: parseInt(params.storage || params.rds_allocated_storage || 20, 10),
    enable_amplify: params.amplify === 'true' || params.enable_amplify === true
  };

  return config;
}

function run() {
  const options = parseArgs();
  const config = generateConfig(options);
  const cost = calculateCost(config);

  console.log(`\n======================================================`);
  console.log(` AutoAWS Onboarding: ${config.client_name.toUpperCase()} [${config.environment.toUpperCase()}]`);
  console.log(`======================================================`);

  printCostTable(cost);

  // Ensure clients directory exists
  const clientsDir = path.resolve(__dirname, '..', 'clients');
  if (!fs.existsSync(clientsDir)) {
    fs.mkdirSync(clientsDir, { recursive: true });
  }

  const clientFilePath = path.join(clientsDir, `${config.client_name}-${config.environment}.tfvars.json`);
  fs.writeFileSync(clientFilePath, JSON.stringify(config, null, 2), 'utf-8');
  console.log(`[SUCCESS] Generated client configuration: clients/${config.client_name}-${config.environment}.tfvars.json\n`);

  console.log('--- terraform.tfvars.json ---');
  console.log(JSON.stringify(config, null, 2));
  console.log('-----------------------------\n');

  console.log('Deploy Commands:');
  console.log(`  terraform workspace select -or-create ${config.client_name}-${config.environment}`);
  console.log(`  terraform plan -var-file=clients/${config.client_name}-${config.environment}.tfvars.json`);
  console.log(`  terraform apply -var-file=clients/${config.client_name}-${config.environment}.tfvars.json\n`);
}

if (require.main === module) {
  run();
}

module.exports = { generateConfig, calculateCost, SIZING_PRESETS, RATES };
