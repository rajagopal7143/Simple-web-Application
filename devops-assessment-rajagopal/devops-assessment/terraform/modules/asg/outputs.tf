output "asg_name"              { value = aws_autoscaling_group.app.name }
output "launch_template_id"   { value = aws_launch_template.app.id }
output "app_iam_role_arn"     { value = aws_iam_role.app.arn }
