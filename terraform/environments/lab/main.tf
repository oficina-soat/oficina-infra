data "aws_caller_identity" "current" {}

data "aws_vpc" "selected" {
  id = local.resolved_vpc_id
}

locals {
  azs          = length(var.azs) > 0 ? slice(var.azs, 0, 2) : ["${var.region}a", "${var.region}b"]
  input_vpc_id = var.vpc_id != null && trimspace(var.vpc_id) != "" ? var.vpc_id : null
  input_api_gateway_name = (
    var.api_gateway_name != null && trimspace(var.api_gateway_name) != "" ? var.api_gateway_name : null
  )
  input_terraform_shared_data_bucket_name = (
    var.terraform_shared_data_bucket_name != null && trimspace(var.terraform_shared_data_bucket_name) != "" ? var.terraform_shared_data_bucket_name : null
  )
  input_eks_cluster_role_arn = (
    var.eks_cluster_role_arn != null && trimspace(var.eks_cluster_role_arn) != "" ? var.eks_cluster_role_arn : null
  )
  input_eks_node_role_arn = (
    var.eks_node_role_arn != null && trimspace(var.eks_node_role_arn) != "" ? var.eks_node_role_arn : null
  )
  input_final_snapshot_identifier = (
    var.final_snapshot_identifier != null && trimspace(var.final_snapshot_identifier) != "" ? var.final_snapshot_identifier : null
  )
  default_tags = merge(var.tags, {
    Project               = "oficina"
    Environment           = var.environment
    DeploymentEnvironment = var.environment
    SharedInfra           = var.shared_infra_name
    Repository            = "oficina-infra"
  })
  create_network = local.input_vpc_id == null && var.create_network_if_missing
  resolved_vpc_id = coalesce(
    local.input_vpc_id,
    try(module.network[0].vpc_id, null),
  )
  resolved_subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : try(module.network[0].public_subnet_ids, [])
  api_gateway_name    = coalesce(local.input_api_gateway_name, "${var.shared_infra_name}-http-api")
  terraform_shared_data_bucket_name = coalesce(
    local.input_terraform_shared_data_bucket_name,
    "tf-shared-${var.shared_infra_name}-${data.aws_caller_identity.current.account_id}-${var.region}",
  )
  expose_microservices_api_gateway = var.create_api_gateway && var.create_eks && var.expose_microservices_api_gateway
  microservice_names = [
    "oficina-os-service",
    "oficina-billing-service",
    "oficina-execution-service",
  ]
  microservice_private_nlb_names = {
    oficina-os-service        = substr("${var.cluster_name}-os-service", 0, 32)
    oficina-billing-service   = substr("${var.cluster_name}-billing-service", 0, 32)
    oficina-execution-service = substr("${var.cluster_name}-execution-service", 0, 32)
  }
  microservice_public_route_services = {
    "POST /api/v1/usuarios"                                       = "oficina-os-service"
    "GET /api/v1/usuarios"                                        = "oficina-os-service"
    "GET /api/v1/usuarios/{usuarioId}"                            = "oficina-os-service"
    "PUT /api/v1/usuarios/{usuarioId}"                            = "oficina-os-service"
    "DELETE /api/v1/usuarios/{usuarioId}"                         = "oficina-os-service"
    "POST /api/v1/usuarios/{usuarioId}/bloqueio"                  = "oficina-os-service"
    "POST /api/v1/usuarios/{usuarioId}/reativacao"                = "oficina-os-service"
    "GET /api/v1/dashboard/ordens-servico"                        = "oficina-os-service"
    "GET /api/v1/dashboard/usuarios"                              = "oficina-os-service"
    "POST /api/v1/clientes"                                       = "oficina-os-service"
    "GET /api/v1/clientes"                                        = "oficina-os-service"
    "GET /api/v1/clientes/{clienteId}"                            = "oficina-os-service"
    "PUT /api/v1/clientes/{clienteId}"                            = "oficina-os-service"
    "POST /api/v1/clientes/{clienteId}/veiculos"                  = "oficina-os-service"
    "GET /api/v1/clientes/{clienteId}/veiculos"                   = "oficina-os-service"
    "GET /api/v1/veiculos/{veiculoId}"                            = "oficina-os-service"
    "PUT /api/v1/veiculos/{veiculoId}"                            = "oficina-os-service"
    "POST /api/v1/ordens-servico"                                 = "oficina-os-service"
    "GET /api/v1/ordens-servico"                                  = "oficina-os-service"
    "GET /api/v1/ordens-servico/{ordemServicoId}"                 = "oficina-os-service"
    "GET /api/v1/ordens-servico/{ordemServicoId}/historico"       = "oficina-os-service"
    "POST /api/v1/ordens-servico/{ordemServicoId}/servicos"       = "oficina-os-service"
    "POST /api/v1/ordens-servico/{ordemServicoId}/pecas"          = "oficina-os-service"
    "PATCH /api/v1/ordens-servico/{ordemServicoId}/estado"        = "oficina-os-service"
    "POST /api/v1/ordens-servico/{ordemServicoId}/cancelamento"   = "oficina-os-service"
    "POST /api/v1/orcamentos"                                     = "oficina-billing-service"
    "GET /api/v1/orcamentos/{orcamentoId}"                        = "oficina-billing-service"
    "GET /api/v1/ordens-servico/{ordemServicoId}/orcamentos"      = "oficina-billing-service"
    "GET /api/v1/ordens-servico/{ordemServicoId}/acompanhar-link" = "oficina-billing-service"
    "GET /api/v1/ordens-servico/{ordemServicoId}/aprovar-link"    = "oficina-billing-service"
    "POST /api/v1/ordens-servico/{ordemServicoId}/aprovar-link"   = "oficina-billing-service"
    "GET /api/v1/ordens-servico/{ordemServicoId}/recusar-link"    = "oficina-billing-service"
    "POST /api/v1/ordens-servico/{ordemServicoId}/recusar-link"   = "oficina-billing-service"
    "POST /api/v1/orcamentos/{orcamentoId}/aprovacao"             = "oficina-billing-service"
    "POST /api/v1/orcamentos/{orcamentoId}/recusa"                = "oficina-billing-service"
    "POST /api/v1/pagamentos"                                     = "oficina-billing-service"
    "GET /api/v1/pagamentos/{pagamentoId}"                        = "oficina-billing-service"
    "GET /api/v1/ordens-servico/{ordemServicoId}/pagamentos"      = "oficina-billing-service"
    "POST /api/v1/pagamentos/{pagamentoId}/confirmacao"           = "oficina-billing-service"
    "POST /api/v1/pagamentos/{pagamentoId}/recusa"                = "oficina-billing-service"
    "POST /api/v1/pagamentos/{pagamentoId}/cancelamento"          = "oficina-billing-service"
    "POST /api/v1/pagamentos/{pagamentoId}/reconciliacao"         = "oficina-billing-service"
    "POST /api/v1/integracoes/mercado-pago/webhooks"              = "oficina-billing-service"
    "GET /api/v1/dashboard/faturamento"                           = "oficina-billing-service"
    "POST /api/v1/servicos"                                       = "oficina-execution-service"
    "GET /api/v1/servicos"                                        = "oficina-execution-service"
    "GET /api/v1/servicos/{servicoId}"                            = "oficina-execution-service"
    "PUT /api/v1/servicos/{servicoId}"                            = "oficina-execution-service"
    "POST /api/v1/pecas"                                          = "oficina-execution-service"
    "GET /api/v1/pecas"                                           = "oficina-execution-service"
    "GET /api/v1/pecas/{pecaId}"                                  = "oficina-execution-service"
    "PUT /api/v1/pecas/{pecaId}"                                  = "oficina-execution-service"
    "GET /api/v1/estoques/pecas/{pecaId}/saldo"                   = "oficina-execution-service"
    "GET /api/v1/estoques/movimentos"                             = "oficina-execution-service"
    "POST /api/v1/estoques/movimentos/entrada"                    = "oficina-execution-service"
    "POST /api/v1/estoques/movimentos/reserva"                    = "oficina-execution-service"
    "POST /api/v1/estoques/movimentos/consumo"                    = "oficina-execution-service"
    "POST /api/v1/estoques/movimentos/estorno"                    = "oficina-execution-service"
    "POST /api/v1/execucoes"                                      = "oficina-execution-service"
    "GET /api/v1/execucoes"                                       = "oficina-execution-service"
    "GET /api/v1/execucoes/fila"                                  = "oficina-execution-service"
    "GET /api/v1/execucoes/{execucaoId}"                          = "oficina-execution-service"
    "GET /api/v1/ordens-servico/{ordemServicoId}/execucao"        = "oficina-execution-service"
    "POST /api/v1/execucoes/{execucaoId}/diagnostico/inicio"      = "oficina-execution-service"
    "POST /api/v1/execucoes/{execucaoId}/diagnostico/conclusao"   = "oficina-execution-service"
    "POST /api/v1/execucoes/{execucaoId}/reparo/conclusao"        = "oficina-execution-service"
    "GET /api/v1/dashboard/execucao"                              = "oficina-execution-service"
  }
  microservice_public_api_gateway_http_routes = local.expose_microservices_api_gateway ? {
    for route_key, service_name in local.microservice_public_route_services : route_key => {
      integration_uri = module.microservice_private_nlb[service_name].listener_arn
      connection_type = "VPC_LINK"
    }
  } : {}
  api_gateway_http_routes = merge(
    local.microservice_public_api_gateway_http_routes,
    var.api_gateway_http_routes,
  )
  api_gateway_vpc_link_security_group_ids = local.expose_microservices_api_gateway ? concat(
    var.api_gateway_vpc_link_security_group_ids,
    [aws_security_group.microservices_api_gateway_vpc_link[0].id],
  ) : var.api_gateway_vpc_link_security_group_ids
  api_gateway_create_vpc_link_security_group = local.expose_microservices_api_gateway ? false : var.api_gateway_create_vpc_link_security_group
  input_execution_dynamodb_table_prefix = (
    var.execution_dynamodb_table_prefix != null && trimspace(var.execution_dynamodb_table_prefix) != "" ? var.execution_dynamodb_table_prefix : null
  )
  execution_dynamodb_table_prefix = coalesce(
    local.input_execution_dynamodb_table_prefix,
    "oficina-execution-${var.environment}",
  )
  domain_event_routes = {
    ordemDeServicoCriada = {
      event_type = "ordemDeServicoCriada"
      topic      = "oficina.os.ordem-de-servico-criada"
      producer   = "oficina-os-service"
      consumers  = ["oficina-billing-service", "oficina-execution-service"]
    }
    diagnosticoIniciado = {
      event_type = "diagnosticoIniciado"
      topic      = "oficina.execution.diagnostico-iniciado"
      producer   = "oficina-execution-service"
      consumers  = ["oficina-os-service"]
    }
    pecaIncluidaNaOrdemDeServico = {
      event_type = "pecaIncluidaNaOrdemDeServico"
      topic      = "oficina.os.peca-incluida-na-ordem-de-servico"
      producer   = "oficina-os-service"
      consumers  = ["oficina-billing-service", "oficina-execution-service"]
    }
    servicoIncluidoNaOrdemDeServico = {
      event_type = "servicoIncluidoNaOrdemDeServico"
      topic      = "oficina.os.servico-incluido-na-ordem-de-servico"
      producer   = "oficina-os-service"
      consumers  = ["oficina-billing-service", "oficina-execution-service"]
    }
    diagnosticoFinalizado = {
      event_type = "diagnosticoFinalizado"
      topic      = "oficina.execution.diagnostico-finalizado"
      producer   = "oficina-execution-service"
      consumers  = ["oficina-os-service", "oficina-billing-service"]
    }
    orcamentoGerado = {
      event_type = "orcamentoGerado"
      topic      = "oficina.billing.orcamento-gerado"
      producer   = "oficina-billing-service"
      consumers  = ["oficina-os-service"]
    }
    orcamentoAprovado = {
      event_type = "orcamentoAprovado"
      topic      = "oficina.billing.orcamento-aprovado"
      producer   = "oficina-billing-service"
      consumers  = ["oficina-os-service", "oficina-execution-service"]
    }
    orcamentoRecusado = {
      event_type = "orcamentoRecusado"
      topic      = "oficina.billing.orcamento-recusado"
      producer   = "oficina-billing-service"
      consumers  = ["oficina-os-service", "oficina-execution-service"]
    }
    execucaoIniciada = {
      event_type = "execucaoIniciada"
      topic      = "oficina.execution.execucao-iniciada"
      producer   = "oficina-execution-service"
      consumers  = ["oficina-os-service"]
    }
    execucaoFinalizada = {
      event_type = "execucaoFinalizada"
      topic      = "oficina.execution.execucao-finalizada"
      producer   = "oficina-execution-service"
      consumers  = ["oficina-os-service", "oficina-billing-service"]
    }
    ordemDeServicoFinalizada = {
      event_type = "ordemDeServicoFinalizada"
      topic      = "oficina.os.ordem-de-servico-finalizada"
      producer   = "oficina-os-service"
      consumers  = ["oficina-billing-service", "oficina-execution-service"]
    }
    ordemDeServicoEntregue = {
      event_type = "ordemDeServicoEntregue"
      topic      = "oficina.os.ordem-de-servico-entregue"
      producer   = "oficina-os-service"
      consumers  = ["oficina-billing-service"]
    }
    pagamentoSolicitado = {
      event_type = "pagamentoSolicitado"
      topic      = "oficina.billing.pagamento-solicitado"
      producer   = "oficina-billing-service"
      consumers  = ["oficina-os-service"]
    }
    pagamentoConfirmado = {
      event_type = "pagamentoConfirmado"
      topic      = "oficina.billing.pagamento-confirmado"
      producer   = "oficina-billing-service"
      consumers  = ["oficina-os-service"]
    }
    pagamentoRecusado = {
      event_type = "pagamentoRecusado"
      topic      = "oficina.billing.pagamento-recusado"
      producer   = "oficina-billing-service"
      consumers  = ["oficina-os-service"]
    }
    estoqueAcrescentado = {
      event_type = "estoqueAcrescentado"
      topic      = "oficina.execution.estoque-acrescentado"
      producer   = "oficina-execution-service"
      consumers  = ["oficina-billing-service"]
    }
    estoqueBaixado = {
      event_type = "estoqueBaixado"
      topic      = "oficina.execution.estoque-baixado"
      producer   = "oficina-execution-service"
      consumers  = ["oficina-billing-service"]
    }
    sagaCompensada = {
      event_type = "sagaCompensada"
      topic      = "oficina.saga.saga-compensada"
      producer   = "oficina-os-service"
      consumers  = ["oficina-billing-service", "oficina-execution-service"]
    }
    sagaFinalizadaComSucesso = {
      event_type = "sagaFinalizadaComSucesso"
      topic      = "oficina.saga.saga-finalizada-com-sucesso"
      producer   = "oficina-os-service"
      consumers  = ["oficina-billing-service", "oficina-execution-service"]
    }
    usuarioAdicionado = {
      event_type = "usuarioAdicionado"
      topic      = "oficina.os.usuario-adicionado"
      producer   = "oficina-os-service"
      consumers  = ["oficina-auth-sync-lambda"]
    }
    usuarioAtualizado = {
      event_type = "usuarioAtualizado"
      topic      = "oficina.os.usuario-atualizado"
      producer   = "oficina-os-service"
      consumers  = ["oficina-auth-sync-lambda"]
    }
    usuarioExcluido = {
      event_type = "usuarioExcluido"
      topic      = "oficina.os.usuario-excluido"
      producer   = "oficina-os-service"
      consumers  = ["oficina-auth-sync-lambda"]
    }
  }
}

