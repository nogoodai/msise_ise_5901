terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  default     = "my-ssh-key"
}

variable "domain_name" {
  description = "Domain name for Route 53"
  default     = "example.com"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.micro"
}

variable "rds_engine" {
  description = "RDS engine type"
  default     = "mysql"
}

variable "rds_engine_version" {
  description = "RDS engine version"
  default     = "5.7"
}

variable "alb_name" {
  description = "Name of the Application Load Balancer"
  default     = "wp-alb"
}

variable "cloudfront_domain_name" {
  description = "Domain name for CloudFront"
  default     = "cdn.example.com"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for static assets"
  default     = "wp-static-assets"
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
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "WordPressIGW"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name        = "public-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "private-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "web_server" {
  name        = "web-server-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.main.id

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
    cidr_blocks = ["0.0.0.0/0"] # Replace with specific IPs for production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "web-server-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "rds" {
  name        = "rds-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "rds-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

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
    Name        = "alb-sg"
    Environment = var.environment
    Project     = var.project
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "wordpress" {
  name_prefix          = "wordpress-lc-"
  image_id             = var.ami_id
  instance_type        = var.instance_type
  key_name             = var.key_name
  security_groups      = [aws_security_group.web_server.id]
  user_data            = file("wordpress-install.sh")
  iam_instance_profile = aws_iam_instance_profile.wordpress.name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress" {
  name                 = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress.name
  vpc_zone_identifier  = aws_subnet.public[*].id
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2

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

# RDS Instance for WordPress Database
resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name        = "wordpress-db-subnet-group"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_db_instance" "wordpress" {
  identifier             = "wordpress-db"
  engine                 = var.rds_engine
  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance_class
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = "wordpress"
  username               = "admin"
  password               = "password123" # Use a secret manager in production
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
    Project     = var.project
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "wordpress-alb"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 30
    interval            = 60
    matcher             = "200"
  }

  tags = {
    Name        = "wordpress-tg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lb_listener" "wordpress_http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_autoscaling_attachment" "wordpress_asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  lb_target_group_arn    = aws_lb_target_group.wordpress.arn
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_lb.wordpress.dns_name
    origin_id   = "ALB"

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
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
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
    Name        = "wordpress-cloudfront"
    Environment = var.environment
    Project     = var.project
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "static_assets" {
  bucket = var.s3_bucket_name
  acl    = "private"

  tags = {
    Name        = "wordpress-static-assets"
    Environment = var.environment
    Project     = var.project
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_route53_record" "alb" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "wordpress.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress.dns_name
    zone_id                = aws_lb.wordpress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cloudfront" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.cloudfront_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

# IAM Role and Instance Profile for EC2 Instances
resource "aws_iam_role" "wordpress" {
  name = "wordpress-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "wordpress-ec2-role"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "wordpress_s3" {
  role       = aws_iam_role.wordpress.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "wordpress" {
  name = "wordpress-instance-profile"
  role = aws_iam_role.wordpress.name
}

# Monitoring and Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "wordpress-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }

  tags = {
    Name        = "wordpress-cpu-utilization-alarm"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_utilization" {
  alarm_name          = "wordpress-rds-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors rds cpu utilization"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress.identifier
  }

  tags = {
    Name        = "wordpress-rds-cpu-utilization-alarm"
    Environment = var.environment
    Project     = var.project
  }
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

output "s3_bucket_arn" {
  value = aws_s3_bucket.static_assets.arn
}

output "route53_zone_id" {
  value = aws_route53_zone.main.zone_id
}
