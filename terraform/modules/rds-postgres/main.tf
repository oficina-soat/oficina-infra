locals {
  db_port              = 5432
  name_prefix          = var.db_identifier
  engine_major_version = split(".", var.engine_version)[0]
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Component = "rds-postgres"
  })
}

resource "aws_db_subnet_group" "this" {
  name        = "${local.name_prefix}-subnet-group"
  description = "Subnets do RDS PostgreSQL compartilhado ${var.db_identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-subnet-group"
  })
}

resource "aws_security_group" "this" {
  name        = "${local.name_prefix}-sg"
  description = "Acesso ao PostgreSQL gerenciado da Oficina"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
  description                  = "PostgreSQL a partir do security group ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "from_cidrs" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = local.db_port
  to_port           = local.db_port
  description       = "PostgreSQL a partir do CIDR ${each.value}"
}

resource "aws_vpc_security_group_egress_rule" "this" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = toset(var.enabled_cloudwatch_logs_exports)

  name              = "/aws/rds/instance/${var.db_identifier}/${each.value}"
  retention_in_days = var.cloudwatch_log_retention_in_days

  tags = local.common_tags
}

resource "aws_db_parameter_group" "this" {
  name        = "${local.name_prefix}-pg"
  family      = "postgres${local.engine_major_version}"
  description = "Parametros PostgreSQL de producao para ${var.db_identifier}"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "password_encryption"
    value        = "scram-sha-256"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_statement_ms)
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-pg"
  })
}

resource "aws_db_instance" "this" {
  identifier                          = var.db_identifier
  engine                              = "postgres"
  engine_version                      = var.engine_version
  instance_class                      = var.instance_class
  allocated_storage                   = var.allocated_storage
  max_allocated_storage               = var.max_allocated_storage
  storage_type                        = var.storage_type
  storage_encrypted                   = true
  kms_key_id                          = var.storage_kms_key_id
  username                            = var.db_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = var.master_user_secret_kms_key_id
  port                                = local.db_port
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.this.id]
  parameter_group_name                = aws_db_parameter_group.this.name
  backup_retention_period             = var.backup_retention_period
  backup_window                       = var.backup_window
  maintenance_window                  = var.maintenance_window
  multi_az                            = var.multi_az
  publicly_accessible                 = var.publicly_accessible
  apply_immediately                   = var.apply_immediately
  deletion_protection                 = var.deletion_protection
  delete_automated_backups            = false
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : var.final_snapshot_identifier
  iam_database_authentication_enabled = false
  allow_major_version_upgrade         = false
  auto_minor_version_upgrade          = true
  copy_tags_to_snapshot               = true
  enabled_cloudwatch_logs_exports     = var.enabled_cloudwatch_logs_exports
  ca_cert_identifier                  = var.ca_cert_identifier

  tags = merge(local.common_tags, {
    Name = var.db_identifier
  })

  depends_on = [
    aws_cloudwatch_log_group.this
  ]
}
