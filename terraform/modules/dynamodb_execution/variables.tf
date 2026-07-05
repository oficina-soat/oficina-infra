variable "table_prefix" {
  type        = string
  description = "Prefixo canonico das tabelas DynamoDB do oficina-execution-service."

  validation {
    condition     = can(regex("^oficina-execution-[a-z0-9-]+$", var.table_prefix))
    error_message = "O prefixo das tabelas deve seguir o formato oficina-execution-<ambiente>."
  }
}

variable "point_in_time_recovery_enabled" {
  type        = bool
  description = "Habilita point-in-time recovery nas tabelas DynamoDB."
  default     = false
}

variable "deletion_protection_enabled" {
  type        = bool
  description = "Habilita protecao contra exclusao acidental das tabelas DynamoDB."
  default     = false
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key opcional para criptografia das tabelas DynamoDB. Se nulo, usa chave gerenciada pela AWS."
  default     = null
}

variable "create_runtime_iam_policy" {
  type        = bool
  description = "Quando true, cria politica IAM gerenciada para o runtime do oficina-execution-service."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags comuns."
  default     = {}
}
