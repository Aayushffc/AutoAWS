#!/usr/bin/env node

/**
 * AutoAWS - Interactive Infrastructure Onboarding CLI
 * 
 * Powered by @clack/prompts and picocolors
 * Guides users through client intake, sizes workloads, provides transparent cost estimates,
 * verifies AWS authentication, generates clients/<client>-<env>.tfvars.json,
 * and executes Terraform with real-time streaming output.
 */

const fs = require('fs');
const path = require('path');
const { execSync, spawnSync } = require('child_process');
const p = require('@clack/prompts');
const pc = require('picocolors');

// Graceful SIGINT handler
process.on('SIGINT', () => {
  p.cancel('Operation cancelled by user.');
  process.exit(0);
});

// Helper: Ensure environment PATH has terraform if installed via WinGet on Windows
function ensureTerraformInPath() {
  if (process.platform === 'win32') {
    const wingetTerraformPath = 'C:\\Users\\AayushSoni\\AppData\\Local\\Microsoft\\WinGet\\Packages\\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe';
    if (fs.existsSync(wingetTerraformPath) && !process.env.PATH.includes(wingetTerraformPath)) {
      process.env.PATH = `${process.env.PATH};${wingetTerraformPath}`;
    }
  }
}
ensureTerraformInPath();

// AWS Pricing Rates (730-hour baseline month)
const RATES = {
  ALB_BASE: 22.00, // $16.50 base ($0.0225/hr) + $5.50 estimated LCU
  FARGATE_VCPU_HOUR: 0.04048,
  FARGATE_RAM_GB_HOUR: 0.004445,
  FARGATE_PUBLIC_IPV4_HOUR: 0.005, // ~$3.65/mo per task (Zero-NAT)
  RDS: {
    'db.t4g.micro': { compute: 11.68, storageGb: 0.115, name: 'db.t4g.micro (2 vCPU Graviton, 1 GB RAM)' },
    'db.t4g.small': { compute: 23.36, storageGb: 0.115, name: 'db.t4g.small (2 vCPU Graviton, 2 GB RAM)' },
    'db.t4g.medium': { compute: 46.72, storageGb: 0.115, name: 'db.t4g.medium (2 vCPU Graviton, 4 GB RAM)' }
  },
  NAT_GATEWAY: 32.85, // $0.045/hr * 730 hrs
  S3_CDN_BASE: 2.50,
  HOURS: 730
};

// Sizing Presets by Environment (Toned down to 0.25 vCPU / 0.5 GB RAM by default)
const PRESETS = {
  dev: {
    label: '0.25 vCPU (256 units) / 0.5 GB RAM (512 MB)',
    desc: 'Cost-optimized baseline (~$9.01/mo compute)',
    cpu: 256,
    memory: 512,
    tasks: 1,
    rds: 'db.t4g.micro'
  },
  staging: {
    label: '0.25 vCPU (256 units) / 0.5 GB RAM (512 MB)',
    desc: 'Ideal for staging & demo environments (~$9.01/mo compute)',
    cpu: 256,
    memory: 512,
    tasks: 1,
    rds: 'db.t4g.micro'
  },
  production: {
    label: '0.50 vCPU (512 units) / 1.0 GB RAM (1024 MB)',
    desc: 'Production High-Availability (2 tasks behind ALB)',
    cpu: 512,
    memory: 1024,
    tasks: 2,
    rds: 'db.t4g.small'
  }
};

function checkCancel(val) {
  if (p.isCancel(val)) {
    p.cancel('Operation cancelled.');
    process.exit(0);
  }
  return val;
}

// Pre-flight check: Verify AWS Credentials
function checkAwsAuth() {
  try {
    const raw = execSync('aws sts get-caller-identity --output json', {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe']
    });
    const parsed = JSON.parse(raw);
    return {
      valid: true,
      account: parsed.Account,
      arn: parsed.Arn,
      userId: parsed.UserId
    };
  } catch (err) {
    const msg = err.stderr ? err.stderr.toString().trim() : err.message;
    return {
      valid: false,
      error: msg || 'No active AWS credentials found'
    };
  }
}

