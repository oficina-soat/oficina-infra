locals {
  default_tags = merge(var.tags, {
    Project               = "oficina"
    Environment           = var.environment
    DeploymentEnvironment = var.environment
    SharedInfra           = var.shared_infra_name
    Repository            = "oficina-infra"
  })
}

check "canonical_environment" {
  assert {
    condition     = var.region == "us-east-1" && var.environment == "lab" && var.shared_infra_name == "eks-lab"
    error_message = "A Fase 4 usa region=us-east-1, environment=lab e shared_infra_name=eks-lab."
  }
}

check "network_inputs" {
  assert {
    condition     = var.vpc_id != null && length(var.subnet_ids) >= 2
    error_message = "Informe vpc_id e pelo menos duas subnet_ids do EKS compartilhado."
  }
}

check "database_access_inputs" {
  assert {
    condition     = length(var.allowed_security_group_ids) > 0 || length(var.allowed_cidr_blocks) > 0
    error_message = "Informe allowed_security_group_ids para workloads do EKS ou allowed_cidr_blocks para bootstrap controlado."
  }
}

check "final_snapshot_inputs" {
  assert {
    condition     = var.skip_final_snapshot || var.final_snapshot_identifier != null
    error_message = "Informe final_snapshot_identifier quando skip_final_snapshot=false."
  }
}

module "rds_postgres" {
  source = "../../modules/rds-postgres"

  db_identifier              = var.db_identifier
  db_username                = var.db_username
  instance_class             = var.instance_class
  vpc_id                     = var.vpc_id
  subnet_ids                 = var.subnet_ids
  allowed_security_group_ids = var.allowed_security_group_ids
  allowed_cidr_blocks        = var.allowed_cidr_blocks
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.final_snapshot_identifier
  tags                       = local.default_tags
}
