# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "The availability zones for the subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "The instance type for the EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "The ID of the AMI for the EC2 instances"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "db_username" {
  type        = string
  default     = "admin"
  description = "The username for the RDS instance"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "The password for the RDS instance"
}

variable "domain_name" {
  type        = string
  description = "The domain name for the Route 53 configuration"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, length(var.availability_zones) + count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_route_table_association" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
  }
}

resource "aws_route_table_association" "private_route_table_association" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
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
    Name        = "WordPressWebServerSG"
    Environment = "production"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "WordPressDBSG"
  description = "Security group for the database"
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
    Name        = "WordPressDBSG"
    Environment = "production"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name               = "wordpress_key"
  user_data              = file("./wordpress.sh")
  tags = {
    Name        = "WordPressInstance"
    Environment = "production"
  }
}

# RDS instance for the WordPress database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = var.db_username
  password             = var.db_password
  vpc_security_group_ids = [
    aws_security_group.db_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name        = "WordPressDB"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "production"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_sg.id]

  listener {
    instance_port      = 80
    instance_protocol = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "production"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  key_name               = "wordpress_key"
  user_data              = file("./wordpress.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"

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
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name        = "WordPressBucket"
    Environment = "production"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}
