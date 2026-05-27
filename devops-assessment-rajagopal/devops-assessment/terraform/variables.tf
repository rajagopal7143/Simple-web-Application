###############################################################################
# VARIABLES.TF
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project identifier used in resource naming"
  type        = string
  default     = "webapp"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# ── Networking ──────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ── Compute ──────────────────────────────────────────────────────────────────
variable "instance_type" {
  description = "EC2 instance type for application servers"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access (leave empty to disable)"
  type        = string
  default     = ""
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

# ── Application ──────────────────────────────────────────────────────────────
variable "app_port" {
  description = "Port the application container listens on"
  type        = number
  default     = 80
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the application image"
  type        = string
  default     = ""
}

variable "app_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

# ── TLS / ALB ────────────────────────────────────────────────────────────────
variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (leave empty for HTTP-only)"
  type        = string
  default     = ""
}

# ── Monitoring ───────────────────────────────────────────────────────────────
variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = "rajagopal@example.com"
}