check "canonical_environment" {
  assert {
    condition     = var.region == "us-east-1" && var.environment == "lab" && var.shared_infra_name == "eks-lab"
    error_message = "A Fase 4 usa region=us-east-1, environment=lab e shared_infra_name=eks-lab."
  }
}

check "network_inputs" {
  assert {
    condition     = local.create_network || (local.resolved_vpc_id != null && length(local.resolved_subnet_ids) >= 2)
    error_message = "Informe vpc_id e pelo menos duas subnet_ids, ou mantenha create_network_if_missing=true."
  }
}

check "database_access_inputs" {
  assert {
    condition     = !var.create_rds || var.create_eks || var.allow_rds_without_network_access || length(var.allowed_security_group_ids) > 0 || length(var.allowed_cidr_blocks) > 0
    error_message = "Informe allowed_security_group_ids, allowed_cidr_blocks, habilite create_eks ou marque explicitamente allow_rds_without_network_access durante a suspensao."
  }
}

check "eks_role_inputs" {
  assert {
    condition     = !var.create_eks || (local.input_eks_cluster_role_arn != null && local.input_eks_node_role_arn != null)
    error_message = "Informe EKS_CLUSTER_ROLE_ARN e EKS_NODE_ROLE_ARN quando create_eks=true."
  }
}

