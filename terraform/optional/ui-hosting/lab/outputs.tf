output "bucket_name" {
  description = "Bucket privado que recebe o build Angular."
  value       = aws_s3_bucket.ui.id
}

output "cloudfront_distribution_id" {
  description = "Distribuição usada pelo pipeline independente da UI."
  value       = aws_cloudfront_distribution.ui.id
}

output "cloudfront_domain_name" {
  description = "Domínio público padrão da UI."
  value       = aws_cloudfront_distribution.ui.domain_name
}

output "ui_url" {
  description = "URL HTTPS pública da UI."
  value       = "https://${aws_cloudfront_distribution.ui.domain_name}"
}
