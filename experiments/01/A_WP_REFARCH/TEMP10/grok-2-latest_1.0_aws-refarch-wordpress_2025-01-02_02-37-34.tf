terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "allowed_ssh_cidr" {
  description = "CIDR block for SSH access"
  default     = "0.0.0.0/0"
}

variable "wordpress_ami" {
  description = "AMI ID for WordPress instances"
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "rds_instance_class" {
  description = "RDS instance type"
  default     = "db.t2.micro"
}

variable "domain_name" {
  description = "Domain name for Route 53"
  default     = "example.com"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for static assets"
  default     = "wordpress-static-assets"
}

variable "environment" {
  description = "Environment tag"
  default     = "production"
}

variable "project" {
  description = "Project tag"
  default     = "wordpress"
}

# Provider
provider "aws" {
  region = var.region
}

# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "WordPressIGW"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "WordPressPublicSubnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "WordPressPrivateSubnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }

  tags = {
    Name        = "WordPressPublicRouteTable"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for WordPress web servers"
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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressWebServerSG"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressRDSSG"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "WordPressELBSG"
  description = "Security group for WordPress ELB"
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

  tags = {
    Name        = "WordPressELBSG"
    Environment = var.environment
    Project     = var.project
  }
}

# EC2 Instances and Auto Scaling
resource "aws_launch_template" "wordpress_lt" {
  name_prefix   = "WordPressLaunchTemplate"
  image_id      = var.wordpress_ami
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.web_server_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd php php-mysqlnd
    systemctl start httpd
    systemctl enable httpd
    # Install WordPress
    # ... (WordPress installation script here)
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "WordPressInstance"
      Environment = var.environment
      Project     = var.project
    }
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "WordPressASG"
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  min_size            = 1
  max_size            = 3
  desired_capacity    = 2

  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123" # Use AWS Secrets Manager for production
  parameter_group_name = "default.mysql5.7"
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  skip_final_snapshot  = true

  tags = {
    Name        = "WordPressDB"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name        = "WordPressRDS-SubnetGroup"
    Environment = var.environment
    Project     = var.project
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_alb" {
  name               = "WordPressALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name        = "WordPressALB"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "WordPressTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }

  tags = {
    Name        = "WordPressTargetGroup"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lb_listener" "wordpress_listener" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  lb_target_group_arn    = aws_lb_target_group.wordpress_tg.arn
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "WordPressALB"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressALB"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "WordPressCDN"
    Environment = var.environment
    Project     = var.project
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "WordPressAssets"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_bucket_public_access_block" "wordpress_assets_block" {
  bucket = aws_s3_bucket.wordpress_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name

  tags = {
    Name        = "WordPressZone"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "wordpress.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cdn" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# Monitoring and CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_alarm" {
  alarm_name          = "WordPressHighCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:WordPressAlerts"] # Replace with actual SNS topic ARN

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress_asg.name
  }

  tags = {
    Name        = "WordPressCPUAlarm"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_utilization_alarm" {
  alarm_name          = "WordPressRDSHighCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors rds cpu utilization"
  alarm_actions       = ["arn:aws:sns:us-east-1:123456789012:WordPressAlerts"] # Replace with actual SNS topic ARN

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress_db.id
  }

  tags = {
    Name        = "WordPressRDSAlarm"
    Environment = var.environment
    Project     = var.project
  }
}

# Outputs
output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_assets.arn
}