// Calculate cost breakdown
function calculateCost(config) {
  const items = [];
  let total = 0;

  // 1. ALB
  items.push({
    name: 'Application Load Balancer (ALB)',
    details: 'Multi-AZ Ingress with HTTP/HTTPS routing & TLS 1.3/1.2 ($16.50 base + $5.50 LCU)',
    monthly: RATES.ALB_BASE
  });
  total += RATES.ALB_BASE;

  // 2. Fargate Compute
  const vcpu = config.ecs_task_cpu / 1024;
  const ramGb = config.ecs_task_memory / 1024;
  const hourlyPerTask = (vcpu * RATES.FARGATE_VCPU_HOUR) + (ramGb * RATES.FARGATE_RAM_GB_HOUR);
  const monthlyFargate = parseFloat((hourlyPerTask * RATES.HOURS * config.ecs_desired_count).toFixed(2));
  
  const containerLabel = config.enable_worker_container 
    ? 'Dual-Container: API + Worker' 
    : 'Single API Container';

  items.push({
    name: `ECS Fargate Compute (${config.ecs_desired_count} task${config.ecs_desired_count > 1 ? 's' : ''})`,
    details: `${vcpu} vCPU (${config.ecs_task_cpu} units) / ${ramGb} GB RAM (${config.ecs_task_memory} MB) [${containerLabel}]`,
    monthly: monthlyFargate
  });
  total += monthlyFargate;

  // 3. Networking: Zero-NAT IPv4 vs NAT Gateway
  if (config.enable_nat_gateway) {
    items.push({
      name: 'VPC NAT Gateway (1 shared)',
      details: 'Outbound internet for private tasks ($0.045/hr x 730 hrs)',
      monthly: RATES.NAT_GATEWAY
    });
    total += RATES.NAT_GATEWAY;
  } else {
    const ipv4Cost = parseFloat((RATES.FARGATE_PUBLIC_IPV4_HOUR * RATES.HOURS * config.ecs_desired_count).toFixed(2));
    items.push({
      name: `Public Task IPv4 Addresses (${config.ecs_desired_count} task${config.ecs_desired_count > 1 ? 's' : ''}) [Zero-NAT]`,
      details: `$0.005/hr IPv4 x 730 hrs (Saves ~$${(RATES.NAT_GATEWAY - ipv4Cost).toFixed(2)}/mo vs NAT Gateway)`,
      monthly: ipv4Cost
    });
    total += ipv4Cost;
  }

  // 4. Amazon RDS
  if (config.enable_rds) {
    const rdsRate = RATES.RDS[config.rds_instance_class] || RATES.RDS['db.t4g.micro'];
    const isMultiAz = config.environment === 'production' || config.environment === 'prod';
    const computeCost = isMultiAz ? rdsRate.compute * 2 : rdsRate.compute;
    const storageCost = config.rds_allocated_storage * rdsRate.storageGb;
    const monthlyRds = parseFloat((computeCost + storageCost).toFixed(2));
    items.push({
      name: `Amazon RDS PostgreSQL (${config.rds_instance_class})`,
      details: `${config.rds_allocated_storage} GB gp3 in isolated DB subnets (${isMultiAz ? 'Multi-AZ HA' : 'Single-AZ'})`,
      monthly: monthlyRds
    });
    total += monthlyRds;
  }

  // 5. S3 & CloudFront
  items.push({
    name: 'S3 Media & CloudFront CDN',
    details: 'Private S3 bucket + CloudFront OAC SigV4 global edge delivery',
    monthly: RATES.S3_CDN_BASE
  });
  total += RATES.S3_CDN_BASE;

  return { items, total: parseFloat(total.toFixed(2)) };
}

