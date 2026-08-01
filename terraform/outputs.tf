output "aurora_cluster_endpoint" {
  description = "Aurora PostgreSQL writer endpoint"
  value       = module.aurora.cluster_endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora PostgreSQL reader endpoint"
  value       = module.aurora.reader_endpoint
}

output "aurora_security_group_id" {
  description = "Security group associated with Aurora"
  value       = module.aurora.security_group_id
}