check "final_snapshot_inputs" {
  assert {
    condition     = var.skip_final_snapshot || local.input_final_snapshot_identifier != null
    error_message = "Informe final_snapshot_identifier quando skip_final_snapshot=false."
  }
}

check "execution_dynamodb_table_prefix" {
  assert {
    condition     = !var.create_execution_dynamodb || local.execution_dynamodb_table_prefix == "oficina-execution-${var.environment}"
    error_message = "O prefixo DynamoDB deve seguir oficina-execution-<environment>, por exemplo oficina-execution-lab."
  }
}

module "rds_postgres" {
  count  = var.create_rds ? 1 : 0
  source = "../../modules/rds-postgres"

  db_identifier              = var.db_identifier
  db_username                = var.db_username
  instance_class             = var.instance_class
  vpc_id                     = local.resolved_vpc_id
  subnet_ids                 = local.resolved_subnet_ids
  allowed_security_group_ids = var.allowed_security_group_ids
  allowed_cidr_blocks        = var.allowed_cidr_blocks
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  delete_automated_backups   = var.delete_automated_backups
  final_snapshot_identifier  = local.input_final_snapshot_identifier
  tags                       = local.default_tags
}

resource "aws_secretsmanager_secret" "auth_database" {
  count = var.create_rds ? 1 : 0

  name                    = var.auth_database_secret_name
  description             = "Conexao exclusiva das Lambdas ao database oficina_auth"
  recovery_window_in_days = 0

  tags = merge(local.default_tags, {
    Component = "auth-database"
    Owner     = "oficina-auth-lambda"
  })
}

