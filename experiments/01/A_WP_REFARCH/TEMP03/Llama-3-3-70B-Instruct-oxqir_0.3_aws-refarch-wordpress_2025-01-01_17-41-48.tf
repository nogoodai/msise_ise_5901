# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Define variables for the configuration
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
  default     = "ami-0c55b159cbfafe1f0"
  description = "The ID of the AMI for the EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "The instance class for the RDS instance"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "The engine for the RDS instance"
}

variable "cloudfront_ssl_certificate" {
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  description = "The SSL certificate for the CloudFront distribution"
}

variable "route53_domain_name" {
  type        = string
  default     = "example.com"
  description = "The domain name for the Route 53 hosted zone"
}

# Create a VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create subnets
resource "aws_subnet" "public_subnets" {
  count = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create route tables
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

# Associate subnets with route tables
resource "aws_route_table_association" "public_subnets_association" {
  count = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets_association" {
  count = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create a route to the internet gateway
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

# Create security groups
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

# Create EC2 instances
resource "aws_instance" "wordpress_instances" {
  count = 3
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id
  tags = {
    Name = "WordPressInstance${count.index + 1}"
  }
}

# Create an RDS instance
resource "aws_db_instance" "wordpress_rds" {
  instance_class = var.rds_instance_class
  engine         = var.rds_engine
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "WordPressRDS"
  }
}

# Create a DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "WordPressDBSubnetGroup"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Create an Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Create an Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 3
  health_check_grace_period = 300
  health_check_type         = "EC2"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

# Create a Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_sg.id
  ]
  user_data = file("${path.module}/user_data.sh")
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.route53_domain_name]
  viewer_certificate {
    acm_certificate_arn = var.cloudfront_ssl_certificate
    ssl_support_method  = "sni-only"
  }
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressELB"
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
  tags = {
    Name = "WordPressCFD"
  }
}

# Create an S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = var.route53_domain_name
  acl    = "private"
  tags = {
    Name = "WordPressS3"
  }
}

# Create a Route 53 hosted zone
resource "aws_route53_zone" "wordpress_r53" {
  name = var.route53_domain_name
}

# Create a Route 53 record
resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53.zone_id
  name    = var.route53_domain_name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Output the ELB DNS name
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

# Output the RDS endpoint
output "rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

# Output the CloudFront distribution ID
output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cfd.id
}

# Output the S3 bucket name
output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

# Output the Route 53 hosted zone ID
output "route53_hosted_zone_id" {
  value = aws_route53_zone.wordpress_r53.zone_id
}