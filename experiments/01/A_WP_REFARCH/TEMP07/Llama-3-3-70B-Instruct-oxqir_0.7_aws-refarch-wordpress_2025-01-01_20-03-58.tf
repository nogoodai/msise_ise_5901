# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "db_instance_class" {
  default = "db.t2.small"
}

variable "db_username" {
  default = "admin"
}

variable "db_password" {
  default = "password123"
}

variable "db_name" {
  default = "wordpressdb"
}

variable "elb_name" {
  default = "wordpress-elb"
}

variable "cloudfront_origin" {
  default = "wordpress-bucket"
}

variable "cloudfront_distribution_name" {
  default = "wordpress-distribution"
}

variable "route53_domain_name" {
  default = "example.com"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

# Create subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "wordpress-public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = "us-west-2a"
  tags = {
    Name = "wordpress-private-subnet-${count.index}"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-igw"
  }
}

# Create route tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "wordpress-public-route-table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-private-route-table"
  }
}

# Associate subnets with route tables
resource "aws_route_table_association" "public_subnets_association" {
  count = length(var.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets_association" {
  count = length(var.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create security groups
resource "aws_security_group" "wordpress_sg" {
  name        = "wordpress-sg"
  description = "Allow inbound traffic on port 80 and 443"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow inbound traffic on port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow inbound traffic on port 443"
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
    Name = "wordpress-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow inbound traffic on port 3306"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow inbound traffic on port 3306"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.db_instance_class
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_db_subnet_group.name
  publicly_accessible    = false
  skip_final_snapshot    = true
}

# Create DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id

  tags = {
    Name = "wordpress-db-subnet-group"
  }
}

# Create EC2 instances
resource "aws_instance" "wordpress_ec2" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id = aws_subnet.public_subnets[0].id
  key_name               = "wordpress-key"
  user_data = file("${path.module}/wordpress.sh")

  tags = {
    Name = "wordpress-ec2"
  }
}

# Create Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = var.elb_name
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_sg.id]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  tags = {
    Name = "wordpress-elb"
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 2
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id

  tag {
    key                 = "Name"
    value               = "wordpress-asg"
    propagate_at_launch = true
  }
}

# Create Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.wordpress_sg.id]
  key_name               = "wordpress-key"
  user_data = file("${path.module}/wordpress.sh")
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = var.cloudfront_origin
    origin_id   = var.cloudfront_origin
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "match-viewer"
      origin_ssl_protocols      = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled = true
  is_ipv6_enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.cloudfront_origin

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
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name = "wordpress-bucket"
  }
}

# Create Route 53 DNS configuration
resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.route53_domain_name
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.route53_domain_name
}

# Create CloudWatch logs and alarms
resource "aws_cloudwatch_log_group" "wordpress_log_group" {
  name = "wordpress-log-group"
}

resource "aws_cloudwatch_metric_alarm" "wordpress_alarm" {
  alarm_name                = "wordpress-alarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "120"
  statistic                 = "Average"
  threshold                 = "80"
  alarm_description         = "This metric alarm monitors ec2 cpu utilization"
  alarm_actions             = [aws_sns_topic.wordpress_sns_topic.arn]
}

resource "aws_sns_topic" "wordpress_sns_topic" {
  name = "wordpress-sns-topic"
}

# Create EFS file system
resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = "wordpress-efs"

  tags = {
    Name = "wordpress-efs"
  }
}

# Create EFS mount targets
resource "aws_efs_mount_target" "wordpress_efs_mount_target" {
  count           = length(var.private_subnets)
  file_system_id  = aws_efs_file_system.wordpress_efs.id
  subnet_id       = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.wordpress_sg.id]
}

# Create Elasticache cluster
resource "aws_elasticache_cluster" "wordpress_elasticache" {
  cluster_id           = "wordpress-elasticache"
  engine               = "memcached"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.4"
  port                 = 11211
  subnet_group_name   = aws_elasticache_subnet_group.wordpress_elasticache_subnet_group.name
}

# Create Elasticache subnet group
resource "aws_elasticache_subnet_group" "wordpress_elasticache_subnet_group" {
  name       = "wordpress-elasticache-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
}

# Outputs
output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_distribution.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.bucket
}

output "route53_record_name" {
  value = aws_route53_record.wordpress_record.name
}