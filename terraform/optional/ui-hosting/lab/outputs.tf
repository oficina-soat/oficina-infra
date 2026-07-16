output "bucket_name" {
  description = "Bucket que recebe o build Angular."
  value       = aws_s3_bucket.ui.id
}

output "cloudfront_distribution_id" {
  description = "Distribuição opcional usada pelo pipeline; vazia no fallback S3 do lab."
  value       = ""
}

output "website_domain_name" {
  description = "Domínio público padrão da UI."
  value       = aws_s3_bucket_website_configuration.ui.website_endpoint
}

output "ui_url" {
  description = "URL pública da UI no website S3 do lab."
  value       = "http://${aws_s3_bucket_website_configuration.ui.website_endpoint}"
}
