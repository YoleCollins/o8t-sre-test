provider "aws" {
  region = var.aws_region
}

# --- DynamoDB Table ---
resource "aws_dynamodb_table" "llm_scores" {
  name           = "llm_scores"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "model_name"

  attribute {
    name = "model_name"
    type = "S"
  }

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Cost tracking
  tags = {
    Name        = "llm-scores-table"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# --- IAM Role for Lambda ---
resource "aws_iam_role" "lambda_role" {
  name = "llm_scores_lambda_role"

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

# Policy to allow logging and DynamoDB access
resource "aws_iam_role_policy" "lambda_policy" {
  name = "llm_scores_lambda_policy"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.llm_scores.arn
      }
    ]
  })
}

# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/llm_scores_service"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "llm-scores-lambda-logs"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# --- Lambda Function ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../src"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "llm_service" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "llm_scores_service"
  role             = aws_iam_role.lambda_role.arn
  handler          = "app.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.llm_scores.name
      ENVIRONMENT = var.environment
    }
  }

  # Associate log group
  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = {
    Name        = "llm-scores-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# --- API Gateway (HTTP API) ---
resource "aws_apigatewayv2_api" "http_api" {
  name          = "llm_scores_api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  # Rate limiting
  default_route_settings {
    throttling_burst_limit = var.api_throttle_burst_limit
    throttling_rate_limit  = var.api_throttle_rate_limit
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.llm_service.invoke_arn
}

resource "aws_apigatewayv2_route" "get_llms" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /llms"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.llm_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# --- Basic CloudWatch Alarms ---
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "llm-scores-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 10 # Alert if >10 errors in 2 minutes
  alarm_description   = "Lambda function errors"

  dimensions = {
    FunctionName = aws_lambda_function.llm_service.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  alarm_name          = "llm-scores-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "API Gateway 5XX errors"

  dimensions = {
    ApiName = aws_apigatewayv2_api.http_api.name
    Stage   = aws_apigatewayv2_stage.default.name
  }
}