terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

# Variables
variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
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

# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "private-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-internet-gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_route_association" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
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
    Name = "web-sg"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "db-sg"
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "wordpress_launch_config" {
  image_id          = data.aws_ami.latest.id
  instance_type     = "t2.micro"
  user_data         = file("wordpress.sh")
  security_groups   = [aws_security_group.web_sg.id]
  key_name          = aws_key_pair.bastion_key.id

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "latest" {
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  owners = ["amazon"]
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id
  min_size             = 2
  max_size             = 5
  vpc_zone_identifier  = aws_subnet.public_subnets[*].id

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-ec2"
      propagate_at_launch = true
    }
  ]
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress_db" {
  engine            = "mysql"
  instance_class    = "db.t2.small"
  allocated_storage = 20
  name              = "wordpressdb"
  username          = "admin"
  password          = "password"
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  multi_az = true

  tags = {
    Name = "wordpress-db"
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name = "wordpress-alb"
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "wordpress_http_listener" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
    }
  }

  enabled             = true
  default_cache_behavior {
    target_origin_id = "wordpress-alb"
    viewer_protocol_policy = "allow-all"
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
  }

  tags = {
    Name = "wordpress-cf"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets-${random_pet.bucket_name.id}"

  tags = {
    Name = "wordpress-static-assets"
  }
}

resource "random_pet" "bucket_name" {}

# Route 53 DNS
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cloudfront_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "assets"
  type    = "CNAME"
  records = [aws_cloudfront_distribution.wordpress_cf.domain_name]
  ttl     = 300
}

# Outputs
output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}
