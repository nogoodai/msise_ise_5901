terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack"
  default     = "todo-app"
}

variable "application_name" {
  description = "Name of the application"
  default     = "todo-app"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify"
  default     = "https://github.com/user/todo-app-frontend"
}

# Provider
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.application_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  callback_urls = ["https://${var.application_name}.${var.stack_name}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse"]
  logout_urls   = ["https://${var.application_name}.${var.stack_name}.auth.${var.region}.amazoncognito.com/logout"]

  tags = {
    Name        = "${var.application_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.application_name}-api"
  description = "API Gateway for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.application_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.application_name}-usage-plan"
  description = "Usage plan for ${var.application_name} API"

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "${var.application_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.application_name}-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api_gateway.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

# Lambda Functions
resource "aws_lambda_function" "lambda_functions" {
  for_each = toset([
    "add-item",
    "get-item",
    "get-all-items",
    "update-item",
    "complete-item",
    "delete-item"
  ])

  function_name = "${var.application_name}-${each.key}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  role = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-${each.key}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.application_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${var.application_name}-*:log-stream:*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.application_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/api-gateway/*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.application_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "amplify:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name       = "${var.application_name}-app"
  repository = var.github_repo

  build_spec = <<-EOT
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
        baseDirectory: build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  tags = {
    Name        = "${var.application_name}-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.application_name}-master-branch"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# CloudWatch Logs and Alarms
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.api_gateway.name}"

  tags = {
    Name        = "${var.application_name}-api-gateway-logs"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors" {
  alarm_name          = "${var.application_name}-api-gateway-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors 5XX errors on the API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.api_gateway.name
  }

  tags = {
    Name        = "${var.application_name}-api-gateway-5xx-errors-alarm"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each = aws_lambda_function.lambda_functions

  name = "/aws/lambda/${each.value.function_name}"

  tags = {
    Name        = "${each.value.function_name}-logs"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = aws_lambda_function.lambda_functions

  alarm_name          = "${each.value.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors errors for the Lambda function ${each.value.function_name}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = {
    Name        = "${each.value.function_name}-errors-alarm"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "lambda_function_arns" {
  value = { for k, v in aws_lambda_function.lambda_functions : k => v.arn }
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}
