terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
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
  type    = string
  default = "https://github.com/your-username/your-repo" # Replace with your GitHub repo URL
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"
  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name             = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id     = aws_cognito_user_pool.main.id
  generate_secret  = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls = ["http://localhost:3000/"] # Replace with your logout URLs


  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 read_capacity  = 5
 write_capacity = 5
 server_side_encryption {
 enabled = true
 }

 attribute {
   name = "cognito-username"
   type = "S"
 }

 attribute {
   name = "id"
   type = "S"
 }

 hash_key = "cognito-username"
 range_key = "id"


  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_iam_role" "api_gateway_role" {
  name = "api_gateway_cloudwatch_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })

  tags = {
    Name        = "api_gateway_cloudwatch_role_${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}



resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api_gateway_cloudwatch_policy_${var.stack_name}"
  role = aws_iam_role.api_gateway_role.id


 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
        Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}




resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.application_name}-api-${var.stack_name}"
 description = "API Gateway for ${var.application_name}"



 tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cognito_authorizer"
 rest_api_id = aws_api_gateway_rest_api.main.id
 provider_arns = [aws_cognito_user_pool.main.arn]
  type = "COGNITO_USER_POOLS"
}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo_url
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
   baseDirectory: build
   files:
     - '**/*'
EOF

  tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-amplify-branch-master-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

}


resource "aws_iam_role" "lambda_role" {
  name = "lambda_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })
  tags = {
    Name        = "lambda_role_${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_policy" {

 name = "lambda_policy_${var.stack_name}"

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
 Resource = ["arn:aws:dynamodb:${var.region}:*:table/todo-table-${var.stack_name}",
          "arn:aws:logs:*:*:*",
 "arn:aws:xray:*:*:*"]
      },
    ]
  })
}



resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_policy.arn
}



output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "lambda_role_arn" {
 value = aws_iam_role.lambda_role.arn
}