// Format cost summary box
function formatCostBox(config, cost) {
  const lines = [];
  lines.push(`${pc.bold('Client:')}      ${pc.cyan(config.client_name)}`);
  lines.push(`${pc.bold('Environment:')} ${pc.magenta(config.environment)} (${config.aws_region})`);
  lines.push(`${pc.bold('Compute:')}     ${config.ecs_task_cpu} CPU units (${config.ecs_task_cpu / 1024} vCPU) / ${config.ecs_task_memory} MB RAM (${config.ecs_desired_count} task${config.ecs_desired_count > 1 ? 's' : ''})`);
  lines.push(`${pc.bold('Containers:')}  ${config.enable_worker_container ? pc.yellow('Dual-Container (API + Background Worker)') : pc.green('Single API Container (Standard)')}`);
  lines.push(`${pc.bold('Networking:')}  ${config.enable_nat_gateway ? pc.red('NAT Gateway Enabled ($32.85/mo)') : pc.green('Cost-Optimized Zero-NAT (Direct IGW + Public IP)')}`);
  lines.push(`${pc.bold('Security:')}    ${config.enable_swagger_protection ? pc.green('Swagger /api-docs/* Whitelist + 403 Block Enabled') : pc.gray('Open')}`);
  lines.push(`${pc.bold('Secrets:')}     Hierarchical <project>/<env>/app_secrets`);
  if (config.enable_rds) {
    lines.push(`${pc.bold('Database:')}    PostgreSQL 16 on ${config.rds_instance_class} (${config.rds_allocated_storage} GB gp3 in isolated subnets)`);
  } else {
    lines.push(`${pc.bold('Database:')}    ${pc.gray('Disabled')}`);
  }
  lines.push(`${pc.bold('Amplify App:')} ${config.enable_amplify ? pc.green('Enabled') : pc.gray('Disabled')}`);
  lines.push('');
  lines.push(pc.bold(pc.underline('Monthly Line-Item Estimates (730 Hours Baseline):')));

  cost.items.forEach(item => {
    const costStr = pc.yellow(`~$${item.monthly.toFixed(2)}/mo`);
    lines.push(` • ${pc.bold(item.name)}: ${costStr}`);
    lines.push(`   ${pc.dim(item.details)}`);
  });

  lines.push('');
  lines.push(`${pc.bold('TOTAL BASELINE COST:')} ${pc.bgGreen(pc.black(` ~$${cost.total.toFixed(2)}/month `))}`);
  if (!config.enable_nat_gateway) {
    lines.push(pc.green('✔ Zero-NAT architecture active: ~$29.20/month saved on idle NAT Gateway costs!'));
  }

  return lines.join('\n');
}

