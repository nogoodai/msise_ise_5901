terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the deployment stack."
  default     = "my-app"
}

variable "github_repo" {
  description = "The GitHub repository for the Amplify app."
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

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
  name         = "app-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
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

resource "aws_apigatewayv2_api" "api" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id     = aws_apigatewayv2_api.api.id
  name       = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format          = "$context.requestId: $context.identity.sourceIp - $context.httpMethod $context.path"
  }
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name = "/aws/apigateway/${aws_apigatewayv2_api.api.id}"
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id      = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer   = aws_cognito_user_pool.user_pool.endpoint
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.lambda_function.invoke_arn
}

resource "aws_apigatewayv2_route" "route" {
  api_id     = aws_apigatewayv2_api.api.id
  route_key  = "ANY /{proxy+}"
  target     = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorizer_id = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

resource "aws_lambda_function" "lambda_function" {
  filename         = "function.zip"
  function_name    = "lambda-${var.stack_name}"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60

  tracing_config {
    mode = "Active"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy-${var.stack_name}"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:*",
          "logs:*",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "amplify_app" {
  name              = "amplify-app-${var.stack_name}"
  repository        = var.github_repo
  oauth_token       = var.oauth_token

  build_spec = <<EOF
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

EOF

  auto_branch_creation_config {
    enable_auto_build = true
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "apigateway_cloudwatch_role" {
  name = "apigateway-cloudwatch-role-${var.stack_name}"

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
}

resource "aws_iam_role_policy" "apigateway_policy" {
  name = "apigateway-policy-${var.stack_name}"
  role = aws_iam_role.apigateway_cloudwatch_role.id

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

resource "aws_iam_role" "amplify_exec_role" {
  name = "amplify-exec-role-${var.stack_name}"

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
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "amplify-policy-${var.stack_name}"
  role = aws_iam_role.amplify_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
          "s3:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB Table."
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "The URL of the API Gateway."
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda Function."
  value       = aws_lambda_function.lambda_function.arn
}

output "amplify_app_id" {
  description = "The ID of the Amplify App."
  value       = aws_amplify_app.amplify_app.id
}