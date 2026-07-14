variable "region" {
  type        = string
  description = "Regiao AWS canonica da Fase 4."
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Ambiente canonico da Fase 4."
  default     = "lab"
}

variable "shared_infra_name" {
  type        = string
  description = "Nome da infraestrutura compartilhada."
  default     = "eks-lab"
}

variable "create_network_if_missing" {
  type        = bool
  description = "Quando true, cria uma VPC publica minima para o lab quando vpc_id nao for informado."
  default     = true
}

variable "network_vpc_cidr" {
  type        = string
  description = "CIDR da VPC criada automaticamente quando create_network_if_missing=true."
  default     = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones usadas pela VPC. Se vazio, usa duas zonas derivadas da regiao."
  default     = []
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs das subnets publicas quando a rede for criada pelo Terraform."
  default     = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "create_rds" {
  type        = bool
  description = "Quando true, cria a instancia RDS PostgreSQL compartilhada."
  default     = true
}

variable "db_identifier" {
  type        = string
  description = "Identificador da instancia RDS PostgreSQL compartilhada."
  default     = "oficina-postgres-lab"
}

variable "db_username" {
  type        = string
  description = "Usuario administrativo inicial do RDS."
  default     = "oficina_master"
}

variable "vpc_id" {
  type        = string
  description = "VPC do ambiente lab. Se nulo, pode ser criada pelo modulo network."
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets do ambiente lab. Se vazia, usa as subnets criadas pelo modulo network."
  default     = []
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups autorizados a conectar no RDS, preferencialmente workloads do EKS."
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDRs autorizados a conectar no RDS para bootstrap ou acesso operacional controlado."
  default     = []
}

variable "allow_rds_without_network_access" {
  type        = bool
  description = "Permite manter o RDS sem ingress durante a suspensao do EKS. Use apenas em workflows de suspensao."
  default     = false
}

variable "create_eks" {
  type        = bool
  description = "Quando true, cria o cluster EKS compartilhado."
  default     = false
}

variable "cluster_name" {
  type        = string
  description = "Nome do cluster EKS compartilhado."
  default     = "eks-lab"
}

variable "kubernetes_version" {
  type        = string
  description = "Versao do Kubernetes a ser usada pelo cluster EKS."
  default     = "1.35"
}

variable "eks_cluster_role_arn" {
  type        = string
  description = "ARN da role existente usada pelo control plane do EKS."
  default     = null
}

variable "eks_node_role_arn" {
  type        = string
  description = "ARN da role existente usada pelos nodes do EKS."
  default     = null
}

variable "eks_access_principal_arn" {
  type        = string
  description = "Principal que recebe acesso administrativo ao cluster. Se nulo, o modulo tenta usar a identidade atual."
  default     = null
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs permitidos para acessar o endpoint publico do EKS."
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  type        = string
  description = "Tipo de instancia do managed node group."
  default     = "t3.medium"
}

variable "node_capacity_type" {
  type        = string
  description = "Tipo de capacidade do node group."
  default     = "ON_DEMAND"
}

variable "node_ami_type" {
  type        = string
  description = "AMI do managed node group."
  default     = "AL2023_x86_64_STANDARD"
}

variable "desired_size" {
  type        = number
  description = "Quantidade desejada de nodes."
  default     = 1
}

variable "min_size" {
  type        = number
  description = "Quantidade minima de nodes."
  default     = 1
}

variable "max_size" {
  type        = number
  description = "Quantidade maxima de nodes."
  default     = 1
}

variable "create_ecr_repositories" {
  type        = bool
  description = "Quando true, cria repositorios ECR canonicos dos microsservicos."
  default     = true
}

variable "ecr_repository_names" {
  type        = set(string)
  description = "Repositorios ECR dos microsservicos."
  default = [
    "oficina-os-service",
    "oficina-billing-service",
    "oficina-execution-service",
  ]
}

variable "ecr_force_delete" {
  type        = bool
  description = "Quando true, permite destruir repositorios ECR mesmo com imagens."
  default     = false
}

variable "create_api_gateway" {
  type        = bool
  description = "Quando true, cria o API Gateway HTTP compartilhado."
  default     = true
}

variable "api_gateway_name" {
  type        = string
  description = "Nome do API Gateway. Se nulo, usa eks-lab-http-api."
  default     = null
}

variable "api_gateway_stage_name" {
  type        = string
  description = "Nome do stage publicado automaticamente."
  default     = "$default"
}

variable "api_gateway_http_routes" {
  type = map(object({
    integration_uri      = string
    integration_method   = optional(string, "ANY")
    authorization_type   = optional(string, "NONE")
    authorizer_key       = optional(string)
    authorization_scopes = optional(list(string), [])
    connection_type      = optional(string, "INTERNET")
    timeout_milliseconds = optional(number, 30000)
    request_parameters   = optional(map(string), {})
  }))
  description = "Rotas HTTP_PROXY do API Gateway. As rotas dos microsservicos podem ser adicionadas quando os backends estiverem publicados."
  default     = {}
}

variable "api_gateway_jwt_authorizers" {
  type = map(object({
    issuer           = optional(string)
    audience         = list(string)
    identity_sources = optional(list(string), ["$request.header.Authorization"])
  }))
  description = "Authorizers JWT do API Gateway HTTP API."
  default     = {}
}

variable "api_gateway_lambda_routes" {
  type = map(object({
    invoke_arn             = string
    function_name          = optional(string)
    authorization_type     = optional(string, "NONE")
    authorizer_key         = optional(string)
    authorization_scopes   = optional(list(string), [])
    payload_format_version = optional(string, "2.0")
    timeout_milliseconds   = optional(number, 30000)
    request_parameters     = optional(map(string), {})
  }))
  description = "Rotas AWS_PROXY para Lambdas compartilhadas."
  default     = {}
}

variable "api_gateway_enable_access_logs" {
  type        = bool
  description = "Quando true, habilita access logs do API Gateway."
  default     = true
}

variable "api_gateway_access_log_retention_in_days" {
  type        = number
  description = "Retencao dos access logs do API Gateway."
  default     = 14
}

variable "api_gateway_default_route_throttling_burst_limit" {
  type        = number
  description = "Burst limit padrao do API Gateway."
  default     = 50
}

variable "api_gateway_default_route_throttling_rate_limit" {
  type        = number
  description = "Rate limit padrao do API Gateway."
  default     = 25
}

variable "api_gateway_enable_detailed_metrics" {
  type        = bool
  description = "Quando true, habilita metricas detalhadas por rota."
  default     = true
}

variable "api_gateway_vpc_link_subnet_ids" {
  type        = list(string)
  description = "Subnets usadas pelo VPC Link quando alguma rota usar VPC_LINK."
  default     = []
}

variable "api_gateway_vpc_link_security_group_ids" {
  type        = list(string)
  description = "Security groups existentes para o VPC Link."
  default     = []
}

variable "api_gateway_create_vpc_link_security_group" {
  type        = bool
  description = "Quando true, cria um security group dedicado para o VPC Link quando necessario."
  default     = true
}

variable "expose_microservices_api_gateway" {
  type        = bool
  description = "Quando true, publica as rotas REST de negocio dos microsservicos no HTTP API por VPC_LINK, NLB interno e NodePorts."
  default     = true
}

variable "microservice_private_listener_ports" {
  type        = map(number)
  description = "Portas privadas dos listeners NLB usados pelo API Gateway para cada microsservico."
  default = {
    oficina-os-service        = 8081
    oficina-billing-service   = 8082
    oficina-execution-service = 8083
  }

  validation {
    condition = alltrue([
      for port in values(var.microservice_private_listener_ports) : port >= 1 && port <= 65535
    ])
    error_message = "microservice_private_listener_ports deve conter apenas portas entre 1 e 65535."
  }
}

variable "microservice_node_ports" {
  type        = map(number)
  description = "NodePorts fixos dos Services Kubernetes dos microsservicos. Devem corresponder aos manifests em k8s/base de cada repositorio de servico."
  default = {
    oficina-os-service        = 30081
    oficina-billing-service   = 30082
    oficina-execution-service = 30083
  }

  validation {
    condition = alltrue([
      for port in values(var.microservice_node_ports) : port >= 30000 && port <= 32767
    ])
    error_message = "microservice_node_ports deve conter apenas portas entre 30000 e 32767."
  }
}

variable "create_terraform_shared_data_bucket" {
  type        = bool
  description = "Quando true, cria o bucket S3 compartilhado usado por states e dados de infraestrutura."
  default     = false
}

variable "terraform_shared_data_bucket_name" {
  type        = string
  description = "Nome do bucket S3 compartilhado. Se nulo, deriva de infra, conta e regiao."
  default     = null
}

variable "terraform_shared_data_bucket_force_destroy" {
  type        = bool
  description = "Quando true, permite destruir o bucket S3 mesmo com objetos."
  default     = false
}

variable "create_execution_dynamodb" {
  type        = bool
  description = "Quando true, cria as tabelas DynamoDB canonicas do oficina-execution-service."
  default     = true
}

variable "execution_dynamodb_table_prefix" {
  type        = string
  description = "Prefixo das tabelas DynamoDB do oficina-execution-service. Se nulo, deriva de environment."
  default     = null
}

variable "execution_dynamodb_point_in_time_recovery_enabled" {
  type        = bool
  description = "Habilita point-in-time recovery nas tabelas DynamoDB do oficina-execution-service."
  default     = false
}

variable "execution_dynamodb_deletion_protection_enabled" {
  type        = bool
  description = "Habilita protecao contra exclusao acidental das tabelas DynamoDB do oficina-execution-service."
  default     = false
}

variable "execution_dynamodb_kms_key_arn" {
  type        = string
  description = "KMS key opcional para criptografia das tabelas DynamoDB. Se nulo, usa chave gerenciada pela AWS."
  default     = null
}

variable "create_domain_messaging" {
  type        = bool
  description = "Quando true, cria SNS/SQS, assinaturas, DLQs e politicas IAM da mensageria da Fase 4."
  default     = true
}

variable "create_runtime_iam_policies" {
  type        = bool
  description = "Quando true, cria politicas IAM gerenciadas para runtime de DynamoDB e mensageria."
  default     = true
}

variable "attach_auth_sync_lambda_consumer_policy" {
  type        = bool
  description = "Quando true, anexa a policy SQS do oficina-auth-sync-lambda a role de execucao informada. Permanece false no VocLabs, onde o attachment e negado e a LabRole ja permite SQS em us-east-1."
  default     = false
}

variable "auth_sync_lambda_role_name" {
  type        = string
  description = "Nome da role IAM usada pela oficina-auth-sync-lambda para consumir as filas de usuarios."
  default     = "LabRole"

  validation {
    condition     = trimspace(var.auth_sync_lambda_role_name) != ""
    error_message = "auth_sync_lambda_role_name nao pode ser vazio."
  }
}

variable "create_auth_sync_lambda" {
  type        = bool
  description = "Quando true, declara a oficina-auth-sync-lambda e seus event source mappings SQS; o workflow do repositorio da Lambda atualiza o pacote nativo."
  default     = true
}

variable "auth_sync_lambda_function_name" {
  type        = string
  description = "Nome canonico da Lambda que projeta usuarios operacionais no store de autenticacao."
  default     = "oficina-auth-sync-lambda-lab"
}

variable "auth_sync_lambda_timeout_seconds" {
  type        = number
  description = "Timeout da oficina-auth-sync-lambda."
  default     = 30
}

variable "auth_sync_lambda_memory_size" {
  type        = number
  description = "Memoria em MB da oficina-auth-sync-lambda."
  default     = 256
}

variable "domain_messaging_max_receive_count" {
  type        = number
  description = "Quantidade maxima de recebimentos SQS antes de enviar para DLQ."
  default     = 5
}

variable "domain_messaging_queue_visibility_timeout_seconds" {
  type        = number
  description = "Visibility timeout das filas consumidoras da mensageria de dominio."
  default     = 30
}

variable "domain_messaging_queue_message_retention_seconds" {
  type        = number
  description = "Retencao das mensagens nas filas consumidoras."
  default     = 345600
}

variable "domain_messaging_dlq_message_retention_seconds" {
  type        = number
  description = "Retencao das mensagens nas DLQs."
  default     = 1209600
}

variable "domain_messaging_queue_receive_wait_time_seconds" {
  type        = number
  description = "Long polling das filas consumidoras."
  default     = 10
}

variable "domain_messaging_raw_message_delivery" {
  type        = bool
  description = "Quando true, entrega no SQS o envelope de dominio sem envelope adicional do SNS."
  default     = true
}

variable "domain_messaging_sqs_managed_sse_enabled" {
  type        = bool
  description = "Habilita criptografia SSE gerenciada pelo SQS nas filas e DLQs."
  default     = true
}

variable "domain_messaging_sns_kms_master_key_id" {
  type        = string
  description = "KMS key opcional para os topicos SNS. Se nulo, usa configuracao padrao do SNS."
  default     = null
}

variable "instance_class" {
  type        = string
  description = "Classe da instancia RDS."
  default     = "db.t4g.micro"
}

variable "deletion_protection" {
  type        = bool
  description = "Protecao contra destruicao acidental. No lab, o default permanece false para permitir destroy completo do ambiente."
  default     = false
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Pula snapshot final ao destruir."
  default     = true
}

variable "delete_automated_backups" {
  type        = bool
  description = "Remove backups automaticos do RDS no destroy do lab."
  default     = true
}

variable "final_snapshot_identifier" {
  type        = string
  description = "Identificador do snapshot final quando skip_final_snapshot=false."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais."
  default     = {}
}
