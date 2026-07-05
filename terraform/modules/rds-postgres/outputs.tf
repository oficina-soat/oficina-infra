output "db_identifier" {
  value       = aws_db_instance.this.identifier
  description = "Identificador da instancia RDS."
}

output "db_endpoint" {
  value       = aws_db_instance.this.address
  description = "Endpoint DNS da instancia RDS."
}

output "db_port" {
  value       = aws_db_instance.this.port
  description = "Porta PostgreSQL."
}

output "db_username" {
  value       = aws_db_instance.this.username
  description = "Usuario administrativo inicial do RDS."
}

output "db_master_user_secret_arn" {
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
  description = "ARN do secret gerenciado pela AWS para o usuario administrativo."
}

output "security_group_id" {
  value       = aws_security_group.this.id
  description = "Security group da instancia RDS."
}