module "network" {
  count  = local.create_network ? 1 : 0
  source = "../../modules/network"

  name                = var.shared_infra_name
  cluster_name        = var.cluster_name
  vpc_cidr            = var.network_vpc_cidr
  azs                 = local.azs
  public_subnet_cidrs = var.public_subnet_cidrs
}

module "eks" {
  count  = var.create_eks ? 1 : 0
  source = "../../modules/eks"

  cluster_name                 = var.cluster_name
  kubernetes_version           = var.kubernetes_version
  cluster_role_arn             = local.input_eks_cluster_role_arn
  node_role_arn                = local.input_eks_node_role_arn
  subnet_ids                   = local.resolved_subnet_ids
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  access_principal_arn         = var.eks_access_principal_arn
  instance_type                = var.instance_type
  node_capacity_type           = var.node_capacity_type
  node_ami_type                = var.node_ami_type
  desired_size                 = var.desired_size
  min_size                     = var.min_size
  max_size                     = var.max_size
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks_cluster" {
  count = var.create_rds && var.create_eks ? 1 : 0

  security_group_id            = module.rds_postgres[0].security_group_id
  referenced_security_group_id = module.eks[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL a partir do security group do cluster EKS ${var.cluster_name}"
}

resource "aws_security_group" "microservices_api_gateway_vpc_link" {
  count = local.expose_microservices_api_gateway ? 1 : 0

  name        = "${local.api_gateway_name}-microservices-vpc-link"
  description = "Security group do VPC Link do API Gateway para os microsservicos"
  vpc_id      = local.resolved_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # A exclusao do VPC Link retorna antes de o API Gateway liberar todas as
  # ENIs gerenciadas. O timeout ampliado permite que o provider repita a
  # remocao do security group durante essa janela de consistencia eventual.
  timeouts {
    delete = "45m"
  }

  tags = merge(local.default_tags, {
    Name = "${local.api_gateway_name}-microservices-vpc-link"
  })
}

module "microservice_private_nlb" {
  for_each = local.expose_microservices_api_gateway ? toset(local.microservice_names) : []
  source   = "../../modules/internal_nodeport_nlb"

