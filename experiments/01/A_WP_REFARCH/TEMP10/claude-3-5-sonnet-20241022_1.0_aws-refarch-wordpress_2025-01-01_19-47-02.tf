# Provider and terraform configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  default = "us-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "environment" {
  default = "production"
}

variable "domain_name" {
  type = string
}

variable "db_password" {
  type = string
  sensitive = true
}

# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "wordpress-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "wordpress-private-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "wordpress-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "alb" {
  name        = "wordpress-alb-sg"
  description = "Security group for WordPress ALB"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "wordpress" {
  name        = "wordpress-ec2-sg"
  description = "Security group for WordPress instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "wordpress-rds-sg"
  description = "Security group for WordPress RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress.id]
  }
}

# RDS Instance
resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "wordpress" {
  identifier           = "wordpress-db"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.small"
  allocated_storage   = 20
  storage_type        = "gp2"
  multi_az            = true
  name                = "wordpress"
  username            = "wordpress"
  password            = var.db_password
  skip_final_snapshot = true

  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"

  tags = {
    Name = "wordpress-db"
  }
}

# Application Load Balancer
resource "aws_lb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = aws_subnet.public[*].id

  tags = {
    Name = "wordpress-alb"
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

# Auto Scaling Group
resource "aws_launch_template" "wordpress" {
  name_prefix   = "wordpress-lt"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.small"

  network_interfaces {
    associate_public_ip_address = false
    security_groups            = [aws_security_group.wordpress.id]
  }

  user_data = base64encode(templatefile("${path.module}/wordpress-init.sh", {
    db_host     = aws_db_instance.wordpress.endpoint
    db_name     = aws_db_instance.wordpress.name
    db_user     = aws_db_instance.wordpress.username
    db_password = var.db_password
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "wordpress-instance"
    }
  }
}

resource "aws_autoscaling_group" "wordpress" {
  desired_capacity    = 2
  max_size           = 4
  min_size           = 1
  target_group_arns  = [aws_lb_target_group.wordpress.arn]
  vpc_zone_identifier = aws_subnet.private[*].id

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "wordpress-asg"
    propagate_at_launch = true
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "wordpress_assets" {
  bucket = aws_s3_bucket.wordpress_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress" {
  enabled = true
  aliases = [var.domain_name]

  origin {
    domain_name = aws_lb.wordpress.dns_name
    origin_id   = aws_lb.wordpress.name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = aws_lb.wordpress.name
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress.arn
    ssl_support_method  = "sni-only"
  }
}

# Route 53 Configuration
resource "aws_route53_zone" "wordpress" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "wordpress-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/EC2"
  period             = "300"
  statistic          = "Average"
  threshold          = "80"
  alarm_description  = "This metric monitors EC2 CPU utilization"
  alarm_actions      = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "wordpress-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
}

# Outputs
output "alb_dns_name" {
  value = aws_lb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}
