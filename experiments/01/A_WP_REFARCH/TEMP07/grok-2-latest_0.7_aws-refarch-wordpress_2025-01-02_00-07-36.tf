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
  type        = list(string)
  description = "Public subnet CIDRs"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDRs"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones for subnets"
  default     = ["us-west-2a", "us-west-2b"]
}

variable "admin_ip" {
  description = "Administrator IP address for SSH access"
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "db_instance_type" {
  description = "RDS instance type"
  default     = "db.t2.micro"
}

variable "domain_name" {
  description = "Domain name for Route 53"
  default     = "example.com"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for static assets"
  default     = "wp-static-assets"
}

# Provider
provider "aws" {
  region = var.region
}

# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPress"
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
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPressPrivateSubnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
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
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  description = "Security group for web servers"
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
    cidr_blocks = [var.admin_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WebServerSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Security group for RDS"
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
    Name        = "RDSSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "elb_sg" {
  name        = "elb-sg"
  description = "Security group for ELB"
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
    Name        = "ELBSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix   = "wordpress-lc-"
  image_id      = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysqlnd
              systemctl start httpd
              systemctl enable httpd
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier  = aws_subnet.public_subnets[*].id
  min_size             = 1
  max_size             = 3
  health_check_type    = "ELB"
  target_group_arns    = [aws_lb_target_group.wordpress_tg.arn]

  tags = [
    {
      key                 = "Name"
      value               = "WordPressInstance"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "Production"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "WordPress"
      propagate_at_launch = true
    }
  ]
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress_db" {
  identifier             = "wordpress-db"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = var.db_instance_type
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = "wordpressdb"
  username               = "admin"
  password               = "password123" # Use a secret manager in production
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name        = "WordPressDB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name        = "WordPressALB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 30
    interval            = 60
    matcher             = "200"
  }

  tags = {
    Name        = "WordPressTG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "ALBOrigin"

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
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALBOrigin"

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
    Name        = "WordPressCDN"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "static_assets" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "WordPressStaticAssets"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket_public_access_block" "static_assets_block_public" {
  bucket = aws_s3_bucket.static_assets.id

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
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "alb_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "wordpress.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cdn_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# Monitoring and Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "wordpress-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_utilization" {
  alarm_name          = "wordpress-rds-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors rds cpu utilization"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress_db.identifier
  }
}

# Outputs
output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.static_assets.arn
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress_zone.zone_id
}