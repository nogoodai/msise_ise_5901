terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables for user-configurable values
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "List of public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "List of private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t2.micro"
}

variable "domain_name" {
  description = "Domain name for the WordPress site"
  type        = string
  default     = "example.com"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "asg_min_size" {
  description = "Minimum size of the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum size of the Auto Scaling Group"
  type        = number
  default     = 3
}

variable "efs_performance_mode" {
  description = "Performance mode of EFS"
  type        = string
  default     = "generalPurpose"
}

variable "elasticache_engine" {
  description = "Engine for ElastiCache"
  type        = string
  default     = "memcached"
}

variable "elasticache_node_type" {
  description = "Node type for ElastiCache"
  type        = string
  default     = "cache.t2.micro"
}

variable "elasticache_num_cache_nodes" {
  description = "Number of cache nodes for ElastiCache"
  type        = number
  default     = 1
}

# Provider configuration
provider "aws" {
  region = var.region
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "WordPress-IGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "WordPress-Public-Subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "WordPress-Private-Subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name        = "WordPress-Public-RT"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "WordPress-Private-RT"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "web_server" {
  name        = "WordPress-Web-Server-SG"
  description = "Security group for WordPress web server"
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
    cidr_blocks = var.ssh_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPress-Web-Server-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "database" {
  name        = "WordPress-Database-SG"
  description = "Security group for WordPress database"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.web_server.id]
  }

  tags = {
    Name        = "WordPress-Database-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "elb" {
  name        = "WordPress-ELB-SG"
  description = "Security group for WordPress ELB"
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
    Name        = "WordPress-ELB-SG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "wordpress" {
  name_prefix   = "WordPress-LC-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server.id]

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

resource "aws_autoscaling_group" "wordpress" {
  name                 = "WordPress-ASG"
  launch_configuration = aws_launch_configuration.wordpress.name
  min_size             = var.asg_min_size
  max_size             = var.asg_max_size
  vpc_zone_identifier  = aws_subnet.public[*].id

  tag {
    key                 = "Name"
    value               = "WordPress-Instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "Production"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "WordPress"
    propagate_at_launch = true
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress" {
  identifier             = "wordpress-db"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = "wordpress"
  username               = "admin"
  password               = "password123"
  vpc_security_group_ids = [aws_security_group.database.id]
  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name        = "WordPress-RDS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress" {
  name               = "WordPress-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "WordPress-ALB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "WordPress-TG"
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
    Name        = "WordPress-TG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_lb_listener" "wordpress" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_autoscaling_attachment" "asg_attachment_wordpress" {
  autoscaling_group_name = aws_autoscaling_group.wordpress.id
  lb_target_group_arn    = aws_lb_target_group.wordpress.arn
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_lb.wordpress.dns_name
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
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressALB"

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
    Name        = "WordPress-CloudFront"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${var.domain_name}"
  acl    = "private"

  tags = {
    Name        = "WordPress-Assets"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress.dns_name
    zone_id                = aws_lb.wordpress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cloudfront" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

# Monitoring and Dashboards
resource "aws_cloudwatch_dashboard" "wordpress" {
  dashboard_name = "WordPress-Dashboard"
  dashboard_body = <<EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [
            "AWS/EC2",
            "CPUUtilization",
            "InstanceId",
            "${aws_autoscaling_group.wordpress.id}"
          ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${var.region}",
        "title": "EC2 CPU Utilization",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [
            "AWS/RDS",
            "CPUUtilization",
            "DBInstanceIdentifier",
            "${aws_db_instance.wordpress.id}"
          ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${var.region}",
        "title": "RDS CPU Utilization",
        "period": 300
      }
    }
  ]
}
EOF
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu_alarm" {
  alarm_name          = "WordPress-EC2-CPU-Alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_alarm" {
  alarm_name          = "WordPress-RDS-CPU-Alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors rds cpu utilization"
  alarm_actions       = []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress.identifier
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.main.id
}

output "alb_dns_name" {
  value = aws_lb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.bucket
}
