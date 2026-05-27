###############################################################################
# MODULE: monitoring/main.tf
# Creates: CloudWatch Log Group, Dashboard, Alarms (CPU, 5xx, healthy hosts),
#          SNS topic for notifications
###############################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/${local.name_prefix}"
  retention_in_days = 14

  tags = { Name = "${local.name_prefix}-logs" }
}

# ── SNS Topic for Alarms ──────────────────────────────────────────────────────
resource "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

# 1. High CPU on ASG
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name_prefix}-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Average CPU above 80% for 4 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}

# 2. ALB 5xx errors
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "More than 10 ALB 5xx errors in 1 minute"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# 3. Target 5xx errors
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${local.name_prefix}-target-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "More than 10 target 5xx errors in 1 minute"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.tg_arn_suffix
  }
}

# 4. Unhealthy host count
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name_prefix}-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "One or more targets are unhealthy"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.tg_arn_suffix
  }
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x = 0; y = 0; width = 12; height = 6
        properties = {
          title  = "ALB Request Count"
          period = 60
          stat   = "Sum"
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]]
        }
      },
      {
        type = "metric"
        x = 12; y = 0; width = 12; height = 6
        properties = {
          title  = "ALB 4xx / 5xx Errors"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_4XX_Count", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type = "metric"
        x = 0; y = 6; width = 12; height = 6
        properties = {
          title  = "EC2 Average CPU"
          period = 60
          stat   = "Average"
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]]
        }
      },
      {
        type = "metric"
        x = 12; y = 6; width = 12; height = 6
        properties = {
          title  = "Healthy / Unhealthy Host Count"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount",   "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.tg_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.tg_arn_suffix]
          ]
        }
      },
      {
        type = "log"
        x = 0; y = 12; width = 24; height = 6
        properties = {
          title   = "Application Logs (last 20 lines)"
          query   = "SOURCE '${aws_cloudwatch_log_group.app.name}' | fields @timestamp, @message | sort @timestamp desc | limit 20"
          region  = "ap-south-1"
          view    = "table"
        }
      }
    ]
  })
}
