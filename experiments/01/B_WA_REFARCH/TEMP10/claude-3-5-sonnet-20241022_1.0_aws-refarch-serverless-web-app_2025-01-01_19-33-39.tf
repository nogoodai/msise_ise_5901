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

# Variables
variable "aws_region" {
  default = "us-east-1"
}

variable "app_name" {
  default = "todo-app"
}

variable "environment" {
  default = "prod" 
}

variable "github_repo" {
  type = string
}

variable "github_access_token" {
  type = string
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.app_name}-user-pool-${var.environment}"

  username_attributes = ["email"]
  auto_verify_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.app_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.app_name}-client"

  user_pool_id = aws_cognito_user_pool.main.id
  
  generate_secret = false
  
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  
  supported_identity_providers = ["COGNITO"]
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.environment}"
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
    Environment = var.environment
    Project     = var.app_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name = "${var.app_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito-authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  stage_name    = var.environment
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.app_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "${var.app_name}-lambda-role"

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

# Lambda Policy
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.app_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
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

# Lambda Functions
resource "aws_lambda_function" "crud_functions" {
  for_each = {
    add_item     = "POST"
    get_item     = "GET"
    get_all      = "GET"
    update_item  = "PUT"
    complete     = "POST"
    delete_item  = "DELETE"
  }

  filename         = "lambda/${each.key}.zip"
  function_name    = "${var.app_name}-${each.key}-${var.environment}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs12.x"
  memory_size     = 1024
  timeout         = 60

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name = var.app_name
  repository = var.github_repo
  access_token = var.github_access_token

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

  enable_auto_branch_creation = true
  enable_branch_auto_build = true

  environment_variables = {
    ENV = var.environment
  }
}

# Amplify Branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"
  
  framework = "React"
  stage     = "PRODUCTION"
}

# API Gateway IAM Role
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.app_name}-api-gateway-role"

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

# API Gateway CloudWatch Policy
resource "aws_iam_role_policy" "api_gateway_cloudwatch" {
  name = "${var.app_name}-api-gateway-cloudwatch"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Amplify IAM Role
resource "aws_iam_role" "amplify_role" {
  name = "${var.app_name}-amplify-role"

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

# Amplify Policy
resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.app_name}-amplify-policy"
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

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id

  depends_on = [
    aws_api_gateway_rest_api.todo_api,
    aws_api_gateway_authorizer.cognito
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.todo_app.default_domain
}