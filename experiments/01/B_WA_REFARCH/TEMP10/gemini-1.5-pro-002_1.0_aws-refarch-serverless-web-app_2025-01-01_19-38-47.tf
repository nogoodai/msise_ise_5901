terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_client" "main" {
  name                 = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id        = aws_cognito_user_pool.main.id
  generate_secret      = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 read_capacity  = 5
 write_capacity = 5
 hash_key       = "cognito-username"
 range_key      = "id"

 attribute {
   name = "cognito-username"
   type = "S"
 }

 attribute {
   name = "id"
   type = "S"
 }

 server_side_encryption {
   enabled = true
 }
}


resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.application_name}-api-${var.stack_name}"
 description = "API Gateway for ${var.application_name} application"
}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = "https://github.com/example/repo" # Replace with your GitHub repository URL
 build_spec = <<EOF
 version: 0.1
 frontend:
   phases:
     preBuild:
       commands:
         - npm install
     build:
       commands:
         - npm run build
     postBuild:
       commands:
         - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket} --delete
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF
}

resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-amplify-bucket-${var.stack_name}"
 acl    = "private"
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
 Effect = "Allow",
        Sid    = "1",
      },
    ]
  })
}


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

 policy = jsonencode({
 Version = "2012-10-17",
 Statement = [
 {
 Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:DescribeLogGroups",
 "logs:DescribeLogStreams",
 "logs:PutLogEvents",
 "logs:GetLogEvents",
 "logs:FilterLogEvents"
        ],
        Resource = "*",
 Effect = "Allow",
        Sid    = "1",
      },
 ]
  })
}



output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}


