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

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
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
  name        = "${var.application_name}-${var.stack_name}-api"
}

resource "aws_api_gateway_authorizer" "cognito" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 name         = "cognito_authorizer"
 type         = "COGNITO_USER_POOLS"
 provider_arns = [aws_cognito_user_pool.main.arn]
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api_gateway_cloudwatch_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api_gateway_cloudwatch_policy_${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}

resource "aws_api_gateway_account" "demo" {
 cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
}

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify"
  repository = var.github_repo_url
  access_token = var.github_personal_access_token

  build_spec = <<EOF
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}

variable "github_personal_access_token" {}

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

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}