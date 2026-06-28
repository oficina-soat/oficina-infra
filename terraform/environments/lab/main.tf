data "aws_caller_identity" "current" {}

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
  resolved_allowed_security_group_ids = distinct(concat(
    var.allowed_security_group_ids,
    try([module.eks[0].cluster_security_group_id], []),
  ))
  api_gateway_name = coalesce(local.input_api_gateway_name, "${var.shared_infra_name}-http-api")
  terraform_shared_data_bucket_name = coalesce(
    local.input_terraform_shared_data_bucket_name,
    "tf-shared-${var.shared_infra_name}-${data.aws_caller_identity.current.account_id}-${var.region}",
  )
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
    condition     = !var.create_rds || var.create_eks || length(local.resolved_allowed_security_group_ids) > 0 || length(var.allowed_cidr_blocks) > 0
    error_message = "Informe allowed_security_group_ids, allowed_cidr_blocks ou habilite create_eks para permitir acesso ao RDS."
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
    condition     = var.skip_final_snapshot || var.final_snapshot_identifier != null
    error_message = "Informe final_snapshot_identifier quando skip_final_snapshot=false."
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
  allowed_security_group_ids = local.resolved_allowed_security_group_ids
  allowed_cidr_blocks        = var.allowed_cidr_blocks
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.final_snapshot_identifier
  tags                       = local.default_tags
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
  vpc_link_security_group_ids          = var.api_gateway_vpc_link_security_group_ids
  create_vpc_link_security_group       = var.api_gateway_create_vpc_link_security_group
  http_routes                          = var.api_gateway_http_routes
  jwt_authorizers                      = var.api_gateway_jwt_authorizers
  lambda_routes                        = var.api_gateway_lambda_routes
  tags                                 = local.default_tags
}

module "terraform_shared_data_bucket" {
  count  = var.create_terraform_shared_data_bucket ? 1 : 0
  source = "../../modules/terraform_shared_data_bucket"

  bucket_name   = local.terraform_shared_data_bucket_name
  force_destroy = var.terraform_shared_data_bucket_force_destroy
}
