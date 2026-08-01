variable "name" {
  description = "Name used for the KMS key alias"
  type        = string
}

variable "description" {
  description = "Description of the KMS key"
  type        = string
  default     = "KMS key for data encryption at rest"
}

variable "administrator_arns" {
  description = "IAM principals allowed to administer the KMS key"
  type        = list(string)
}

variable "key_user_arns" {
  description = "IAM principals allowed to use the KMS key"
  type        = list(string)
  default     = []
}

variable "deletion_window_in_days" {
  description = "Waiting period before KMS key deletion"
  type        = number
  default     = 30

  validation {
    condition = (
      var.deletion_window_in_days >= 7 &&
      var.deletion_window_in_days <= 30
    )

    error_message = "deletion_window_in_days must be between 7 and 30 days."
  }
}

variable "tags" {
  description = "Additional tags applied to the KMS key"
  type        = map(string)
  default     = {}
}