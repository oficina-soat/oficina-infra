output "table_names" {
  value = {
    for key, table in aws_dynamodb_table.this : key => table.name
  }
  description = "Nomes das tabelas DynamoDB por nome logico."
}

output "table_arns" {
  value = {
    for key, table in aws_dynamodb_table.this : key => table.arn
  }
  description = "ARNs das tabelas DynamoDB por nome logico."
}

output "stream_arns" {
  value = {
    for key, table in aws_dynamodb_table.this : key => table.stream_arn
    if local.table_definitions[key].stream_enabled
  }
  description = "ARNs dos streams DynamoDB habilitados por nome logico."
}

output "runtime_policy_arn" {
  value       = try(aws_iam_policy.runtime_access[0].arn, null)
  description = "ARN da politica IAM de runtime do oficina-execution-service."
}
