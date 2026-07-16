variable "region" {
  description = "Região dos recursos opcionais da UI."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente identificado nas tags e nomes."
  type        = string
  default     = "lab"
}

variable "cluster_name" {
  description = "Nome canônico do cluster EKS compartilhado."
  type        = string
  default     = "eks-lab"
}

variable "main_state_bucket" {
  description = "Bucket do state principal do lab."
  type        = string

  validation {
    condition     = trimspace(var.main_state_bucket) != ""
    error_message = "main_state_bucket deve ser informado."
  }
}

variable "main_state_key" {
  description = "Key do state principal do lab."
  type        = string
  default     = "oficina/lab/infra/terraform.tfstate"
}

variable "main_state_region" {
  description = "Região do backend do state principal."
  type        = string
  default     = "us-east-1"
}

variable "ecr_repository_name" {
  description = "Repositório ECR exclusivo da UI."
  type        = string
  default     = "oficina-ui"
}

variable "listener_port" {
  description = "Porta do listener interno usado pelo VPC Link."
  type        = number
  default     = 80
}

variable "node_port" {
  description = "NodePort canônico do Service oficina-ui."
  type        = number
  default     = 30084

  validation {
    condition     = var.node_port >= 30000 && var.node_port <= 32767
    error_message = "node_port deve estar entre 30000 e 32767."
  }
}

variable "force_destroy" {
  description = "Permite remover o ECR com imagens ao destruir a stack opcional."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags adicionais aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
