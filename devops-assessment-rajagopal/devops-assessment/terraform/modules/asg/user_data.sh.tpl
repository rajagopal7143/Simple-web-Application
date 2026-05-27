#!/bin/bash
###############################################################################
# user_data.sh.tpl — EC2 bootstrap script
# Installs Docker, pulls image from ECR, starts container
###############################################################################
set -euxo pipefail

# ── System updates ────────────────────────────────────────────────────────────
dnf update -y
dnf install -y docker amazon-cloudwatch-agent

# ── Start Docker ──────────────────────────────────────────────────────────────
systemctl enable --now docker

# ── CloudWatch Agent config ───────────────────────────────────────────────────
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWAGENT'
{
  "agent": { "run_as_user": "root" },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/aws/ec2/${project_name}-${environment}",
            "log_stream_name": "{instance_id}/app",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/docker.log",
            "log_group_name": "/aws/ec2/${project_name}-${environment}",
            "log_stream_name": "{instance_id}/docker"
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle","cpu_usage_user","cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      }
    },
    "namespace": "CWAgent/${project_name}"
  }
}
CWAGENT

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# ── Pull image from ECR ───────────────────────────────────────────────────────
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="${aws_region}"

aws ecr get-login-password --region $${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  "$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com"

ECR_IMAGE="${ecr_repository_url}:${app_image_tag}"

if [ -z "${ecr_repository_url}" ]; then
  # Fallback: run nginx as demo when no ECR repo is configured
  ECR_IMAGE="nginx:alpine"
fi

mkdir -p /var/log/app

# ── Run application container ─────────────────────────────────────────────────
docker run -d \
  --name webapp \
  --restart unless-stopped \
  -p ${app_port}:${app_port} \
  -v /var/log/app:/app/logs \
  -e APP_ENV=${environment} \
  -e PORT=${app_port} \
  --log-driver awslogs \
  --log-opt awslogs-region=$${AWS_REGION} \
  --log-opt awslogs-group=/aws/ec2/${project_name}-${environment} \
  --log-opt awslogs-stream=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)/container \
  $${ECR_IMAGE}

echo "Bootstrap complete: $(date)" >> /var/log/app/bootstrap.log
