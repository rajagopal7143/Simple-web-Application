###############################################################################
# MODULE: asg/main.tf
# Creates: Launch Template, Auto Scaling Group, scaling policies,
#          IAM role for EC2 instances, and ECR pull permissions
###############################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── IAM Role for EC2 instances ────────────────────────────────────────────────
resource "aws_iam_role" "app" {
  name = "${local.name_prefix}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app.name
}

# ── Launch Template ───────────────────────────────────────────────────────────
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  vpc_security_group_ids = [var.app_sg_id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  monitoring {
    enabled = true   # detailed CloudWatch monitoring
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    ecr_repository_url = var.ecr_repository_url
    app_image_tag      = var.app_image_tag
    app_port           = var.app_port
    aws_region         = data.aws_region.current.name
    project_name       = var.project_name
    environment        = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${local.name_prefix}-app"
      Environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_region" "current" {}

# ── Auto Scaling Group ────────────────────────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name                = "${local.name_prefix}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [var.target_group_arn]
  health_check_type   = "ELB"
  health_check_grace_period = 120

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # Rolling updates — replace 50% at a time
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 60
    }
  }

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]   # let scaling policies own this
  }
}

# ── Target Tracking Scaling Policy — CPU ─────────────────────────────────────
resource "aws_autoscaling_policy" "cpu_scale_out" {
  name                   = "${local.name_prefix}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}

# ── Target Tracking Scaling Policy — ALB Request Count Per Target ─────────────
resource "aws_autoscaling_policy" "alb_request_scale" {
  name                   = "${local.name_prefix}-alb-request-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.alb_arn_suffix}/${var.tg_arn_suffix}"
    }
    target_value = 1000.0
  }
}
