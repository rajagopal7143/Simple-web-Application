###############################################################################
# MODULE: asg/variables.tf
###############################################################################
variable "project_name"        { type = string }
variable "environment"         { type = string }
variable "vpc_id"              { type = string }
variable "private_subnet_ids"  { type = list(string) }
variable "app_sg_id"           { type = string }
variable "ami_id"              { type = string }
variable "instance_type"       { type = string }
variable "key_name"            { type = string  default = "" }
variable "target_group_arn"    { type = string }
variable "app_port"            { type = number  default = 80 }
variable "min_size"            { type = number  default = 1 }
variable "max_size"            { type = number  default = 4 }
variable "desired_capacity"    { type = number  default = 2 }
variable "ecr_repository_url"  { type = string  default = "" }
variable "app_image_tag"       { type = string  default = "latest" }
variable "alb_arn_suffix"      { type = string  default = "" }
variable "tg_arn_suffix"       { type = string  default = "" }
