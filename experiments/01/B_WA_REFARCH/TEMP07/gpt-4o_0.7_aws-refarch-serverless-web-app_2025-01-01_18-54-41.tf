terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "my-serverless-app"
}

variable "environment" {
  default = "production"
}

variable "stack_name" {
  default = "my-stack"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.project_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_AUTH_CODE_FLOW", "ALLOW_IMPLICIT_FLOW"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret = false
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

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

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-api"
  description = "API for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id

  xray_tracing_enabled = true

  tags = {
    Name        = "${var.project_name}-api-stage"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.project_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.api_stage.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  tags = {
    Name        = "${var.project_name}-usage-plan"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.project_name}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api.id
  type                   = "COGNITO_USER_POOLS"
  identity_source        = "method.request.header.Authorization"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_lambda_function" "lambda_function" {
  function_name = "${var.project_name}-function"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-lambda"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*"
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.project_name}-lambda-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem"
    ]
    resources = [aws_dynamodb_table.todo_table.arn]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_amplify_app" "amplify_app" {
  name = "${var.project_name}-amplify"

  source_code_repository {
    repository_url = "https://github.com/user/repo"
    branch_name    = "master"
  }

  auto_build = true

  build_spec = <<-EOT
    version: 1.0
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

  tags = {
    Name        = "${var.project_name}-amplify"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-api-gateway-role"

  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role_policy.json
}

data "aws_iam_policy_document" "api_gateway_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name   = "${var.project_name}-api-gateway-policy"
  role   = aws_iam_role.api_gateway_role.id
  policy = data.aws_iam_policy_document.api_gateway_policy.json
}

data "aws_iam_policy_document" "api_gateway_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-amplify-role"

  assume_role_policy = data.aws_iam_policy_document.amplify_assume_role_policy.json
}

data "aws_iam_policy_document" "amplify_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["amplify.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name   = "${var.project_name}-amplify-policy"
  role   = aws_iam_role.amplify_role.id
  policy = data.aws_iam_policy_document.amplify_policy.json
}

data "aws_iam_policy_document" "amplify_policy" {
  statement {
    actions = [
      "amplify:*",
      "s3:*"
    ]
    resources = ["*"]
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
