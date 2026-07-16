data "terraform_remote_state" "main" {
  backend = "s3"

  config = {
    bucket = var.main_state_bucket
    key    = var.main_state_key
    region = var.main_state_region
  }
}

data "aws_caller_identity" "current" {}

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

data "archive_file" "ui_telemetry" {
  type        = "zip"
  source_file = "${path.module}/lambda/ui_telemetry.py"
  output_path = "${path.module}/.terraform/ui-telemetry.zip"
}

resource "aws_cloudwatch_log_group" "ui_telemetry" {
  name              = "/aws/lambda/oficina-ui-telemetry-${var.environment}"
  retention_in_days = 7
  tags              = local.tags
}

resource "aws_lambda_function" "ui_telemetry" {
  function_name    = "oficina-ui-telemetry-${var.environment}"
  role             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.lambda_role_name}"
  runtime          = "python3.13"
  handler          = "ui_telemetry.handler"
  filename         = data.archive_file.ui_telemetry.output_path
  source_code_hash = data.archive_file.ui_telemetry.output_base64sha256
  timeout          = 5
  memory_size      = 128
  tags             = local.tags

  depends_on = [
    aws_cloudwatch_log_group.ui_telemetry,
  ]
}

resource "aws_apigatewayv2_integration" "ui_telemetry" {
  api_id                 = local.main.api_gateway_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ui_telemetry.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 5000
}

resource "aws_apigatewayv2_route" "ui_telemetry" {
  api_id             = local.main.api_gateway_id
  route_key          = "POST /ui/telemetry"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.ui_telemetry.id}"
}

resource "aws_lambda_permission" "ui_telemetry_api" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ui_telemetry.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${local.main.api_gateway_id}/*/POST/ui/telemetry"
}
