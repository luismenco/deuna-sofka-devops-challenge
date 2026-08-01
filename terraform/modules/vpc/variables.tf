variable "name" {
  description = "Name prefix used for VPC resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block assigned to the VPC"
  type        = string
}

variable "availability_zones" {
  description = "Availability Zones used to distribute the subnets"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two Availability Zones must be provided."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks assigned to public subnets"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least two public subnet CIDRs must be provided."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks assigned to private subnets"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnet CIDRs must be provided."
  }
}

variable "enable_nat_gateway" {
  description = "Enable outbound Internet access from private subnets through a NAT Gateway"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags applied to VPC resources"
  type        = map(string)
  default     = {}
}