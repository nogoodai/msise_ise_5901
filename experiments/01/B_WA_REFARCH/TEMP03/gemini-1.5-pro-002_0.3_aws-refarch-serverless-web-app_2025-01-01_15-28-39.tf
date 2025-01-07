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
    require_lower_case = true
    require_upper_case = true
    require_numbers = false
    require_symbols = false
  }

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls = ["http://localhost:3000/"] # Placeholder, update as needed

  supported_identity_providers = ["COGNITO"]
}

resource "aws_dynamodb_table" "main" {
 name = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
 read_capacity = 5
 write_capacity = 5
 server_side_encryption {
   enabled = true
 }

 hash_key {
   name = "cognito-username"
   type = "S"
 }

 range_key {
   name = "id"
   type = "S"
 }
}

resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Effect": "Allow",
   "Principal": {
    "Service": "apigateway.amazonaws.com"
   },
   "Action": "sts:AssumeRole"
  }
 ]
}
EOF
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {
 name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
 role = aws_iam_role.api_gateway_cloudwatch_logs_role.id

 policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Effect": "Allow",
   "Action": [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
   ],
   "Resource": "*"
  }
 ]
}
EOF
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
}

resource "aws_amplify_app" "main" {
 name = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url
 access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub PAT
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
 artifacts:
  baseDirectory: /
  files:
   - '**/*'
EOF
}



resource "aws_amplify_branch" "main" {
 app_id = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true
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

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}
