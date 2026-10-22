# AutoAWS

> **Cost-Optimized, Production-Grade AWS Infrastructure Engine in Terraform**  
> Architected for Dual-Container Node.js backends (`backend-api-container` + `backend-worker-container`) on AWS ECS Fargate, Zero-NAT Cost Optimization, Application Load Balancer with TLS 1.3/1.2 and Swagger `/api-docs/*` protection, PostgreSQL in isolated subnets, hierarchical Secrets Manager (`<project>/<env>/app_secrets`), and keyless GitHub Actions CI/CD.

---

## 1. Cost-Optimized Zero-NAT Architecture

### Why Omit the NAT Gateway?
In traditional AWS architectures, ECS tasks reside in private subnets and require an **AWS NAT Gateway** ($32.85/month base + data processing fees) to pull Docker images from ECR, fetch credentials from AWS Secrets Manager, and stream logs to CloudWatch.

AutoAWS eliminates the NAT Gateway by default (`enable_nat_gateway = false`), deploying ECS tasks directly into public subnets with `assign_public_ip = true`:
- **Outbound Traffic:** Flows directly through the free Internet Gateway (IGW) for ECR pulls, Secrets Manager calls, and third-party APIs (Stripe, SendGrid, etc.).
- **Cost:** AWS charges $0.005/hr for public IPv4 (~$3.65/month per running task) vs. **$32.85/month** for a single NAT Gateway—saving **~$29.20/month per environment** (~$60–$90/month across dev/staging/prod).

### Is It Secure? (Zero-Trust Security Group Chaining)
Yes. AWS Security Groups are stateful firewalls. Fargate tasks in the public subnet block all inbound traffic from the public internet:

```
[ Public Internet (0.0.0.0/0) ]
              │
              ▼ (Inbound Ports 80 & 443 only)
┌──────────────────────────────────────┐
│  ALB Security Group (ALB-SG)         │
└──────────────────────────────────────┘
              │
              ▼ (Inbound Port 3000 STRICTLY from ALB-SG ID - 0.0.0.0/0 BLOCKED)
┌──────────────────────────────────────┐
│  ECS Security Group (ECS-SG)         │  assign_public_ip = true
└──────────────────────────────────────┘  (Egress 0.0.0.0/0 to IGW)
              │
              ▼ (Inbound Port 5432 STRICTLY from ECS-SG ID)
┌──────────────────────────────────────┐
│  RDS Security Group (RDS-SG)         │  publicly_accessible = false
└──────────────────────────────────────┘  (Isolated Database Subnets, No IGW Route)
```

---

## 2. Application Load Balancer & Swagger Security

The ALB module enforces:
1. **HTTP 80 Listener:** Automatic `HTTP_301` redirect to `HTTPS://#{host}:443/#{path}?#{query}`.
2. **HTTPS 443 Listener:** Modern TLS policy `ELBSecurityPolicy-TLS13-1-2-Res-2021-06` with default forwarding to `<project>-<env>-tg`. Turnkey auto-generated ACM certificate fallback if no external ACM ARN is provided.
3. **Swagger Protection Rules for `/api-docs/*`:**
   - **Priority 10 (`Swagger-Rules`):** Path `/api-docs/*` AND Source IP matching configurable CIDR whitelist -> Forward to target group.
   - **Priority 20:** Path `/api-docs/*` -> Fixed response `403 Forbidden` (`text/plain`).
   - **Default Action:** Catch-all traffic -> Forward to target group.

---

## 3. Hierarchical Secrets Manager Convention

All environments (`dev`, `staging`, `production`) follow a strict hierarchical naming convention:
- **Secret Path:** `<project>/<env>/app_secrets` (e.g. `backend/dev/app_secrets`, `backend/prod/app_secrets`).
- **ECS Injection:** ECS Task Definition maps the entire secret payload into the container environment variable `APP_SECRETS` using `secrets.valueFrom = <secret_arn>`.

---

## 4. Dual-Container ECS Fargate Task Definition

Co-locates two containers within the same task:
1. **`backend-api-container` (Essential):**
   - Port 3000 (`containerPort: 3000`, `hostPort: 3000`, `appProtocol: http`).
   - Command: `["sh", "-c", "node dist/server.js"]`
   - Health Check: Native Node.js HTTP ping to `http://127.0.0.1:3000/health`.
   - CloudWatch Logs: `/ecs/<project>-<env>-api` (auto-created).
2. **`backend-worker-container` (Non-Essential):**
   - Command: `["node", "dist/worker.js"]`
   - Starts **only** after the API container is healthy:
     ```json
     "dependsOn": [{ "containerName": "backend-api-container", "condition": "HEALTHY" }]
     ```
   - CloudWatch Logs: `/ecs/<project>-<env>-worker`.

### Resource Allocation Split:
| Environment | Total Task | API Container | Worker Container | Desired Tasks |
| :--- | :--- | :--- | :--- | :--- |
| **dev** | 512 CPU / 1024 MB | 384 CPU / 768 MB | 128 CPU / 256 MB | 1 |
| **staging** | 512 CPU / 1024 MB | 384 CPU / 768 MB | 128 CPU / 256 MB | 1 |
| **production** | 1024 CPU / 2048 MB | 768 CPU / 1536 MB | 256 CPU / 512 MB | 2 (Multi-AZ) |

---

## 5. Repository Structure

```text
AutoAWS/
├── bin/
│   └── autoaws.js               # Interactive CLI onboarding engine (@clack/prompts)
├── clients/
│   ├── tapsy-dev.tfvars.json    # Dev client configuration
│   ├── tapsy-prod.tfvars.json   # Production client configuration
│   └── pulse-staging.tfvars.json
├── modules/
│   ├── vpc/                     # IGW, public subnets, isolated DB subnets, chained SGs, zero-NAT
│   ├── alb/                     # ALB, HTTPS 301 redirect, TLS 1.3/1.2, Swagger IP whitelist rules
│   ├── ecs/                     # Dual-container task definition, Fargate service, ECR, CloudWatch, IAM
│   ├── rds/                     # PostgreSQL 16 in isolated subnets + <project>/<env>/app_secrets
│   ├── storage_cdn/             # Private S3 media bucket + CloudFront OAC SigV4
│   ├── amplify_nextjs/          # Optional Next.js SSR frontend
│   └── github_repos/            # Keyless GitHub Actions IAM OIDC deployer role
├── provider.tf                  # AWS, Random, TLS providers
├── variables.tf                 # Parameterized root variables with slug & environment validations
├── main.tf                      # Root infrastructure orchestrator
├── outputs.tf                   # Comprehensive infrastructure outputs
├── terraform.tfvars             # Active configuration file
└── terraform.tfvars.example     # Reference template
```

---

## 6. Quick Start

### 1. Interactive Onboarding Wizard
Run the CLI wizard to size workloads, calculate live cost estimates, and generate client configurations:
```bash
npm run onboard
# or
node bin/autoaws.js onboard
```

### 2. Manual Provisioning via Terraform
```bash
# 1. Initialize working directory
terraform init

# 2. Select or create environment workspace
terraform workspace select -or-create dev

# 3. Generate plan
terraform plan -var-file=terraform.tfvars -out=tfplan

# 4. Apply to AWS
terraform apply "tfplan"
```