async function runOnboard() {
  console.clear();
  p.intro(pc.bgCyan(pc.black(' AutoAWS Infrastructure Architect & Cost-Optimized Onboarding Engine ')));

  // Step 1: Client Name
  const clientName = checkCancel(await p.text({
    message: 'Enter client or project name (slug format):',
    placeholder: 'acme',
    validate(val) {
      if (!val || val.trim().length === 0) return 'Client name is required.';
      if (!/^[a-z0-9-]+$/.test(val.trim())) {
        return 'Client name must contain lowercase letters, numbers, and hyphens only (e.g. "acme", "acme-api").';
      }
    }
  })).trim();

  // Step 2: Environment
  const environment = checkCancel(await p.select({
    message: 'Select target deployment environment:',
    options: [
      { value: 'staging', label: 'staging', hint: 'recommended default for client previews & testing' },
      { value: 'dev', label: 'dev', hint: 'cost-optimized feature sandboxes' },
      { value: 'production', label: 'production', hint: 'multi-AZ high-availability & dual tasks' }
    ],
    initialValue: 'staging'
  }));

  // Step 3: AWS Region
  const awsRegion = checkCancel(await p.select({
    message: 'Select target AWS Region:',
    options: [
      { value: 'us-west-1', label: 'us-west-1 (N. California)' },
      { value: 'us-east-1', label: 'us-east-1 (N. Virginia)' },
      { value: 'ap-south-1', label: 'ap-south-1 (Mumbai)' }
    ],
    initialValue: 'us-west-1'
  }));

  // Step 4: Compute Sizing
  const presetKey = environment === 'production' ? 'production' : environment;
  const defaultPreset = PRESETS[presetKey] || PRESETS.staging;

  const sizingChoice = checkCancel(await p.select({
    message: `Choose ECS Fargate compute sizing for ${environment}:`,
    options: [
      {
        value: 'preset',
        label: `Recommended Default: ${defaultPreset.label}`,
        hint: defaultPreset.desc
      },
      {
        value: 'custom',
        label: 'Custom Sizing...',
        hint: 'customize CPU in units and RAM in MB separately'
      }
    ]
  }));

  let ecsTaskCpu = defaultPreset.cpu;
  let ecsTaskMemory = defaultPreset.memory;
  let ecsDesiredCount = defaultPreset.tasks;

  if (sizingChoice === 'custom') {
    // Ask CPU separately in units
    ecsTaskCpu = checkCancel(await p.select({
      message: 'Select total container CPU allocation (in units):',
      options: [
        { value: 256, label: '256 CPU units (0.25 vCPU)', hint: 'Ideal for microservices & lightweight APIs (~$7.40/mo)' },
        { value: 512, label: '512 CPU units (0.50 vCPU)', hint: 'Standard backend API traffic (~$14.80/mo)' },
        { value: 1024, label: '1024 CPU units (1.00 vCPU)', hint: 'High-throughput / production load (~$29.60/mo)' },
        { value: 2048, label: '2048 CPU units (2.00 vCPU)', hint: 'Compute intensive workloads (~$59.10/mo)' }
      ],
      initialValue: defaultPreset.cpu
    }));

    // Ask RAM separately in MB
    const ramOptionsByCpu = {
      256: [
        { value: 512, label: '512 MB (0.5 GB RAM)' },
        { value: 1024, label: '1024 MB (1.0 GB RAM)' },
        { value: 2048, label: '2048 MB (2.0 GB RAM)' }
      ],
      512: [
        { value: 1024, label: '1024 MB (1.0 GB RAM)' },
        { value: 2048, label: '2048 MB (2.0 GB RAM)' },
        { value: 4096, label: '4096 MB (4.0 GB RAM)' }
      ],
      1024: [
        { value: 2048, label: '2048 MB (2.0 GB RAM)' },
        { value: 3072, label: '3072 MB (3.0 GB RAM)' },
        { value: 4096, label: '4096 MB (4.0 GB RAM)' },
        { value: 8192, label: '8192 MB (8.0 GB RAM)' }
      ],
      2048: [
        { value: 4096, label: '4096 MB (4.0 GB RAM)' },
        { value: 8192, label: '8192 MB (8.0 GB RAM)' },
        { value: 16384, label: '16384 MB (16.0 GB RAM)' }
      ]
    };

    ecsTaskMemory = checkCancel(await p.select({
      message: 'Select total container RAM allocation (in MB):',
      options: ramOptionsByCpu[ecsTaskCpu] || ramOptionsByCpu[256],
      initialValue: defaultPreset.memory
    }));

    const taskCountStr = checkCancel(await p.text({
      message: 'Desired running task count:',
      initialValue: String(defaultPreset.tasks),
      validate(val) {
        const num = parseInt(val, 10);
        if (isNaN(num) || num < 1 || num > 20) return 'Task count must be a number between 1 and 20.';
      }
    }));
    ecsDesiredCount = parseInt(taskCountStr, 10);
  }

  // Step 5: Container Architecture (Single vs Dual Container)
  const enableWorkerContainer = checkCancel(await p.confirm({
    message: 'Enable an optional co-located background worker container?',
    hint: 'Default: No (single API container is cleaner and standard for most projects)',
    initialValue: false
  }));

  // Step 6: Container Port
  const containerPortStr = checkCancel(await p.text({
    message: 'Application listening port for backend-api-container:',
    initialValue: '3000',
    validate(val) {
      const prt = parseInt(val, 10);
      if (isNaN(prt) || prt < 1 || prt > 65535) return 'Port must be a valid number between 1 and 65535.';
    }
  }));
  const containerPort = parseInt(containerPortStr, 10);

  // Step 7: Cost-Optimized Zero-NAT Gateway Toggle
  const omitNat = checkCancel(await p.confirm({
    message: 'Omit AWS NAT Gateway ($32.85/mo savings) and use public subnets + Zero-Trust Security Groups?',
    initialValue: true
  }));
  const enableNatGateway = !omitNat;

  // Step 8: Application Load Balancer & Swagger Protection
  const certArnInput = checkCancel(await p.text({
    message: 'ACM Certificate ARN for HTTPS:443 (leave blank for turnkey auto-generated cert):',
    placeholder: 'arn:aws:acm:us-west-1:123456789012:certificate/acme-123',
    initialValue: ''
  }));
  const certificateArn = certArnInput ? certArnInput.trim() : '';

  const enableSwaggerProtection = checkCancel(await p.confirm({
    message: 'Enable Swagger documentation protection (/api-docs/* IP whitelist + 403 block)?',
    initialValue: true
  }));

  let swaggerWhitelistIps = [
    '122.168.85.82/32',
    '202.89.77.27/32',
    '122.168.82.7/32',
    '122.168.81.182/32',
    '202.89.67.216/32'
  ];

  if (enableSwaggerProtection) {
    const ipsInput = checkCancel(await p.text({
      message: 'Comma-separated CIDR blocks permitted to access /api-docs/*:',
      initialValue: swaggerWhitelistIps.join(', ')
    }));
    swaggerWhitelistIps = ipsInput
      .split(',')
      .map(s => s.trim())
      .filter(Boolean);
  }

  // Step 9: Database (RDS PostgreSQL in Isolated Subnets)
  const enableRds = checkCancel(await p.confirm({
    message: 'Enable managed PostgreSQL database in isolated DB subnets?',
    initialValue: true
  }));

  let rdsInstanceClass = defaultPreset.rds;
  let rdsAllocatedStorage = 20;

  if (enableRds) {
    rdsInstanceClass = checkCancel(await p.select({
      message: 'Select PostgreSQL RDS instance class:',
      options: [
        { value: 'db.t4g.micro', label: 'db.t4g.micro (2 vCPU Graviton, 1 GB RAM)', hint: 'Ideal for dev/staging & MVPs (~$14/mo)' },
        { value: 'db.t4g.small', label: 'db.t4g.small (2 vCPU Graviton, 2 GB RAM)', hint: 'Recommended for moderate load (~$26/mo)' },
        { value: 'db.t4g.medium', label: 'db.t4g.medium (2 vCPU Graviton, 4 GB RAM)', hint: 'High-throughput / production load (~$49/mo)' }
      ],
      initialValue: defaultPreset.rds
    }));

    const storageStr = checkCancel(await p.text({
      message: 'Allocated gp3 storage in GB:',
      initialValue: '20',
      validate(val) {
        const num = parseInt(val, 10);
        if (isNaN(num) || num < 20 || num > 1000) return 'Allocated storage must be between 20 and 1000 GB.';
      }
    }));
    rdsAllocatedStorage = parseInt(storageStr, 10);
  }

  // Step 10: Frontend Assets (Amplify)
  const enableAmplify = checkCancel(await p.confirm({
    message: 'Provision AWS Amplify for Next.js SSR frontend?',
    initialValue: false
  }));

  // Build Configuration Object matching root variables.tf
  const config = {
    client_name: clientName,
    environment: environment,
    aws_region: awsRegion,
    container_port: containerPort,
    enable_nat_gateway: enableNatGateway,
    certificate_arn: certificateArn,
    enable_swagger_protection: enableSwaggerProtection,
    swagger_whitelist_ips: swaggerWhitelistIps,
    enable_worker_container: enableWorkerContainer,
    ecs_task_cpu: ecsTaskCpu,
    ecs_task_memory: ecsTaskMemory,
    ecs_desired_count: ecsDesiredCount,
    enable_rds: enableRds,
    rds_instance_class: enableRds ? rdsInstanceClass : 'db.t4g.micro',
    rds_allocated_storage: enableRds ? rdsAllocatedStorage : 20,
    enable_amplify: enableAmplify
  };

  // Step 11: Calculate & Display Cost Breakdown
  const cost = calculateCost(config);
  p.note(formatCostBox(config, cost), 'Cost-Optimized Architecture Spec Sheet & Monthly Estimate');

  // Step 12: Pre-Flight AWS Credential Check
  const s = p.spinner();
  s.start('Running pre-flight AWS authentication check (aws sts get-caller-identity)...');
  const auth = checkAwsAuth();

  if (auth.valid) {
    s.stop(pc.green(`AWS Authenticated: Account ${pc.bold(auth.account)} | IAM: ${pc.dim(auth.arn)}`));
  } else {
    s.stop(pc.yellow('AWS Credentials Check: Inactive / Not Configured'));
    p.log.warn(pc.yellow(`Reason: ${auth.error}`));
    p.log.info(pc.cyan('Tip: Configure AWS credentials ($env:AWS_ACCESS_KEY_ID or aws configure) before running terraform apply.'));
  }

  // Step 13: Artifact Generation
  const clientsDir = path.resolve(__dirname, '..', 'clients');
  if (!fs.existsSync(clientsDir)) {
    fs.mkdirSync(clientsDir, { recursive: true });
  }

  const clientFileName = `${config.client_name}-${config.environment}.tfvars.json`;
  const clientFilePath = path.join(clientsDir, clientFileName);
  fs.writeFileSync(clientFilePath, JSON.stringify(config, null, 2), 'utf-8');

  p.log.success(`Saved client configuration: ${pc.bold(`clients/${clientFileName}`)}`);

  // Step 14: Confirmation & Execution Engine
  if (!auth.valid) {
    p.note(
      [
        pc.bold('Manual Provisioning Commands:'),
        '',
        `  ${pc.cyan(`terraform workspace select -or-create ${config.client_name}-${config.environment}`)}`,
        `  ${pc.cyan(`terraform plan -var-file=clients/${clientFileName} -out=tfplan`)}`,
        `  ${pc.cyan('terraform apply "tfplan"')}`,
        '',
        pc.dim('Configure your AWS credentials first, then execute the commands above.')
      ].join('\n'),
      'Next Steps'
    );
    p.outro(pc.green('Onboarding complete! Configuration file is ready in clients/'));
    return;
  }

  // AWS is authenticated: Offer automated execution
  const shouldApply = checkCancel(await p.confirm({
    message: 'Do you want to run Terraform plan & apply right now?',
    initialValue: false
  }));

  if (!shouldApply) {
    p.note(
      [
        pc.bold('Manual Provisioning Commands:'),
        '',
        `  ${pc.cyan(`terraform workspace select -or-create ${config.client_name}-${config.environment}`)}`,
        `  ${pc.cyan(`terraform plan -var-file=clients/${clientFileName} -out=tfplan`)}`,
        `  ${pc.cyan('terraform apply "tfplan"')}`
      ].join('\n'),
      'Ready to Deploy'
    );
    p.outro(pc.green('Client onboarded successfully!'));
    return;
  }

  // Automated Execution Flow
  const workspaceName = `${config.client_name}-${config.environment}`;
  p.log.step(`Setting up Terraform workspace: ${pc.bold(workspaceName)}`);

  try {
    const wsResult = spawnSync('terraform', ['workspace', 'select', '-or-create', workspaceName], {
      stdio: 'inherit',
      shell: true
    });
    if (wsResult.status !== 0) {
      throw new Error(`Terraform workspace selection exited with code ${wsResult.status}`);
    }

    p.log.step('Generating Terraform plan with client variables...');
    const planResult = spawnSync(
      'terraform',
      ['plan', `-var-file=clients/${clientFileName}`, '-out=tfplan'],
      { stdio: 'inherit', shell: true }
    );
    if (planResult.status !== 0) {
      throw new Error(`Terraform plan exited with code ${planResult.status}`);
    }

    const confirmExecute = checkCancel(await p.confirm({
      message: 'Review the plan above. Do you want to apply this tfplan to AWS now?',
      initialValue: true
    }));

    if (!confirmExecute) {
      p.log.info('Terraform apply skipped. You can apply later using: terraform apply "tfplan"');
      p.outro(pc.yellow('Deployment deferred.'));
      return;
    }

    p.log.step('Applying Terraform plan to AWS (this may take several minutes)...');
    const applyResult = spawnSync('terraform', ['apply', 'tfplan'], {
      stdio: 'inherit',
      shell: true
    });
    if (applyResult.status !== 0) {
      throw new Error(`Terraform apply exited with code ${applyResult.status}`);
    }

    p.outro(pc.green(`🎉 Success! Infrastructure for ${config.client_name} [${config.environment}] has been provisioned.`));
  } catch (err) {
    p.log.error(pc.red(`Execution Error: ${err.message}`));
    p.outro(pc.yellow('Terraform run halted. Check output above for details.'));
  }
}

// CLI Command Router
const args = process.argv.slice(2);

if (args.includes('--help') || args.includes('-h') || args[0] === 'help') {
  console.log(`
${pc.bold('AutoAWS CLI')} - Production AWS Infrastructure Provisioner

${pc.bold('Usage:')}
  node scripts/onboard.js
  npm run onboard

${pc.bold('Commands:')}
  onboard    Interactive onboarding wizard to size, price, and provision client workloads (default)
  help       Display this help message
`);
  process.exit(0);
}

runOnboard().catch(err => {
  p.log.error(pc.red(`Fatal Error: ${err.message}`));
  process.exit(1);
});

module.exports = { calculateCost, PRESETS, RATES };
