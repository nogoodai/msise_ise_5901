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
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "ssh_ingress_cidr" {
  description = "CIDR block for SSH ingress"
  default     = "0.0.0.0/0"
}

variable "domain_name" {
  description = "Domain name for Route 53"
  default     = "example.com"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "db_engine" {
  description = "Database engine type"
  default     = "mysql"
}

variable "db_instance_class" {
  description = "Database instance class"
  default     = "db.t2.micro"
}

variable "rds_username" {
  description = "RDS admin username"
  default     = "admin"
}

variable "rds_password" {
  description = "RDS admin password"
  default     = "password123"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for static assets"
  default     = "wordpress-static-assets"
}

# Provider
provider "aws" {
  region = var.region
}

# Networking
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

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
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "WordPress-Public-Subnet-${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
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
    Name        = "WordPress-Public-Route-Table"
    Environment = "Production"
    Project     = "WordPress"
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
    Name        = "WordPress-Private-Route-Table"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "web_server" {
  name        = "WordPress-Web-Server-SG"
  description = "Security group for WordPress web servers"
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
    cidr_blocks = [var.ssh_ingress_cidr]
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
  name_prefix          = "wordpress-"
  image_id             = var.ami_id
  instance_type        = var.instance_type
  security_groups     = [aws_security_group.web_server.id]
  key_name             = "wordpress-key"
  user_data            = file("wordpress-install.sh")

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
  health_check_type    = "ELB"

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
resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "WordPress-DB-Subnet-Group"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_instance" "wordpress" {
  identifier             = "wordpress-db"
  engine                 = var.db_engine
  engine_version         = "5.7"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = "wordpressdb"
  username               = var.rds_username
  password               = var.rds_password
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids = [aws_security_group.database.id]
  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name        = "WordPress-DB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress" {
  name               = "wordpress-alb"
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
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name        = "WordPress-Target-Group"
    Environment = "Production"
    Project     = "WordPress"
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

resource "aws_autoscaling_attachment" "asg_attachment_wordpress" {
  autoscaling_group_name = aws_autoscaling_group.wordpress.id
  lb_target_group_arn    = aws_lb_target_group.wordpress.arn
}

# CloudFront Distribution for Content Delivery
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
resource "aws_s3_bucket" "static_assets" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "WordPress-Static-Assets"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket_public_access_block" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress" {
  name = var.domain_name

  tags = {
    Name        = "WordPress-Route53-Zone"
    Environment = "Production"
    Project     = "WordPress"
  }
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

# Monitoring and Alerting
resource "aws_cloudwatch_metric_alarm" "wordpress_cpu_high" {
  alarm_name          = "wordpress-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }
}

resource "aws_cloudwatch_metric_alarm" "wordpress_db_cpu_high" {
  alarm_name          = "wordpress-db-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
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

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "elb_dns_name" {
  value = aws_lb.wordpress.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.static_assets.arn
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress.zone_id
}