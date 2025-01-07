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


variable "github_repo" {
  type = string
}


variable "github_branch" {
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

 username_attributes = ["email"]

  auto_verified_attributes = ["email"]
}


resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name             = "${var.application_name}-${var.stack_name}-client"
  user_pool_id     = aws_cognito_user_pool.main.id
  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls = ["http://localhost:3000/"]
  logout_urls   = ["http://localhost:3000/"]


}


resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
 read_capacity = 5
 write_capacity = 5

  hash_key = "cognito-username"
  range_key = "id"

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


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
 Statement = [
      {
        Action = "sts:AssumeRole",
 Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}



resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.application_name}-api-${var.stack_name}"

}




resource "aws_api_gateway_authorizer" "cognito_authorizer" {

  name            = "cognito_authorizer_${var.stack_name}"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.main.arn]
}

resource "aws_lambda_function" "add_item" {

 filename      = "add_item.zip"
 function_name = "add_item-${var.stack_name}"
 handler       = "index.handler"
 runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60
 tracing_config {
    mode = "Active"
  }

}

resource "aws_lambda_function" "get_item" {

 filename      = "get_item.zip"
 function_name = "get_item-${var.stack_name}"
 handler       = "index.handler"
 runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60
 tracing_config {
    mode = "Active"
  }
}




resource "aws_amplify_app" "main" {
  name             = "${var.application_name}-amplify-${var.stack_name}"
 repository        = var.github_repo
 access_token = var.github_access_token # Replace with actual variable declaration
 build_spec = <<-EOT
version: 0.1
frontend:
 phases:
    install:
      commands:
        - npm install
    preBuild:
      commands:
        - npm run build
    build:
      commands:
        - npm run export
 artifacts:
    baseDirectory: /
    files:
      - '**/*'
cache:
 paths:
    - node_modules/**/*

 EOT
}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
}


# Placeholder IAM role and policy for Lambda. Replace with specific permissions required.
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
 Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
 }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
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
