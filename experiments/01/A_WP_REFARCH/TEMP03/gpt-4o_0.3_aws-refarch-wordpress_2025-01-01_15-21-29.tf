terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  description = "IP addresses allowed to SSH into instances"
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.small"
}

variable "db_name" {
  description = "Database name for WordPress"
  default     = "wordpressdb"
}

variable "db_username" {
  description = "Database username"
  default     = "admin"
}

variable "db_password" {
  description = "Database password"
  default     = "changeme"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "wordpress-public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "wordpress-private-subnet-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "wordpress-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

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
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "wordpress-web-sg"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "wordpress-db-sg"
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[0].id
  key_name      = var.key_name
  security_groups = [aws_security_group.web_sg.name]
  associate_public_ip_address = true
  tags = {
    Name = "wordpress-bastion"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups    = [aws_security_group.web_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  listener {
    instance_port     = 443
    instance_protocol = "HTTPS"
    lb_port           = 443
    lb_protocol       = "HTTPS"
    ssl_certificate_id = var.ssl_certificate_id
  }
  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = {
    Name = "wordpress-elb"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.public.*.id
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.db_instance_class
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az             = true
  skip_final_snapshot  = true
  tags = {
    Name = "wordpress-db"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_id.hex}"
  acl    = "public-read"
  tags = {
    Name = "wordpress-assets"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpressS3Origin"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpressS3Origin"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
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
    Name = "wordpress-cdn"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

data "aws_availability_zones" "available" {}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}