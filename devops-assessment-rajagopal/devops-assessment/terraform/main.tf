###############################################################################
# ROOT MAIN.TF — Production-like Web Application Architecture
# Author : Rajagopal | Assessment Submission
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — S3 backend (uncomment after bucket creation)
  # backend "s3" {
  #   bucket         = "raja-tfstate-prod"
  #   key            = "webapp/terraform.tfstate"
  #   region         = "ap-south-1"
  #   encrypt        = true
  #   dynamodb_table = "tf-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Rajagopal"
    }
  }
}

###############################################################################
# DATA SOURCES
###############################################################################
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

###############################################################################
# MODULE CALLS
###############################################################################

module "vpc" {
  source = "./modules/vpc"

  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.vpc.alb_sg_id
  certificate_arn   = var.certificate_arn
}

module "asg" {
  source = "./modules/asg"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  app_sg_id          = module.vpc.app_sg_id
  ami_id             = data.aws_ami.amazon_linux_2023.id
  instance_type      = var.instance_type
  key_name           = var.key_name
  target_group_arn   = module.alb.target_group_arn
  app_port           = var.app_port

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  ecr_repository_url = var.ecr_repository_url
  app_image_tag      = var.app_image_tag
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name    = var.project_name
  environment     = var.environment
  asg_name        = module.asg.asg_name
  alb_arn_suffix  = module.alb.alb_arn_suffix
  tg_arn_suffix   = module.alb.tg_arn_suffix
  alarm_email     = var.alarm_email
}
