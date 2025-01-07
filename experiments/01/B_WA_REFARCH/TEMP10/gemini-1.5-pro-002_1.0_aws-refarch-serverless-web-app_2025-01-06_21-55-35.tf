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

variable "aws_region" {
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

variable "github_repo_url" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls = ["http://localhost:3000/"] # Update with your frontend callback URL
  logout_urls   = ["http://localhost:3000/"] # Update with your frontend logout URL

  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}



resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
 })
}

resource "aws_api_gateway_rest_api" "main" {
 name = "${var.application_name}-api-${var.stack_name}"
}


resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy-${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
"dynamodb:DescribeTable"

        ],
        Resource = aws_dynamodb_table.main.arn,
        Effect = "Allow"

      },
 {
                Effect = "Allow",
                Action = [
"cloudwatch:PutMetricData"
                    ],
                Resource = "*"
            }
    ]
  })


}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}





# Placeholder for Lambda function code - replace with actual implementation
data "archive_file" "lambda_zip" {
 type        = "zip"
 source_dir = "./lambda_functions" # Replace with the directory containing your Lambda functions
 output_path = "lambda_functions.zip"
}

resource "aws_lambda_function" "lambda_functions" {

  filename         = data.archive_file.lambda_zip.output_path
  function_name = "todo-lambda-functions-${var.stack_name}"
 handler = "index.handler" # Replace with your Lambda function handler
 runtime = "nodejs12.x" # Replace with the desired runtime environment
  memory_size = 1024
 timeout = 60
 role = aws_iam_role.lambda_execution_role.arn


 tracing_config {
    mode = "Active"
  }


  tags = {
    Name        = "todo-lambda-functions-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito_authorizer_${var.stack_name}"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]

}

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-app-${var.stack_name}"
  repository = var.github_repo_url
  #  access_token = var.github_access_token
  build_spec = <<EOF
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
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  stage       = "PRODUCTION"

  enable_auto_build = true
}




output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}



output "lambda_function_arn" {
 value = aws_lambda_function.lambda_functions.arn
}



output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}
