terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "project_name" {
  type    = string
  default = "wordpress-project"
}

variable "environment" {
  type    = string
  default = "production"
}


# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-1"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-2"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "${var.project_name}-public-route-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {}

# Security Groups

resource "aws_security_group" "web_sg" {
 name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP, HTTPS and SSH"
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
    cidr_blocks = ["0.0.0.0/0"] # Replace with your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# EC2 Instances and Auto Scaling

resource "aws_launch_template" "wordpress_lt" {
  name_prefix   = "${var.project_name}-wordpress-lt-"
  image_id      = "ami-0c94855ba95c574c8" # Replace with your desired AMI
  instance_type = "t2.micro"
  network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
    associate_public_ip_address = true
  }

  user_data = filebase64("user_data.sh") # Create this file with your WordPress installation script

  lifecycle {
    create_before_destroy = true
  }

}


resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "${var.project_name}-wordpress-asg"
  min_size                  = 2
  max_size                  = 4
  vpc_zone_identifier       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }


  tag {
    key                 = "Name"
    value              = "${var.project_name}-wordpress-instance"
    propagate_at_launch = true
  }
}


# RDS Instance

resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}


resource "aws_db_instance" "default" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t2.micro"
  name                   = "wordpress"
  username               = "admin" # Replace with your username
  password               = "password" # Replace with your password
  db_subnet_group_name   = aws_db_subnet_group.default.name
  skip_final_snapshot    = true
 publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.web_sg.id] # Allow access from web server

}


# Elastic Load Balancer

resource "aws_lb" "wordpress_lb" {
  name               = "${var.project_name}-wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]


}

resource "aws_lb_target_group" "wordpress_tg" {
  name        = "${var.project_name}-wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"


  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 5
    timeout             = 5
  }
}


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}



resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
  lb_target_group_arn     = aws_lb_target_group.wordpress_tg.arn
}


# S3 Bucket

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "${var.project_name}-wordpress-assets"
  acl    = "private"


}


# CloudFront Distribution (Example with S3 origin)

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.wordpress_assets.id

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/ABCDEFGHIJKLMN" # Replace with your OAI
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.wordpress_assets.id
    viewer_protocol_policy = "redirect-to-https"


    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }


  price_class = "PriceClass_All"


  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }


  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


# Route53 (Example)

# resource "aws_route53_zone" "main" {
#   name = "example.com." # Replace with your domain
# }

# resource "aws_route53_record" "www" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = "www"
#   type    = "A"

#   alias {
#     name                   = aws_lb.wordpress_lb.dns_name
#     zone_id                = aws_lb.wordpress_lb.zone_id
#     evaluate_target_health = true
#   }
# }



output "lb_dns_name" {
  value = aws_lb.wordpress_lb.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.bucket
}


output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}


output "rds_endpoint" {
 value = aws_db_instance.default.endpoint
}
