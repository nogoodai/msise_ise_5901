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
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack"
  type        = string
}

variable "application_name" {
  description = "Name of the application"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository for Amplify"
  type        = string
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "${var.application_name}-user-pool-client"

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  
  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
  callback_urls             = ["https://${var.application_name}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
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

resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.application_name}-api"
  description = "API Gateway for the serverless application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  provider_arns = [aws_cognito_user_pool.user_pool.arn]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod_stage" {
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.todo_api.id
  deployment_id        = aws_api_gateway_deployment.deployment.id
  xray_tracing_enabled = true
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  triggers = {
    redeployment = sha1(jsonencode(aws_lambda_function.todo_lambda.*.invoke_arn))
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.application_name}-usage-plan"

  api_stages {
    api_id   = aws_api_gateway_rest_api.todo_api.id
    stage    = aws_api_gateway_stage.prod_stage.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "todo_lambda" {
  count                  = 6
  filename               = "path_to_your_lambda_zip_file" # Replace with actual path
  function_name          = "${var.application_name}-lambda-${element(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"], count.index)}"
  role                   = aws_iam_role.lambda_exec_role.arn
  handler                = "index.handler"
  runtime                = "nodejs12.x"
  memory_size            = 1024
  timeout                = 60
  publish                = true

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.application_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "${var.application_name}-lambda-dynamodb-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  count = 6
  name              = "/aws/lambda/${element(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"], count.index)}"
  retention_in_days = 7
}

resource "aws_amplify_app" "frontend" {
  name                = "${var.application_name}-amplify-app"
  repository          = var.github_repository
  oauth_token         = var.github_oauth_token

  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        preBuild:
          commands:
            - npm install
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
    EOT

  environment_variables = {
    "_LIVE_UPDATES" = "null"
  }
}

resource "aws_amplify_branch" "master" {
  app_id     = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}

resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.application_name}-api-gateway-cloudwatch-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.todo_api.execution_arn
}

output "amplify_app_url" {
  value = aws_amplify_app.frontend.default_domain
}