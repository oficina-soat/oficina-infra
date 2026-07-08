variable "db_identifier" {
  type        = string
  description = "Identificador da instancia RDS PostgreSQL compartilhada."
}

variable "db_username" {
  type        = string
  description = "Usuario administrativo inicial do RDS. Nao deve ser usado por workloads."
  default     = "oficina_master"
}

variable "engine_version" {
  type        = string
  description = "Versao major do PostgreSQL gerenciado."
  default     = "16"
}

variable "instance_class" {
  type        = string
  description = "Classe da instancia RDS."
  default     = "db.t4g.micro"

  validation {
    condition     = contains(["db.t4g.micro", "db.t4g.small"], var.instance_class)
    error_message = "Use db.t4g.micro ou db.t4g.small para manter o baseline da Fase 4."
  }
}

variable "allocated_storage" {
  type        = number
  description = "Storage inicial em GB."
  default     = 20
}

variable "max_allocated_storage" {
  type        = number
  description = "Limite maximo em GB para autoscaling de storage."
  default     = 40
}

variable "storage_type" {
  type        = string
  description = "Tipo do storage do RDS."
  default     = "gp3"
}

variable "multi_az" {
  type        = bool
  description = "Habilita Multi-AZ. No ambiente lab, o default permanece false por custo."
  default     = false
}

variable "backup_retention_period" {
  type        = number
  description = "Dias de retencao de backup automatico."
  default     = 7
}

variable "backup_window" {
  type        = string
  description = "Janela diaria de backup em UTC."
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  type        = string
  description = "Janela semanal de manutencao em UTC."
  default     = "sun:04:00-sun:05:00"
}

variable "publicly_accessible" {
  type        = bool
  description = "Expoe a instancia publicamente."
  default     = false
}

variable "apply_immediately" {
  type        = bool
  description = "Aplica alteracoes imediatamente."
  default     = false
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

variable "delete_automated_backups" {
  type        = bool
  description = "Remove backups automaticos quando a instancia for destruida."
  default     = true
}

variable "final_snapshot_identifier" {
  type        = string
  description = "Identificador do snapshot final quando skip_final_snapshot=false."
  default     = null
}

variable "vpc_id" {
  type        = string
  description = "VPC onde o RDS sera criado."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets para o DB subnet group."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups autorizados a conectar no PostgreSQL."
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDRs autorizados a conectar no PostgreSQL. Preferir security groups em workloads."
  default     = []
}

variable "storage_kms_key_id" {
  type        = string
  description = "KMS key opcional para criptografia do storage."
  default     = null
}

variable "master_user_secret_kms_key_id" {
  type        = string
  description = "KMS key opcional para secret gerenciado do usuario master."
  default     = null
}

variable "ca_cert_identifier" {
  type        = string
  description = "CA certificate identifier do RDS."
  default     = null
}

variable "log_min_duration_statement_ms" {
  type        = number
  description = "Valor de log_min_duration_statement em milissegundos."
  default     = 1000
}

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "Logs exportados pelo RDS para CloudWatch."
  default     = ["postgresql", "upgrade"]
}

variable "cloudwatch_log_retention_in_days" {
  type        = number
  description = "Retencao dos logs do RDS."
  default     = 14
}

variable "tags" {
  type        = map(string)
  description = "Tags comuns."
  default     = {}
}
