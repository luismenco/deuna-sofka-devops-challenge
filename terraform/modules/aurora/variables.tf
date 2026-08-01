variable "name" {
  description = "Name prefix for Aurora resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC where Aurora will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by the Aurora cluster"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt Aurora"
  type        = string
}

variable "database_name" {
  description = "Initial database name"
  type        = string
  default     = "deuna"
}

variable "master_username" {
  description = "Master username for the Aurora cluster"
  type        = string
  default     = "pgadmin"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = null
}

variable "instance_class" {
  description = "Instance class used by Aurora instances"
  type        = string
  default     = "db.r7g.large"
}

variable "instance_count" {
  description = "Number of Aurora instances"
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1
    error_message = "At least one Aurora instance is required."
  }
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds"
  type        = number
  default     = 60
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect to Aurora"
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  description = "Enable deletion protection for the Aurora cluster"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying the Aurora cluster"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags applied to Aurora resources"
  type        = map(string)
  default     = {}
}

variable "secret_allowed_principal_arns" {
  description = "IAM principals allowed to access the Aurora master secret"
  type        = list(string)
}