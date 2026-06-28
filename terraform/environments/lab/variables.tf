variable "region" {
  type        = string
  description = "Regiao AWS canonica da Fase 4."
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Ambiente canonico da Fase 4."
  default     = "lab"
}

variable "shared_infra_name" {
  type        = string
  description = "Nome da infraestrutura compartilhada."
  default     = "eks-lab"
}

variable "db_identifier" {
  type        = string
  description = "Identificador da instancia RDS PostgreSQL compartilhada."
  default     = "oficina-postgres-lab"
}

variable "db_username" {
  type        = string
  description = "Usuario administrativo inicial do RDS."
  default     = "oficina_master"
}

variable "vpc_id" {
  type        = string
  description = "VPC do EKS compartilhado. Informe via terraform.tfvars ou -var."
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets para o RDS. Informe pelo menos duas via terraform.tfvars ou -var."
  default     = []
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups autorizados a conectar no RDS, preferencialmente workloads do EKS."
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDRs autorizados a conectar no RDS para bootstrap ou acesso operacional controlado."
  default     = []
}

variable "instance_class" {
  type        = string
  description = "Classe da instancia RDS."
  default     = "db.t4g.micro"
}

variable "deletion_protection" {
  type        = bool
  description = "Protecao contra destruicao acidental."
  default     = true
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Pula snapshot final ao destruir."
  default     = false
}

variable "final_snapshot_identifier" {
  type        = string
  description = "Identificador do snapshot final quando skip_final_snapshot=false."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais."
  default     = {}
}
