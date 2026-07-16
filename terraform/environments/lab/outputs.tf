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

output "auth_database_secret_name" {
  value       = try(aws_secretsmanager_secret.auth_database[0].name, null)
  description = "Nome do secret exclusivo do database oficina_auth."
}

output "auth_database_secret_arn" {
  value       = try(aws_secretsmanager_secret.auth_database[0].arn, null)
  description = "ARN do secret exclusivo do database oficina_auth."
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

output "api_gateway_http_route_keys" {
  value       = try(module.api_gateway[0].http_route_keys, [])
  description = "Route keys HTTP_PROXY publicadas no API Gateway."
}

output "microservice_private_nlb_dns_names" {
  value = {
    for name, nlb in module.microservice_private_nlb : name => nlb.load_balancer_dns_name
  }
  description = "DNS privados dos NLBs internos usados pelo API Gateway para os microsservicos."
}

output "microservice_private_nlb_listener_arns" {
  value = {
    for name, nlb in module.microservice_private_nlb : name => nlb.listener_arn
  }
  description = "Listener ARNs dos NLBs internos usados nas integracoes VPC_LINK dos microsservicos."
}

output "execution_dynamodb_table_names" {
  value       = try(module.execution_dynamodb[0].table_names, {})
  description = "Nomes das tabelas DynamoDB do oficina-execution-service."
}

output "execution_dynamodb_table_arns" {
  value       = try(module.execution_dynamodb[0].table_arns, {})
  description = "ARNs das tabelas DynamoDB do oficina-execution-service."
}

output "execution_dynamodb_stream_arns" {
  value       = try(module.execution_dynamodb[0].stream_arns, {})
  description = "ARNs dos streams DynamoDB habilitados."
}

output "execution_dynamodb_runtime_policy_arn" {
  value       = try(module.execution_dynamodb[0].runtime_policy_arn, null)
  description = "ARN da politica IAM de runtime do oficina-execution-service para DynamoDB."
}

output "domain_messaging_topic_names_by_event" {
  value       = try(module.domain_messaging[0].topic_names_by_event, {})
  description = "Nomes fisicos dos topicos SNS por eventType."
}

output "domain_messaging_topic_arns_by_event" {
  value       = try(module.domain_messaging[0].topic_arns_by_event, {})
  description = "ARNs dos topicos SNS por eventType."
}

output "domain_messaging_consumer_queue_urls" {
  value       = try(module.domain_messaging[0].consumer_queue_urls, {})
  description = "URLs das filas consumidoras no formato eventType:servico."
}

output "domain_messaging_dlq_arns_by_event" {
  value       = try(module.domain_messaging[0].dlq_arns_by_event, {})
  description = "ARNs das DLQs por eventType."
}

output "domain_messaging_producer_policy_arns" {
  value       = try(module.domain_messaging[0].producer_policy_arns, {})
  description = "ARNs das politicas IAM de publicacao por servico produtor."
}

output "domain_messaging_consumer_policy_arns" {
  value       = try(module.domain_messaging[0].consumer_policy_arns, {})
  description = "ARNs das politicas IAM de consumo por servico consumidor."
}

output "auth_sync_lambda_function_name" {
  value       = try(aws_lambda_function.auth_sync[0].function_name, null)
  description = "Nome da Lambda que projeta usuarios no store de autenticacao."
}

output "auth_sync_lambda_function_arn" {
  value       = try(aws_lambda_function.auth_sync[0].arn, null)
  description = "ARN da Lambda que projeta usuarios no store de autenticacao."
}

output "terraform_shared_data_bucket_name" {
  value       = try(module.terraform_shared_data_bucket[0].bucket_name, null)
  description = "Bucket S3 compartilhado criado pelo Terraform, quando habilitado."
}
