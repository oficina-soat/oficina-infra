data "terraform_remote_state" "main" {
  backend = "s3"

  config = {
    bucket = var.main_state_bucket
    key    = var.main_state_key
    region = var.main_state_region
  }
}

locals {
  main = data.terraform_remote_state.main.outputs
  tags = merge(var.tags, {
    Project               = "oficina"
    Environment           = var.environment
    DeploymentEnvironment = var.environment
    OptionalComponent     = "ui-workload"
    Repository            = "oficina-infra"
  })
}

check "shared_infrastructure_outputs" {
  assert {
    condition = alltrue([
      try(local.main.vpc_id, null) != null,
      try(length(local.main.subnet_ids), 0) > 0,
      try(local.main.eks_cluster_name, null) != null,
      try(local.main.eks_cluster_security_group_id, null) != null,
      try(local.main.eks_node_group_autoscaling_group_name, null) != null,
      try(local.main.api_gateway_id, null) != null,
      try(local.main.api_gateway_vpc_link_id, null) != null,
      try(length(local.main.api_gateway_vpc_link_security_group_ids), 0) > 0,
    ])
    error_message = "O state principal deve publicar EKS, VPC, HTTP API e VPC Link antes da stack opcional da UI."
  }
}

module "ecr" {
  source = "../../../modules/ecr"

  repository_name = var.ecr_repository_name
  force_delete    = var.force_destroy
}

module "private_nlb" {
  source = "../../../modules/internal_nodeport_nlb"

  name                              = substr("${var.cluster_name}-ui", 0, 32)
  vpc_id                            = local.main.vpc_id
  subnet_ids                        = local.main.subnet_ids
  listener_port                     = var.listener_port
  target_node_port                  = var.node_port
  target_autoscaling_group_name     = local.main.eks_node_group_autoscaling_group_name
  allowed_source_security_group_ids = local.main.api_gateway_vpc_link_security_group_ids
  target_security_group_ids         = [local.main.eks_cluster_security_group_id]
  tags                              = local.tags
}

resource "aws_apigatewayv2_integration" "ui" {
  api_id               = local.main.api_gateway_id
  integration_type     = "HTTP_PROXY"
  integration_method   = "ANY"
  integration_uri      = module.private_nlb.listener_arn
  connection_type      = "VPC_LINK"
  connection_id        = local.main.api_gateway_vpc_link_id
  timeout_milliseconds = 30000
  description          = "Oficina UI opcional no EKS"
}

resource "aws_apigatewayv2_route" "ui" {
  api_id             = local.main.api_gateway_id
  route_key          = "$default"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.ui.id}"
}
