terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  default     = "todo-app"
}

variable "stack_name" {
  description = "Stack name for resource naming"
  default     = "prod"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the custom Cognito domain"
  default     = "auth"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify"
  default     = "https://github.com/user/todo-app-frontend"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers  = false
    require_symbols  = false
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.project_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${var.project_name}.com"]
  logout_urls                          = ["https://${var.project_name}.com/logout"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool-domain"
    Environment = var.stack_name
    Project     = var.project_name
  }
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
    Project     = var.project_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.project_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.project_name} application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  name        = "${var.project_name}-${var.stack_name}-cognito-authorizer"
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.project_name}-${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.project_name} application"

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
    Name        = "${var.project_name}-${var.stack_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.project_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "add_item.zip"
  source_code_hash = filebase64sha256("add_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-add-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "get_item" {
  function_name = "${var.project_name}-${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "get_item.zip"
  source_code_hash = filebase64sha256("get_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-get-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "${var.project_name}-${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "get_all_items.zip"
  source_code_hash = filebase64sha256("get_all_items.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-get-all-items"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "update_item" {
  function_name = "${var.project_name}-${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "update_item.zip"
  source_code_hash = filebase64sha256("update_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-update-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "complete_item" {
  function_name = "${var.project_name}-${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "complete_item.zip"
  source_code_hash = filebase64sha256("complete_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-complete-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "delete_item" {
  function_name = "${var.project_name}-${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "delete_item.zip"
  source_code_hash = filebase64sha256("delete_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-delete-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Amplify App
resource "aws_amplify_app" "frontend_app" {
  name       = "${var.project_name}-${var.stack_name}-frontend"
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
    EOT

  environment_variables = {
    ENV = var.stack_name
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-frontend"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.frontend_app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-master-branch"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-role"

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
    Name        = "${var.project_name}-${var.stack_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-${var.stack_name}-amplify-role"

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
    Name        = "${var.project_name}-${var.stack_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.project_name}-${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "amplify:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.stack_name}-lambda-role"

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
    Name        = "${var.project_name}-${var.stack_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.project_name}-${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "${var.project_name}-${var.stack_name}-lambda-cloudwatch-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Monitoring and Alerting
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.api_gateway.name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api-gateway-log-group"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.project_name}-${var.stack_name}-lambda-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors for ${var.project_name}"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.add_item.function_name
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-lambda-error-alarm"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_deployment_invoke_url" {
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend_app.id
}

output "amplify_app_default_domain" {
  value = aws_amplify_app.frontend_app.default_domain
}