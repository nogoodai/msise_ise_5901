# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
  }
  required_version = ">= 1.2.0"
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "WordPressVPC"
  }
}

# Public subnets
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PublicSubnet1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "PublicSubnet2"
  }
}

# Private subnets
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PrivateSubnet1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "PrivateSubnet2"
  }
}

# Internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

# Private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Route table associations
resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_1_association" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_2_association" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security group for WordPress instances"
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
    Name = "WordPressSG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDSSG"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance_1" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet_1.id
  vpc_security_group_ids = [
    aws_security_group.wordpress_sg.id
  ]
  key_name               = "wordpress_key"
  tags = {
    Name = "WordPressInstance1"
  }
}

resource "aws_instance" "wordpress_instance_2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet_2.id
  vpc_security_group_ids = [
    aws_security_group.wordpress_sg.id
  ]
  key_name               = "wordpress_key"
  tags = {
    Name = "WordPressInstance2"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.micro"
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "WordPressRDS"
  }
}

# DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id
  ]
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [
    aws_subnet.public_subnet_1.id,
    aws_subnet.public_subnet_2.id
  ]
  security_groups = [
    aws_security_group.wordpress_sg.id
  ]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 2
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id
  ]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    }
  ]
}

# Launch configuration for Auto Scaling Group
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.wordpress_sg.id
  ]
  key_name               = "wordpress_key"
  user_data              = file("wordpress_user_data.sh")
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["example.com", "www.example.com"]
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
  tags = {
    Name = "WordPressCDN"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket        = "example-bucket"
  force_destroy = true
  acl           = "private"
  tags = {
    Name = "WordPressBucket"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cdn.zone_id
    evaluate_target_health = false
  }
}

# ACM certificate for CloudFront
resource "aws_acm_certificate" "wordpress_cert" {
  domain_name       = "example.com"
  validation_method = "DNS"
  tags = {
    Name = "WordPressCert"
  }
}

# DNS validation for ACM certificate
resource "aws_route53_record" "wordpress_cert_validation" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "_acme-challenge.example.com"
  type    = "TXT"
  ttl     = 60
  records = [aws_acm_certificate.wordpress_cert.domain_validation_options[0].resource_record_value]
}

# Output critical information
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_cdn_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}
