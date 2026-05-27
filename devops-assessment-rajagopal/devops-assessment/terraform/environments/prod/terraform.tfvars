###############################################################################
# environments/prod/terraform.tfvars
###############################################################################

aws_region   = "ap-south-1"
project_name = "webapp"
environment  = "prod"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

# Compute
instance_type        = "t3.micro"
asg_min_size         = 1
asg_max_size         = 4
asg_desired_capacity = 2

# Application
app_port     = 80
app_image_tag = "latest"

key_name           = "my-keypair"
ecr_repository_url = "127214179413.dkr.ecr.ap-south-1.amazonaws.com/webapp"
certificate_arn    = "arn:aws:acm:ap-south-1:127214179413:certificate/..."

# Monitoring
alarm_email = "rajagopal7143@gmail.com"
