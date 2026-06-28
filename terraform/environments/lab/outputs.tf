output "db_identifier" {
  value       = try(module.rds_postgres[0].db_identifier, null)
  description = "Identificador da instancia RDS PostgreSQL compartilhada."
}

output "db_endpoint" {
  value       = try(module.rds_postgres[0].db_endpoint, null)
  description = "Endpoint da instancia RDS."
}

output "db_port" {
  value       = try(module.rds_postgres[0].db_port, null)
  description = "Porta PostgreSQL."
}

output "db_username" {
  value       = try(module.rds_postgres[0].db_username, null)
  description = "Usuario administrativo inicial do RDS."
}

output "db_master_user_secret_arn" {
  value       = try(module.rds_postgres[0].db_master_user_secret_arn, null)
  description = "ARN do secret gerenciado pela AWS para o usuario administrativo."
}

output "db_security_group_id" {
  value       = try(module.rds_postgres[0].security_group_id, null)
  description = "Security group do RDS."
}

output "vpc_id" {
  value       = local.resolved_vpc_id
  description = "VPC usada pelos recursos compartilhados."
}

output "subnet_ids" {
  value       = local.resolved_subnet_ids
  description = "Subnets usadas pelos recursos compartilhados."
}

output "eks_cluster_name" {
  value       = try(module.eks[0].cluster_name, null)
  description = "Nome do cluster EKS compartilhado."
}

output "eks_cluster_endpoint" {
  value       = try(module.eks[0].cluster_endpoint, null)
  description = "Endpoint do cluster EKS compartilhado."
}

output "ecr_repository_urls" {
  value = {
    for name, repository in module.ecr : name => repository.repository_url
  }
  description = "URLs dos repositorios ECR canonicos."
}

output "api_gateway_endpoint" {
  value       = try(module.api_gateway[0].api_endpoint, null)
  description = "Endpoint publico do API Gateway HTTP."
}

output "terraform_shared_data_bucket_name" {
  value       = try(module.terraform_shared_data_bucket[0].bucket_name, null)
  description = "Bucket S3 compartilhado criado pelo Terraform, quando habilitado."
}