  name                              = local.microservice_private_nlb_names[each.key]
  vpc_id                            = local.resolved_vpc_id
  subnet_ids                        = local.resolved_subnet_ids
  listener_port                     = var.microservice_private_listener_ports[each.key]
  target_node_port                  = var.microservice_node_ports[each.key]
  target_autoscaling_group_name     = module.eks[0].node_group_autoscaling_group_name
  allowed_source_security_group_ids = local.api_gateway_vpc_link_security_group_ids
  target_security_group_ids         = [module.eks[0].cluster_security_group_id]
  tags                              = local.default_tags
}

module "mailhog_smtp_private_nlb" {
  count  = var.create_eks ? 1 : 0
  source = "../../modules/internal_nodeport_nlb"

  name                              = substr("${var.cluster_name}-mailhog-smtp", 0, 32)
  vpc_id                            = local.resolved_vpc_id
  subnet_ids                        = local.resolved_subnet_ids
  listener_port                     = 1025
  target_node_port                  = 31025
  target_autoscaling_group_name     = module.eks[0].node_group_autoscaling_group_name
  allowed_source_security_group_ids = []
  allowed_source_cidr_blocks        = [data.aws_vpc.selected.cidr_block]
  target_security_group_ids         = [module.eks[0].cluster_security_group_id]
  tags                              = local.default_tags
}

module "ecr" {
  for_each = var.create_ecr_repositories ? var.ecr_repository_names : []
  source   = "../../modules/ecr"

