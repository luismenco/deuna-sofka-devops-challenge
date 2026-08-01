terraform {
  backend "s3" {
    bucket               = "deuna-terraform-state"
    key                  = "infrastructure/terraform.tfstate"
    region               = "us-east-1"
    encrypt              = true
    use_lockfile         = true
    workspace_key_prefix = "environments"
  }
}