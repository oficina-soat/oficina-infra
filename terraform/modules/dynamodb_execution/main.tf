locals {
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Component = "dynamodb-execution"
    Service   = "oficina-execution-service"
  })

  table_definitions = {
    catalogo = {
      name             = "${var.table_prefix}-catalogo"
      stream_enabled   = false
      stream_view_type = null
      ttl_enabled      = false
      ttl_attribute    = null
      attributes = [
        { name = "PK", type = "S" },
        { name = "SK", type = "S" },
        { name = "entityType", type = "S" },
        { name = "nomeNormalizado", type = "S" },
        { name = "codigo", type = "S" },
      ]
      global_secondary_indexes = {
        GSI1 = {
          hash_key        = "entityType"
          range_key       = "nomeNormalizado"
          projection_type = "ALL"
        }
        GSI2 = {
          hash_key        = "codigo"
          range_key       = "entityType"
          projection_type = "ALL"
        }
      }
    }

    estoque = {
      name             = "${var.table_prefix}-estoque"
      stream_enabled   = true
      stream_view_type = "NEW_AND_OLD_IMAGES"
      ttl_enabled      = false
      ttl_attribute    = null
      attributes = [
        { name = "PK", type = "S" },
        { name = "SK", type = "S" },
        { name = "ordemServicoId", type = "S" },
        { name = "createdAt", type = "S" },
        { name = "movimentoId", type = "S" },
        { name = "entityType", type = "S" },
      ]
      global_secondary_indexes = {
        GSI1 = {
          hash_key        = "ordemServicoId"
          range_key       = "createdAt"
          projection_type = "ALL"
        }
        GSI2 = {
          hash_key        = "movimentoId"
          range_key       = "entityType"
          projection_type = "ALL"
        }
      }
    }

    execucoes = {
      name             = "${var.table_prefix}-execucoes"
      stream_enabled   = true
      stream_view_type = "NEW_AND_OLD_IMAGES"
      ttl_enabled      = false
      ttl_attribute    = null
      attributes = [
        { name = "PK", type = "S" },
        { name = "SK", type = "S" },
        { name = "ordemServicoId", type = "S" },
        { name = "entityType", type = "S" },
        { name = "status", type = "S" },
        { name = "updatedAt", type = "S" },
        { name = "filaStatus", type = "S" },
        { name = "prioridadeCriadoEm", type = "S" },
      ]
      global_secondary_indexes = {
        GSI1 = {
          hash_key        = "ordemServicoId"
          range_key       = "entityType"
          projection_type = "ALL"
        }
        GSI2 = {
          hash_key        = "status"
          range_key       = "updatedAt"
          projection_type = "ALL"
        }
        GSI3 = {
          hash_key        = "filaStatus"
          range_key       = "prioridadeCriadoEm"
          projection_type = "ALL"
        }
      }
    }

    outbox = {
      name             = "${var.table_prefix}-outbox"
      stream_enabled   = true
      stream_view_type = "NEW_AND_OLD_IMAGES"
      ttl_enabled      = true
      ttl_attribute    = "expiresAt"
      attributes = [
        { name = "PK", type = "S" },
        { name = "SK", type = "S" },
        { name = "status", type = "S" },
        { name = "nextAttemptAt", type = "S" },
        { name = "aggregateId", type = "S" },
        { name = "createdAt", type = "S" },
      ]
      global_secondary_indexes = {
        GSI1 = {
          hash_key        = "status"
          range_key       = "nextAttemptAt"
          projection_type = "ALL"
        }
        GSI2 = {
          hash_key        = "aggregateId"
          range_key       = "createdAt"
          projection_type = "ALL"
        }
      }
    }

    idempotencia = {
      name                     = "${var.table_prefix}-idempotencia"
      stream_enabled           = false
      stream_view_type         = null
      ttl_enabled              = true
      ttl_attribute            = "expiresAt"
      attributes               = [{ name = "PK", type = "S" }, { name = "SK", type = "S" }]
      global_secondary_indexes = {}
    }
  }
}

resource "aws_dynamodb_table" "this" {
  for_each = local.table_definitions

  name                        = each.value.name
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "PK"
  range_key                   = "SK"
  deletion_protection_enabled = var.deletion_protection_enabled
  stream_enabled              = each.value.stream_enabled
  stream_view_type            = each.value.stream_enabled ? each.value.stream_view_type : null

  dynamic "attribute" {
    for_each = each.value.attributes

    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = each.value.global_secondary_indexes

    content {
      name            = global_secondary_index.key
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type
    }
  }

  dynamic "ttl" {
    for_each = each.value.ttl_enabled ? [each.value.ttl_attribute] : []

    content {
      attribute_name = ttl.value
      enabled        = true
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(local.common_tags, {
    Name         = each.value.name
    LogicalTable = each.key
  })
}

data "aws_iam_policy_document" "runtime_access" {
  statement {
    sid = "DynamoDBTables"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:ConditionCheckItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:TransactGetItems",
      "dynamodb:TransactWriteItems",
      "dynamodb:UpdateItem",
    ]
    resources = concat(
      [for table in aws_dynamodb_table.this : table.arn],
      [for table in aws_dynamodb_table.this : "${table.arn}/index/*"],
    )
  }

  statement {
    sid = "DynamoDBStreams"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:ListStreams",
    ]
    resources = compact([
      for key, table in aws_dynamodb_table.this :
      local.table_definitions[key].stream_enabled ? table.stream_arn : null
    ])
  }
}

locals {
  runtime_policy_description = "Acesso runtime do oficina-execution-service as tabelas DynamoDB da Fase 4."
  runtime_policy_hash = substr(sha256(jsonencode({
    description = local.runtime_policy_description
    policy      = jsondecode(data.aws_iam_policy_document.runtime_access.json)
  })), 0, 12)
}

resource "aws_iam_policy" "runtime_access" {
  count    = var.create_runtime_iam_policy ? 1 : 0
  provider = aws.untagged

  name        = "${var.table_prefix}-runtime-dynamodb-${local.runtime_policy_hash}"
  description = local.runtime_policy_description
  policy      = data.aws_iam_policy_document.runtime_access.json

  lifecycle {
    create_before_destroy = true
  }
}