  repository_name = each.value
  force_delete    = var.ecr_force_delete
}

module "api_gateway" {
  count  = var.create_api_gateway ? 1 : 0
  source = "../../modules/api_gateway"

  name                                 = local.api_gateway_name
  stage_name                           = var.api_gateway_stage_name
  enable_access_logs                   = var.api_gateway_enable_access_logs
  access_log_retention_in_days         = var.api_gateway_access_log_retention_in_days
  default_route_throttling_burst_limit = var.api_gateway_default_route_throttling_burst_limit
  default_route_throttling_rate_limit  = var.api_gateway_default_route_throttling_rate_limit
  enable_detailed_metrics              = var.api_gateway_enable_detailed_metrics
  vpc_id                               = local.resolved_vpc_id
  vpc_link_subnet_ids                  = length(var.api_gateway_vpc_link_subnet_ids) > 0 ? var.api_gateway_vpc_link_subnet_ids : local.resolved_subnet_ids
  vpc_link_security_group_ids          = local.api_gateway_vpc_link_security_group_ids
  create_vpc_link_security_group       = local.api_gateway_create_vpc_link_security_group
  http_routes                          = local.api_gateway_http_routes
  jwt_authorizers                      = var.api_gateway_jwt_authorizers
  lambda_routes                        = var.api_gateway_lambda_routes
  tags                                 = local.default_tags
}

module "execution_dynamodb" {
  count  = var.create_execution_dynamodb ? 1 : 0
  source = "../../modules/dynamodb_execution"

  providers = {
    aws          = aws
    aws.untagged = aws.untagged
  }

  table_prefix                   = local.execution_dynamodb_table_prefix
  point_in_time_recovery_enabled = var.execution_dynamodb_point_in_time_recovery_enabled
  deletion_protection_enabled    = var.execution_dynamodb_deletion_protection_enabled
  kms_key_arn                    = var.execution_dynamodb_kms_key_arn
  create_runtime_iam_policy      = var.create_runtime_iam_policies
  tags                           = local.default_tags
}

module "domain_messaging" {
  count  = var.create_domain_messaging ? 1 : 0
  source = "../../modules/domain_messaging"

  providers = {
    aws          = aws
    aws.untagged = aws.untagged
  }

