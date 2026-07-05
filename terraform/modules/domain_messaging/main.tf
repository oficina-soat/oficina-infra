locals {
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Component = "domain-messaging"
  })

  routes = {
    for key, route in var.routes : key => merge(route, {
      topic_name = replace(route.topic, ".", "-")
      dlq_name   = replace("${route.topic}.dlq", ".", "-")
    })
  }

  consumer_bindings = {
    for binding in flatten([
      for route_key, route in local.routes : [
        for consumer in route.consumers : {
          key        = "${route_key}:${consumer}"
          route_key  = route_key
          event_type = route.event_type
          topic      = route.topic
          topic_name = route.topic_name
          producer   = route.producer
          consumer   = consumer
          queue_name = replace("${route.topic}.${consumer}", ".", "-")
        }
      ]
    ]) : binding.key => binding
  }

  producer_services = toset(distinct([
    for route in values(local.routes) : route.producer
  ]))

  consumer_services = toset(distinct(flatten([
    for route in values(local.routes) : route.consumers
  ])))

  producer_policy_services = {
    for service in local.producer_services : service => service
    if var.create_runtime_iam_policies
  }

  consumer_policy_services = {
    for service in local.consumer_services : service => service
    if var.create_runtime_iam_policies
  }
}

resource "aws_sns_topic" "this" {
  for_each = local.routes

  name              = each.value.topic_name
  kms_master_key_id = var.sns_kms_master_key_id

  tags = merge(local.common_tags, {
    Name         = each.value.topic_name
    LogicalTopic = each.value.topic
    EventType    = each.value.event_type
    Producer     = each.value.producer
  })
}

resource "aws_sqs_queue" "dlq" {
  for_each = local.routes

  name                      = each.value.dlq_name
  message_retention_seconds = var.dlq_message_retention_seconds
  sqs_managed_sse_enabled   = var.sqs_managed_sse_enabled

  tags = merge(local.common_tags, {
    Name         = each.value.dlq_name
    LogicalTopic = each.value.topic
    EventType    = each.value.event_type
    QueueType    = "dlq"
  })
}

resource "aws_sqs_queue" "consumer" {
  for_each = local.consumer_bindings

  name                       = each.value.queue_name
  visibility_timeout_seconds = var.queue_visibility_timeout_seconds
  message_retention_seconds  = var.queue_message_retention_seconds
  receive_wait_time_seconds  = var.queue_receive_wait_time_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.value.route_key].arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(local.common_tags, {
    Name         = each.value.queue_name
    LogicalTopic = each.value.topic
    EventType    = each.value.event_type
    Producer     = each.value.producer
    Consumer     = each.value.consumer
    QueueType    = "consumer"
  })
}

data "aws_iam_policy_document" "consumer_queue" {
  for_each = local.consumer_bindings

  statement {
    sid     = "AllowSnsPublish"
    actions = ["sqs:SendMessage"]
    resources = [
      aws_sqs_queue.consumer[each.key].arn,
    ]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.this[each.value.route_key].arn]
    }
  }
}

resource "aws_sqs_queue_policy" "consumer" {
  for_each = local.consumer_bindings

  queue_url = aws_sqs_queue.consumer[each.key].url
  policy    = data.aws_iam_policy_document.consumer_queue[each.key].json
}

resource "aws_sns_topic_subscription" "consumer" {
  for_each = local.consumer_bindings

  topic_arn            = aws_sns_topic.this[each.value.route_key].arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.consumer[each.key].arn
  raw_message_delivery = var.raw_message_delivery

  depends_on = [
    aws_sqs_queue_policy.consumer
  ]
}

data "aws_iam_policy_document" "producer" {
  for_each = local.producer_policy_services

  statement {
    sid     = "PublishDomainEvents"
    actions = ["sns:Publish"]
    resources = [
      for route_key, route in local.routes :
      aws_sns_topic.this[route_key].arn
      if route.producer == each.key
    ]
  }
}

resource "aws_iam_policy" "producer" {
  for_each = local.producer_policy_services

  name        = "${var.policy_name_prefix}-${each.key}-producer"
  description = "Permite ao ${each.key} publicar eventos de dominio nos topicos canonicos."
  policy      = data.aws_iam_policy_document.producer[each.key].json

  tags = merge(local.common_tags, {
    Service    = each.key
    PolicyType = "producer"
  })
}

data "aws_iam_policy_document" "consumer" {
  for_each = local.consumer_policy_services

  statement {
    sid = "ConsumeDomainEvents"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [
      for binding_key, binding in local.consumer_bindings :
      aws_sqs_queue.consumer[binding_key].arn
      if binding.consumer == each.key
    ]
  }
}

resource "aws_iam_policy" "consumer" {
  for_each = local.consumer_policy_services

  name        = "${var.policy_name_prefix}-${each.key}-consumer"
  description = "Permite ao ${each.key} consumir eventos de dominio das filas canonicas."
  policy      = data.aws_iam_policy_document.consumer[each.key].json

  tags = merge(local.common_tags, {
    Service    = each.key
    PolicyType = "consumer"
  })
}
