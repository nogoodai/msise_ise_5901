# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Define variables for the configuration
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy resources"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "public_subnets" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for public subnets"
}

variable "private_subnets" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "CIDR blocks for private subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "AMI ID for EC2 instances"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "db_engine" {
  type        = string
  default     = "mysql"
  description = "Engine for RDS instance"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for Route 53 configuration"
}

# Create the VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnets)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = "${var.aws_region}${count.index % 2 + 1}"
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet${count.index + 1}"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = "${var.aws_region}${count.index % 2 + 1}"
  tags = {
    Name = "PrivateSubnet${count.index + 1}"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Create public route table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

# Create route for public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_association" {
  count = length(var.public_subnets)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Create security groups
resource "aws_security_group" "web_sg" {
  name        = "WordPressWebSG"
  description = "Allow inbound HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "WordPressDBSG"
  description = "Allow inbound MySQL traffic from web servers"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 3306
    to_port     = 3306
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_db" {
  identifier           = "wordpress-db"
  instance_class       = var.db_instance_class
  engine               = var.db_engine
  engine_version       = "8.0.28"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  multi_az             = true
  storage_type         = "gp2"
  allocated_storage    = 20
  skip_final_snapshot  = true
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_sg.id]

  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }

  listener {
    lb_port       = 443
    lb_protocol   = "https"
    instance_port = 80
    instance_protocol = "http"
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/WordPressCert"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name               = "wordpress_key"
  user_data = file("${path.module}/wordpress.sh")
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 2
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]
  key_name               = "wordpress_key"
  user_data = file("${path.module}/wordpress.sh")
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-origin"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-origin"

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

# Create S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "wordpress-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }
}

# Create Route 53 record
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cf.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "cf_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "rds_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}