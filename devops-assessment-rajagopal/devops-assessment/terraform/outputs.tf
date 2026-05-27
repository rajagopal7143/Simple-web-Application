###############################################################################
# OUTPUTS.TF
###############################################################################

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.asg.asg_name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name for the application"
  value       = module.monitoring.log_group_name
}

output "sns_alarm_topic" {
  description = "SNS topic ARN for alarm notifications"
  value       = module.monitoring.sns_topic_arn
}
