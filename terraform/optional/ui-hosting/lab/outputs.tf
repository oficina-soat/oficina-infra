output "ecr_repository_url" {
  description = "URL do repositório que recebe a imagem validada da UI."
  value       = module.ecr.repository_url
}

output "eks_cluster_name" {
  description = "Cluster compartilhado onde a UI opcional é executada."
  value       = local.main.eks_cluster_name
}

output "ui_url" {
  description = "URL HTTPS pública compartilhada pela UI e APIs."
  value       = local.main.api_gateway_endpoint
}

output "route_key" {
  description = "Rota de fallback exclusiva da UI no HTTP API."
  value       = aws_apigatewayv2_route.ui.route_key
}
