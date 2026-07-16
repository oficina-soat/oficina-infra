variable "region" {
  description = "Região dos recursos de hospedagem da UI."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente identificado nas tags e nomes."
  type        = string
  default     = "lab"
}

variable "bucket_name" {
  description = "Nome opcional do bucket privado; quando nulo, deriva conta e região."
  type        = string
  default     = null
  nullable    = true
}

variable "force_destroy" {
  description = "Permite remover os artefatos ao destruir esta stack opcional."
  type        = bool
  default     = true
}

variable "connect_src_origins" {
  description = "Origins HTTPS públicos permitidos pelo CSP para acesso às APIs."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for origin in var.connect_src_origins : can(regex("^https://[^/]+$", origin))
    ])
    error_message = "Cada origin de connect_src_origins deve usar HTTPS e não conter caminho."
  }
}

variable "tags" {
  description = "Tags adicionais aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
