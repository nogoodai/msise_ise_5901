terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-west-2"
}

variable "stack_name" {
  default = "my-stack"
}

variable "application_name" {
  default = "my-app"
}

variable "github_repo" {
  description = "GitHub repository for Amplify app"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                   = "${var.application_name}-client"
  user_pool_id           = aws_cognito_user_pool.user_pool.id
  generate_secret        = false
  allowed_oauth_flows    = ["code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls          = ["https://example.com/callback"]
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain      = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"

  read_capacity  = 5
  write_capacity = 5

  hash_key  = "cognito-username"
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

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-api"
  description = "API for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name         = "CognitoAuthorizer"
  rest_api_id  = aws_api_gateway_rest_api.api.id
  type         = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.item_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.application_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.add_item.function_name}"
  retention_in_days = 14
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.application_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "LambdaDynamoDBPolicy"
  role   = aws_iam_role.lambda_exec_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = "logs:*"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "frontend" {
  name = var.application_name
  repository = var.github_repo

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
        baseDirectory: /build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
    EOT
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build = true
}

output "user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "api_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}