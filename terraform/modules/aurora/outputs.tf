output "cluster_id" {
  description = "Aurora cluster ID"
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "Aurora cluster ARN"
  value       = aws_rds_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Aurora writer endpoint"
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Aurora reader endpoint"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "Aurora PostgreSQL port"
  value       = aws_rds_cluster.this.port
}

output "security_group_id" {
  description = "Security group associated with Aurora"
  value       = aws_security_group.this.id
}

output "master_user_secret_arn" {
  description = "ARN of the RDS managed master user secret"
  value       = try(aws_rds_cluster.this.master_user_secret[0].secret_arn, null)
  sensitive   = true
}