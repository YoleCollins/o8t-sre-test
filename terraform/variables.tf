variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttling burst limit"
  type        = number
  default     = 100
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttling rate limit (requests per second)"
  type        = number
  default     = 50
}

variable "enable_provisioned_concurrency" {
  description = "Enable provisioned concurrency to eliminate cold starts (increases cost)"
  type        = bool
  default     = false
}

variable "provisioned_concurrency_count" {
  description = "Number of provisioned concurrent executions"
  type        = number
  default     = 2
}