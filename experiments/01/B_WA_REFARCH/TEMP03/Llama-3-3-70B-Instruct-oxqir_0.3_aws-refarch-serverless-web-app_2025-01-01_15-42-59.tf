provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "stack_name" {
  type        = string
  default     = "my-stack"
}

variable "github_token" {
  type        = string
  sensitive   = true
}

variable "github_repo" {
  type        = string
  default     = "my-repo"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain               = "${var.stack_name}-auth"
  user_pool_id         = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  key_schema = [
    {
      attribute_name = "cognito-username"
      key_type       = "HASH"
    },
    {
      attribute_name = "id"
      key_type       = "RANGE"
    }
  ]
  server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_authorizer" "this" {
  name           = "${var.stack_name}-authorizer"
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id    = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_method.post, aws_api_gateway_method.get, aws_api_gateway_method.put, aws_api_gateway_method.delete]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_deployment.this.stage_name
  }
  quota {
    limit  = 5000
    offset = 0
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-get-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-get-all-items"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-update-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-complete-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-delete-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# API Gateway Integration
resource "aws_api_gateway_integration" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.stack_name}-app"
  description = "Amplify app for ${var.stack_name}"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_backend_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment = "prod"
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec"
  description = "Execution role for API Gateway"

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

resource "aws_iam_policy" "api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec-policy"
  description = "Policy for API Gateway execution role"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.stack_name}-lambda-exec"
  description = "Execution role for Lambda"

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

resource "aws_iam_policy" "lambda_exec" {
  name        = "${var.stack_name}-lambda-exec-policy"
  description = "Policy for Lambda execution role"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.stack_name}-amplify-exec"
  description = "Execution role for Amplify"

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

resource "aws_iam_policy" "amplify_exec" {
  name        = "${var.stack_name}-amplify-exec-policy"
  description = "Policy for Amplify execution role"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateBackendEnvironment",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "lambda_function_arns" {
  value = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}