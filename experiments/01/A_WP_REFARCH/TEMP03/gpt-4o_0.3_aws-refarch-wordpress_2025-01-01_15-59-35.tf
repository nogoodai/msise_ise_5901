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
  description = "The CIDR block for the VPC"
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
  description = "List of IPs allowed to SSH into bastion and web servers"
  default     = ["0.0.0.0/0"]
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.small"
}

variable "db_name" {
  description = "Database name"
  default     = "wordpressdb"
}

variable "db_username" {
  description = "Database username"
  default     = "admin"
}

variable "db_password" {
  description = "Database password"
  default     = "password"
  sensitive   = true
}

variable "project_name" {
  description = "The name of the project"
  default     = "wordpress"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  cidr_block = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "${var.project_name}-public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  cidr_block = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "${var.project_name}-private-subnet-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)
  subnet_id = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
  description = "Allow HTTP, HTTPS, and SSH traffic"
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = var.allowed_ssh_ips
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id
  description = "Allow MySQL traffic from web servers"
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

resource "aws_instance" "bastion" {
  ami = var.ami_id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public[0].id
  key_name = var.key_name
  associate_public_ip_address = true
  security_groups = [aws_security_group.web_sg.name]
  tags = {
    Name = "${var.project_name}-bastion"
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  vpc = true
}

resource "aws_efs_file_system" "wordpress" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "${var.project_name}-efs"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count = length(var.private_subnet_cidrs)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id = element(aws_subnet.private.*.id, count.index)
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_rds_instance" "wordpress" {
  allocated_storage = 20
  engine = "mysql"
  instance_class = var.db_instance_class
  name = var.db_name
  username = var.db_username
  password = var.db_password
  multi_az = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  tags = {
    Name = "${var.project_name}-rds"
  }
}

resource "aws_elb" "wordpress" {
  name = "${var.project_name}-elb"
  availability_zones = data.aws_availability_zones.available.names
  listener {
    instance_port = 80
    instance_protocol = "HTTP"
    lb_port = 80
    lb_protocol = "HTTP"
  }
  listener {
    instance_port = 443
    instance_protocol = "HTTPS"
    lb_port = 443
    lb_protocol = "HTTPS"
  }
  security_groups = [aws_security_group.web_sg.id]
  tags = {
    Name = "${var.project_name}-elb"
  }
}

resource "aws_autoscaling_group" "wordpress" {
  launch_configuration = aws_launch_configuration.wordpress.id
  min_size = 1
  max_size = 3
  vpc_zone_identifier = aws_subnet.public.*.id
  tags = [
    {
      key = "Name"
      value = "${var.project_name}-asg"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress" {
  image_id = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]
  user_data = file("wordpress-install.sh")
  associate_public_ip_address = true
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "${var.project_name}-assets"
  acl = "private"
  tags = {
    Name = "${var.project_name}-assets"
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id = "s3-${aws_s3_bucket.wordpress_assets.id}"
  }
  enabled = true
  default_cache_behavior {
    target_origin_id = "s3-${aws_s3_bucket.wordpress_assets.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  tags = {
    Name = "${var.project_name}-cloudfront"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name = "www"
  type = "A"
  alias {
    name = aws_elb.wordpress.dns_name
    zone_id = aws_elb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress.dns_name
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}
