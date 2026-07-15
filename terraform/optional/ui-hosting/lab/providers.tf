provider "aws" {
  region = var.region

  default_tags {
    tags = merge(var.tags, {
      Project               = "oficina"
      Environment           = var.environment
      DeploymentEnvironment = var.environment
      Repository            = "oficina-infra"
      OptionalComponent     = "ui-hosting"
    })
  }
}
