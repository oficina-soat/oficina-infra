output "topic_arns_by_event" {
  value = {
    for key, topic in aws_sns_topic.this : key => topic.arn
  }
  description = "ARNs dos topicos SNS por eventType."
}

output "topic_names_by_event" {
  value = {
    for key, topic in aws_sns_topic.this : key => topic.name
  }
  description = "Nomes fisicos dos topicos SNS por eventType."
}

output "consumer_queue_arns" {
  value = {
    for key, queue in aws_sqs_queue.consumer : key => queue.arn
  }
  description = "ARNs das filas consumidoras no formato eventType:servico."
}

output "consumer_queue_urls" {
  value = {
    for key, queue in aws_sqs_queue.consumer : key => queue.url
  }
  description = "URLs das filas consumidoras no formato eventType:servico."
}

output "dlq_arns_by_event" {
  value = {
    for key, queue in aws_sqs_queue.dlq : key => queue.arn
  }
  description = "ARNs das DLQs por eventType."
}

output "producer_policy_arns" {
  value = {
    for service, policy in aws_iam_policy.producer : service => policy.arn
  }
  description = "ARNs das politicas IAM de publicacao por servico produtor."
}

output "consumer_policy_arns" {
  value = {
    for service, policy in aws_iam_policy.consumer : service => policy.arn
  }
  description = "ARNs das politicas IAM de consumo por servico consumidor."
}
