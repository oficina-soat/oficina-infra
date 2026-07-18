output "ecr_repository_url" {
  description = "URL do repositório que recebe a imagem validada da UI."
  value       = module.ecr.repository_url
}

output "eks_cluster_name" {
  description = "Cluster compartilhado onde a UI opcional é executada."
  value       = try(local.main.eks_cluster_name, null)
}

output "ui_url" {
  description = "URL HTTPS pública compartilhada pela UI e APIs."
  value       = local.main.api_gateway_endpoint
}

output "route_key" {
  description = "Rota de fallback exclusiva da UI no HTTP API."
  value       = try(aws_apigatewayv2_route.ui[0].route_key, null)
}

output "ui_observability_endpoint" {
  description = "Endpoint público seguro que recebe a telemetria allowlist da UI."
  value       = "${local.main.api_gateway_endpoint}/ui/telemetry"
}

output "ui_observability_log_group" {
  description = "Log group usado para correlacionar a telemetria do navegador no lab."
  value       = aws_cloudwatch_log_group.ui_telemetry.name
}