  routes                           = local.domain_event_routes
  policy_name_prefix               = "oficina-${var.environment}-domain-messaging"
  max_receive_count                = var.domain_messaging_max_receive_count
  queue_visibility_timeout_seconds = var.domain_messaging_queue_visibility_timeout_seconds
  queue_message_retention_seconds  = var.domain_messaging_queue_message_retention_seconds
  dlq_message_retention_seconds    = var.domain_messaging_dlq_message_retention_seconds
  queue_receive_wait_time_seconds  = var.domain_messaging_queue_receive_wait_time_seconds
  raw_message_delivery             = var.domain_messaging_raw_message_delivery
  sqs_managed_sse_enabled          = var.domain_messaging_sqs_managed_sse_enabled
  sns_kms_master_key_id            = var.domain_messaging_sns_kms_master_key_id
  create_runtime_iam_policies      = var.create_runtime_iam_policies
  tags                             = local.default_tags
}

data "aws_iam_role" "auth_sync_lambda" {
  count = var.create_domain_messaging && var.create_runtime_iam_policies && var.attach_auth_sync_lambda_consumer_policy ? 1 : 0
  name  = var.auth_sync_lambda_role_name
}

resource "aws_iam_role_policy_attachment" "auth_sync_lambda_consumer" {
  count = var.create_domain_messaging && var.create_runtime_iam_policies && var.attach_auth_sync_lambda_consumer_policy ? 1 : 0

  role       = data.aws_iam_role.auth_sync_lambda[0].name
  policy_arn = module.domain_messaging[0].consumer_policy_arns["oficina-auth-sync-lambda"]
}

data "aws_iam_role" "auth_sync_lambda_runtime" {
  count = var.create_auth_sync_lambda ? 1 : 0
  name  = var.auth_sync_lambda_role_name
}

data "archive_file" "auth_sync_lambda_placeholder" {
  count       = var.create_auth_sync_lambda ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/.terraform/auth-sync-lambda-placeholder.zip"

  source {
    content  = "#!/bin/sh\necho 'Pacote nativo ainda nao publicado' >&2\nexit 1\n"
    filename = "bootstrap"
  }
}

resource "aws_security_group" "auth_sync_lambda" {
  count = var.create_auth_sync_lambda ? 1 : 0

  name        = "${var.auth_sync_lambda_function_name}-sg"
  description = "Egress da Lambda de sincronizacao de usuarios"
  vpc_id      = local.resolved_vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.default_tags, {
    Name = var.auth_sync_lambda_function_name
  })

}

resource "aws_vpc_security_group_ingress_rule" "rds_from_auth_sync_lambda" {
  count = var.create_auth_sync_lambda && var.create_rds ? 1 : 0

  security_group_id            = module.rds_postgres[0].security_group_id
  referenced_security_group_id = aws_security_group.auth_sync_lambda[0].id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL a partir da oficina-auth-sync-lambda"
}

resource "aws_lambda_function" "auth_sync" {
  count = var.create_auth_sync_lambda ? 1 : 0

  function_name    = var.auth_sync_lambda_function_name
  description      = "Projeta usuarios do oficina-os-service no store de autenticacao"
  filename         = data.archive_file.auth_sync_lambda_placeholder[0].output_path
  source_code_hash = data.archive_file.auth_sync_lambda_placeholder[0].output_base64sha256
  role             = data.aws_iam_role.auth_sync_lambda_runtime[0].arn
  runtime          = "provided.al2023"
  handler          = "not.used.in.provided.runtime"
  architectures    = ["x86_64"]
  memory_size      = var.auth_sync_lambda_memory_size
  timeout          = var.auth_sync_lambda_timeout_seconds

  vpc_config {
    subnet_ids         = local.resolved_subnet_ids
    security_group_ids = [aws_security_group.auth_sync_lambda[0].id]
  }

  tags = local.default_tags

  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
      environment,
    ]
  }
}

locals {
  auth_sync_event_types = toset([
    "usuarioAdicionado",
    "usuarioAtualizado",
    "usuarioExcluido",
  ])
}

resource "aws_lambda_event_source_mapping" "auth_sync" {
  for_each = var.create_auth_sync_lambda && var.create_domain_messaging ? local.auth_sync_event_types : toset([])

  event_source_arn = module.domain_messaging[0].consumer_queue_arns["${each.value}:oficina-auth-sync-lambda"]
  function_name    = aws_lambda_function.auth_sync[0].arn
  batch_size       = 10
  enabled          = false

  function_response_types = ["ReportBatchItemFailures"]

  lifecycle {
    ignore_changes = [enabled]
  }
}

module "terraform_shared_data_bucket" {
  count  = var.create_terraform_shared_data_bucket ? 1 : 0
  source = "../../modules/terraform_shared_data_bucket"

  bucket_name   = local.terraform_shared_data_bucket_name
  force_destroy = var.terraform_shared_data_bucket_force_destroy
}
