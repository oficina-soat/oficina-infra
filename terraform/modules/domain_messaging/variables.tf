variable "routes" {
  type = map(object({
    event_type = string
    topic      = string
    producer   = string
    consumers  = list(string)
  }))
  description = "Rotas canonicas evento -> topico -> produtor -> consumidores."

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      route.event_type != "" && can(regex("^oficina\\.[a-z]+\\.[a-z0-9-]+$", route.topic)) && length(route.consumers) > 0
    ])
    error_message = "Cada rota deve ter event_type, topico oficina.<dominio>.<evento> e pelo menos um consumidor."
  }
}

variable "policy_name_prefix" {
  type        = string
  description = "Prefixo das politicas IAM gerenciadas de mensageria."
}

variable "max_receive_count" {
  type        = number
  description = "Numero maximo de recebimentos antes de enviar mensagem para DLQ."
  default     = 5
}

variable "queue_visibility_timeout_seconds" {
  type        = number
  description = "Visibility timeout das filas consumidoras."
  default     = 30
}

variable "queue_message_retention_seconds" {
  type        = number
  description = "Retencao das mensagens nas filas consumidoras."
  default     = 345600
}

variable "dlq_message_retention_seconds" {
  type        = number
  description = "Retencao das mensagens nas DLQs."
  default     = 1209600
}

variable "queue_receive_wait_time_seconds" {
  type        = number
  description = "Long polling das filas SQS."
  default     = 10
}

variable "raw_message_delivery" {
  type        = bool
  description = "Quando true, entrega no SQS o envelope de dominio publicado no SNS, sem envelope adicional do SNS."
  default     = true
}

variable "sqs_managed_sse_enabled" {
  type        = bool
  description = "Habilita criptografia SSE gerenciada pelo SQS."
  default     = true
}

variable "sns_kms_master_key_id" {
  type        = string
  description = "KMS key opcional para topicos SNS. Se nulo, usa configuracao padrao do SNS."
  default     = null
}

variable "create_runtime_iam_policies" {
  type        = bool
  description = "Quando true, cria politicas IAM gerenciadas separadas para produtores e consumidores."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags comuns."
  default     = {}
}
