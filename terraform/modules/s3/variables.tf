variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the bucket"
  type        = string
}

variable "transition_days" {
  description = "Number of days before transitioning objects to STANDARD_IA"
  type        = number
  default     = 90
}

variable "noncurrent_expiration_days" {
  description = "Number of days before deleting noncurrent object versions"
  type        = number
  default     = 365
}

variable "tags" {
  description = "Additional tags applied to S3 resources"
  type        = map(string)
  default     = {}
}