# Production-Like Web Application — Cloud Architecture Assessment

**Author:** Rajagopal  
**Stack:** AWS · Terraform · Docker · GitHub Actions · CloudWatch  
**Region:** ap-south-1 (Mumbai)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [Prerequisites](#prerequisites)
4. [Quickstart — Deploy from Scratch](#quickstart--deploy-from-scratch)
5. [Design Decisions](#design-decisions)
6. [Trade-offs Considered](#trade-offs-considered)
7. [CI/CD Pipeline](#cicd-pipeline)
8. [Monitoring Implementation](#monitoring-implementation)
9. [Cost Awareness & Optimization](#cost-awareness--optimization)
10. [Security Hardening](#security-hardening)
11. [Known Limitations & Next Steps](#known-limitations--next-steps)

---

## Architecture Overview

```
Internet users
      │  HTTPS / HTTP
      ▼
Application Load Balancer (public subnets, 2 AZs)
      │
      ├──► EC2 Instance (AZ-a, private subnet)  ┐
      │     └── Docker container (Flask app)     │  Auto Scaling Group
      └──► EC2 Instance (AZ-b, private subnet)  ┘  (min 1 · desired 2 · max 4)
                │
                ├── NAT Gateway → Internet (ECR pull, OS updates)
                ├── CloudWatch Agent → Logs + Metrics
                └── SSM Session Manager (no bastion needed)

CI/CD: GitHub → GitHub Actions → ECR → Terraform Apply → ASG Instance Refresh
```

### Core Components

| Component | Service | Purpose |
|---|---|---|
| Networking | VPC, Subnets, IGW, NAT GW | Isolated network with public/private tiers |
| Compute | EC2 + Auto Scaling Group | Horizontally scalable app layer |
| Load Balancing | Application Load Balancer | Traffic distribution, TLS termination |
| Containerisation | Docker on EC2 | Consistent runtime, easy deployments |
| Image Registry | Amazon ECR | Private Docker registry |
| IaC | Terraform | Reproducible, version-controlled infra |
| CI/CD | GitHub Actions | Automated test → build → deploy |
| Monitoring | CloudWatch Logs, Metrics, Alarms | Observability and alerting |
| Notifications | SNS → Email | Alarm delivery |

---

## Repository Structure

```
.
├── app/
│   ├── app.py                  # Flask application (demo)
│   ├── Dockerfile              # Multi-stage, non-root, IMDSv2-aware
│   └── requirements.txt
│
├── terraform/
│   ├── main.tf                 # Root module — wires all sub-modules
│   ├── variables.tf            # Input variable definitions
│   ├── outputs.tf              # Output values (ALB DNS, ASG name, etc.)
│   │
│   ├── modules/
│   │   ├── vpc/                # VPC, subnets, IGW, NAT, route tables, SGs
│   │   ├── alb/                # ALB, Target Group, listeners, access log S3
│   │   ├── asg/                # Launch Template, ASG, scaling policies, IAM
│   │   └── monitoring/         # Log Group, Dashboard, Alarms, SNS
│   │
│   └── environments/
│       └── prod/
│           └── terraform.tfvars
│
├── docs/
│   └── architecture-diagram.png   # (exported separately)
│
└── .github/
    └── workflows/
        └── deploy.yml          # CI/CD pipeline definition
```

---

## Prerequisites

| Tool | Version |
|---|---|
| Terraform | >= 1.6.0 |
| AWS CLI | >= 2.x |
| Docker | >= 24.x |
| Git | any recent |

AWS IAM permissions needed: `ec2:*`, `iam:*` (role/profile), `autoscaling:*`, `elasticloadbalancing:*`, `ecr:*`, `cloudwatch:*`, `logs:*`, `sns:*`, `s3:*`

---

## Quickstart — Deploy from Scratch

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/devops-assessment.git
cd devops-assessment
```

### 2. Configure AWS credentials

```bash
aws configure
# or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_DEFAULT_REGION
```

### 3. Create ECR repository (one-time)

```bash
aws ecr create-repository --repository-name webapp --region ap-south-1
```

### 4. Build & push the Docker image

```bash
cd app

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${AWS_ACCOUNT}.dkr.ecr.ap-south-1.amazonaws.com/webapp"

aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin "${ECR_REPO}"

docker build -t "${ECR_REPO}:latest" .
docker push "${ECR_REPO}:latest"
```

### 5. Edit terraform.tfvars

```bash
# terraform/environments/prod/terraform.tfvars
ecr_repository_url = "<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/webapp"
alarm_email        = "your@email.com"
# optional: key_name, certificate_arn
```

### 6. Deploy infrastructure

```bash
cd terraform

terraform init
terraform plan -var-file="environments/prod/terraform.tfvars"
terraform apply -var-file="environments/prod/terraform.tfvars"
```

### 7. Access the application

```bash
terraform output alb_dns_name
# Open http://<alb-dns-name> in a browser
```

### Tear down

```bash
terraform destroy -var-file="environments/prod/terraform.tfvars"
```

---

## Design Decisions

### 1. EC2 + ASG instead of ECS/Fargate

**Why:** The assessment asks for a Docker container running on EC2 instances with an ASG. This is also the setup most common in SME environments and it demonstrates a broader set of concepts (launch template, user data bootstrapping, IMDSv2, CloudWatch Agent, SSM) compared to managed container services.

**If building for production at scale**, ECS Fargate would be the natural next step — it eliminates AMI management, simplifies deployments to task definitions, and scales faster.

### 2. Two Availability Zones

Every tier — public subnets, private subnets, NAT Gateways, and EC2 instances — is spread across AZ-a and AZ-b. This means the application can tolerate a full AZ failure with no manual intervention. Two AZs are the minimum for HA; three AZs could be added by extending the `availability_zones` list.

### 3. Private Subnets for Application Servers

EC2 instances sit in private subnets with no direct internet exposure. Outbound internet access (for ECR pulls, CloudWatch API, OS updates) goes through NAT Gateways in the public subnets. This limits the blast radius of a compromised instance.

### 4. Security Group Layering

- **ALB Security Group** — allows inbound 80/443 from `0.0.0.0/0`; all egress allowed.
- **App Security Group** — allows inbound on port 80 *only from the ALB security group*. No inbound from the internet. No SSH from the internet; access is via SSM Session Manager.

This follows least-privilege networking — the app tier is unreachable except through the load balancer.

### 5. IMDSv2 Enforced

The Launch Template sets `http_tokens = "required"`, enforcing IMDSv2 (token-based metadata). This prevents SSRF attacks from accessing EC2 metadata, which is a common cloud security finding.

### 6. Multi-Stage Docker Build

The Dockerfile uses a `builder` stage (installs pip dependencies) and a lean `runtime` stage. The resulting image is significantly smaller than a single-stage build because build tools and pip cache are discarded. The app runs as a non-root user (`app:app`).

### 7. ASG Instance Refresh for Zero-Downtime Deployments

New deployments trigger an ASG Instance Refresh (rolling replace) with `MinHealthyPercentage: 50`. This means at least one instance is always serving traffic while the other is replaced. The ALB health check gate ensures traffic is only routed to instances that have passed the `/health` check.

### 8. Terraform Module Structure

The code is split into four focused modules (`vpc`, `alb`, `asg`, `monitoring`). This makes each module independently testable, reusable across environments, and easier to review. A `environments/prod/terraform.tfvars` file holds environment-specific values while the module code stays generic.

### 9. ALB Access Logs to S3

ALB access logs are written to a dedicated S3 bucket with a 30-day lifecycle rule. This provides a complete audit trail of every request with minimal cost, and enables post-incident analysis without any agent on the instance.

---

## Trade-offs Considered

| Decision | Alternative Considered | Trade-off Made |
|---|---|---|
| **EC2 + Docker on ASG** | ECS Fargate | More control, more ops burden. ECS would eliminate AMI patching but adds learning curve for the assessment scope. |
| **One NAT GW per AZ** | Single NAT GW | Higher cost (~$32/month each) but no single point of failure for outbound connectivity. For dev/staging, one NAT GW saves ~$32/month. |
| **t3.micro instance type** | t3.small / t3.medium | Free-tier eligible, cheapest option for demo. Upgrade to t3.small (2 GiB) if the app OOMs. |
| **GitHub Actions** | Jenkins, GitLab CI, CodePipeline | GitHub Actions is zero-infrastructure, has an excellent AWS action ecosystem, and is familiar to most engineers. Jenkins would add an EC2 server to manage. |
| **CloudWatch for monitoring** | Prometheus + Grafana | CloudWatch is fully managed and has zero setup overhead. Prometheus/Grafana offers richer querying and dashboarding but requires running additional workloads (or using Amazon Managed Prometheus). |
| **HTTP → HTTPS redirect at ALB** | HTTPS-only (reject HTTP) | Redirect is more user-friendly. In a real deployment, the `certificate_arn` variable should be set and HTTP → HTTPS redirect enforced. |
| **S3 remote state (commented out)** | Local `.tfstate` | Local state is fine for a single developer. The S3 + DynamoDB backend config is included (commented) for team use. |
| **desired_capacity = 2** | desired_capacity = 1 | Costs one extra instance (~$8/month for t3.micro) but provides fault tolerance across AZs out of the box. |

---

## CI/CD Pipeline

The pipeline runs on every push to `main` and on pull requests.

```
Push to main
│
├─ [PR only] Terraform Plan → uploads plan as artifact
│
├─ Job: test
│   ├── flake8 lint
│   └── pytest (if tests exist)
│
├─ Job: build  (main branch only, after test passes)
│   ├── Configure AWS credentials (from GitHub Secrets)
│   ├── Login to ECR
│   └── docker build + push (tagged with git SHA + latest)
│
└─ Job: deploy  (main branch only, after build, requires "production" env approval)
    ├── terraform init + apply (updates Launch Template if user_data changed)
    ├── Start ASG Instance Refresh (rolling, 50% min healthy)
    └── Poll until refresh status = Successful
```

### Required GitHub Secrets

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user or OIDC role |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret |

**Production recommendation:** Replace the long-lived IAM credentials with an OIDC identity provider (GitHub → AWS). This eliminates static secrets entirely and is a one-time setup in the AWS Console.

---

## Monitoring Implementation

### Logs

- Application container logs → CloudWatch via Docker `awslogs` log driver
- System/host metrics → CloudWatch Agent (CPU, memory, disk)
- ALB access logs → S3 bucket

Log Group: `/aws/ec2/webapp-prod`
Retention: 14 days

### Metrics & Alarms

| Alarm | Condition | Action |
|---|---|---|
| `webapp-prod-high-cpu` | ASG average CPU ≥ 80% for 4 min | SNS → email |
| `webapp-prod-alb-5xx` | ALB 5xx count > 10 per minute | SNS → email |
| `webapp-prod-target-5xx` | Target 5xx count > 10 per minute | SNS → email |
| `webapp-prod-unhealthy-hosts` | UnhealthyHostCount ≥ 1 | SNS → email |

### Dashboard

A CloudWatch Dashboard (`webapp-prod-dashboard`) is provisioned automatically with widgets for:
- ALB request count over time
- ALB 4xx / 5xx error rates
- EC2 average CPU utilisation
- Healthy / Unhealthy host count
- Live application log tail (last 20 lines)

### Auto-scaling Policies

Two Target Tracking policies keep the fleet right-sized automatically:
- CPU utilisation target: **60%** — scale out/in based on average CPU
- ALB request count target: **1000 requests/target** — scale out under traffic spikes

---

## Cost Awareness & Optimization

### Estimated Monthly Cost (prod, ap-south-1, 2 instances)

| Resource | Unit cost | Est. monthly |
|---|---|---|
| EC2 t3.micro × 2 | $0.0116/hr | ~$17 |
| NAT Gateway × 2 | $0.045/hr + data | ~$65 (with data) |
| ALB | $0.008/LCU-hr + $0.018/hr | ~$16 |
| CloudWatch Logs (5 GB) | $0.57/GB | ~$3 |
| ECR (1 GB) | $0.10/GB | ~$0.10 |
| S3 (ALB logs) | negligible | <$1 |
| **Total** | | **~$102/month** |

> NAT Gateway dominates. In non-prod, use a single NAT GW and save ~$32/month.

### Optimization Strategies Applied

**Right-sizing:** t3.micro chosen as the smallest viable instance. `desired_capacity = 2` is the minimum for AZ fault tolerance. Target tracking scaling automatically returns to minimum when traffic drops.

**NAT Gateway trade-off documented:** Two NAT GWs cost more but eliminate the outbound connectivity SPOF. For dev/staging, a single NAT GW or NAT instance (free-tier eligible) significantly reduces cost.

**ALB access log lifecycle:** Logs expire after 30 days automatically. Adjust the `days` value to balance retention requirements vs. storage cost.

**gp3 EBS volumes:** Launch Template uses gp3 (not gp2). gp3 is 20% cheaper than gp2 for the same performance baseline.

**Scheduled scaling (optional):** For workloads with known traffic patterns (e.g. business-hours only), add a `aws_autoscaling_schedule` resource to scale down at night and scale up in the morning, cutting EC2 cost by up to 50%.

**Savings Plans (production):** EC2 Savings Plans or Compute Savings Plans provide up to 66% discount for a 1- or 3-year commitment on consistent baseline capacity.

**VPC Endpoints (cost + security):** Adding `com.amazonaws.ap-south-1.ecr.api` and `com.amazonaws.ap-south-1.s3` VPC Gateway endpoints eliminates NAT GW data-processing charges for ECR pulls and S3 writes, which can be a significant saving in high-deployment environments.

---

## Security Hardening

- IMDSv2 enforced on all instances (prevents SSRF metadata theft)
- Instances in private subnets — no public IP, no direct internet inbound
- SSH not exposed; access via SSM Session Manager only
- Encrypted EBS root volumes (gp3, encrypted=true)
- IAM instance profile scoped to ECR read, SSM, and CloudWatch only
- ALB drops invalid header fields (`drop_invalid_header_fields = true`)
- ALB uses TLS 1.3 security policy when HTTPS is enabled
- Docker runs as non-root user

---

## Known Limitations & Next Steps

1. **No RDS in this submission** — the `modules/rds` folder is scaffolded but not fully built. A real application would add RDS MySQL/PostgreSQL in private subnets with a separate security group.
2. **HTTPS requires a pre-created ACM certificate** — set `certificate_arn` in tfvars and the ALB listener will switch to HTTPS automatically.
3. **No WAF** — AWS WAF can be attached to the ALB for DDoS and OWASP Top 10 protection.
4. **State locking** — The S3 backend with DynamoDB table is commented out. Uncomment and create the S3 bucket before running in a team environment.
5. **ECR image scanning** — Enable ECR scan-on-push to catch CVEs in the Docker image automatically.
6. **OIDC for GitHub Actions** — Replace static IAM credentials with GitHub OIDC for a more secure CI/CD setup.
