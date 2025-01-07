terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack for identification"
  default     = "prod-stack"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"
  
  auto_verified_attributes = ["email"]

  policies {
    password_policy {
      minimum_length    = 6
      require_lowercase = true
      require_numbers   = false
      require_symbols   = false
      require_uppercase = true
    }
  }

  tags = {
    Name       = "${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                   = "${var.stack_name}-client"
  user_pool_id           = aws_cognito_user_pool.user_pool.id
  generate_secret        = false
  allowed_oauth_flows    = ["code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  
  tags = {
    Name        = "${var.stack_name}-client"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = "${var.stack_name}.auth.${var.aws_region}.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  tags = {
    Name        = "${var.stack_name}-domain"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key     = "cognito-username"
  range_key    = "id"

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
    Project     = "ServerlessApp"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name} application"

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  
  tags = {
    Name        = "${var.stack_name}-prod-stage"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = ""
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  identity_source = "method.request.header.Authorization"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  type          = "COGNITO_USER_POOLS"

  tags = {
    Name        = "${var.stack_name}-cognito-authorizer"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_lambda_function" "crud_function" {
  for_each = {
    "AddItem"       = "POST /item"
    "GetItem"       = "GET /item/{id}"
    "GetAllItems"   = "GET /item"
    "UpdateItem"    = "PUT /item/{id}"
    "CompleteItem"  = "POST /item/{id}/done"
    "DeleteItem"    = "DELETE /item/{id}"
  }

  function_name = "${each.key}-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }
  
  tags = {
    Name        = "${each.key}-function"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_amplify_app" "frontend" {
  name                = "${var.stack_name}-amplify"
  repository          = var.github_repo
  oauth_token         = var.github_token
  build_spec          = file("amplify-build-spec.yml")

  auto_branch_creation {
    patterns                        = ["*"]
    enable_auto_build               = true
    enable_basic_auth               = false
    enable_pull_request_preview     = false
  }

  tags = {
    Name        = "${var.stack_name}-frontend"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_amplify_branch" "master" {
  app_id     = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build  = true

  tags = {
    Name        = "${var.stack_name}-master-branch"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-exec-role"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.stack_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.stack_name}-amplify-role"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSAmplifyAdminAccess"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.api_stage.invoke_url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
