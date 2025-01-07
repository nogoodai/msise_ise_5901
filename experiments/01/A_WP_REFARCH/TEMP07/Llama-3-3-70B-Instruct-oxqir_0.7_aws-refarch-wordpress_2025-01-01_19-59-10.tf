provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "List of availability zones"
}

variable "web_server_instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for the web server"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for the RDS instance"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for the Route 53 configuration"
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnets
resource "aws_subnet" "public_subnet" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 16)
  availability_zone = var.availability_zones[count.index]
  vpc_id            = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for the web server"
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
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "WordPressWebServerSG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for the RDS instance"
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
    Name = "WordPressRDSSG"
  }
}

# EC2 Instances
resource "aws_instance" "web_server" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.web_server_instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnet[0].id
  tags = {
    Name = "WordPressWebServer"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password123"
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpressdb"
  subnet_ids = aws_subnet.private_subnet[*].id
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "WordPressALB"
  internal        = false
  security_groups = [aws_security_group.web_server_sg.id]
  subnets         = aws_subnet.public_subnet[*].id
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_alb_target_group" "wordpress_target_group" {
  name     = "WordPressTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressTargetGroup"
  }
}

resource "aws_alb_listener" "wordpress_listener" {
  load_balancer_arn = aws_alb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_alb_target_group.wordpress_target_group.arn
    type             = "forward"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "WordPressASG"
  max_size             = 2
  min_size             = 1
  desired_capacity    = 1
  launch_configuration = aws_launch_configuration.wordpress_launch_config.name
  target_group_arns    = [aws_alb_target_group.wordpress_target_group.arn]
  tags = {
    Name = "WordPressASG"
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.web_server_instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  user_data = file("./wordpress_install.sh")
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = "S3Origin"
  }
  enabled         = true
  is_ipv6_enabled = true
  default_root_object = "index.html"
  aliases = [
    var.domain_name
  ]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"
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
    acm_certificate_arn = aws_acm_certificate.wordpress_cert.arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_acm_certificate" "wordpress_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "wordpress_cert_validation" {
  certificate_arn = aws_acm_certificate.wordpress_cert.arn
  validation_record {
    name    = aws_route53_record.wordpress_cert_validation.name
    value   = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_value
    type    = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_type
  }
}

resource "aws_route53_record" "wordpress_cert_validation" {
  name    = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_name
  type    = aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_type
  zone_id = aws_route53_zone.wordpress_zone.id
  records = [aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_value]
  ttl     = 60
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_record" {
  name    = var.domain_name
  type    = "A"
  zone_id = aws_route53_zone.wordpress_zone.id
  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_distribution.zone_id
    evaluate_target_health = false
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"
  tags = {
    Name = "WordPressBucket"
  }
}

# CloudWatch Metrics
resource "aws_cloudwatch_metric_alarm" "wordpress_alarm" {
  alarm_name                = "WordPressAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = 1
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = 300
  statistic                 = "Average"
  threshold                = 70
  alarm_description         = "Alarm for CPU utilization"
  actions_enabled           = true
  alarm_actions             = [aws_sns_topic.wordpress_topic.arn]
}

resource "aws_sns_topic" "wordpress_topic" {
  name = "WordPressTopic"
}

resource "aws_sns_topic_subscription" "wordpress_subscription" {
  topic_arn = aws_sns_topic.wordpress_topic.arn
  protocol  = "email"
  endpoint  = "example@example.com"
}

# Outputs
output "alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_distribution.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "route53_record_name" {
  value = aws_route53_record.wordpress_record.name
}
