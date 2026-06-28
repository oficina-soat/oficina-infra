output "db_identifier" {
  value       = module.rds_postgres.db_identifier
  description = "Identificador da instancia RDS PostgreSQL compartilhada."
}

output "db_endpoint" {
  value       = module.rds_postgres.db_endpoint
  description = "Endpoint da instancia RDS."
}

output "db_port" {
  value       = module.rds_postgres.db_port
  description = "Porta PostgreSQL."
}

output "db_username" {
  value       = module.rds_postgres.db_username
  description = "Usuario administrativo inicial do RDS."
}

output "db_master_user_secret_arn" {
  value       = module.rds_postgres.db_master_user_secret_arn
  description = "ARN do secret gerenciado pela AWS para o usuario administrativo."
}

output "db_security_group_id" {
  value       = module.rds_postgres.security_group_id
  description = "Security group do RDS."
}
