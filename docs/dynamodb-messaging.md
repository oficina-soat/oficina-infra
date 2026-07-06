# DynamoDB e mensageria da Fase 4

Este documento descreve a materialização executável, em Terraform, dos contratos definidos no `oficina-platform` para DynamoDB do `oficina-execution-service` e mensageria SNS/SQS da Fase 4.

Referências normativas:

- [Padrão DynamoDB do oficina-execution-service](../../oficina-platform/docs/dynamodb-execution-service.md)
- [Contrato de Tópicos de Mensageria](../../oficina-platform/contracts/Contrato%20de%20Tópicos%20de%20Mensageria.md)
- [Nomes de runtime, secrets e infraestrutura](../../oficina-platform/docs/infra-runtime-naming.md)
- [Plano de migração para o repositório unificado de infraestrutura](../../oficina-platform/docs/infrastructure-migration-plan.md)

## Terraform

O ambiente `lab` referencia dois módulos:

```text
terraform/modules/dynamodb_execution/
terraform/modules/domain_messaging/
```

Flags principais:

| Variável | Default | Uso |
|---|---:|---|
| `create_execution_dynamodb` | `true` | Cria as tabelas DynamoDB do `oficina-execution-service`. |
| `execution_dynamodb_table_prefix` | `null` | Quando nulo, deriva `oficina-execution-<environment>`. No `lab`, o valor materializado é `oficina-execution-lab`. |
| `create_domain_messaging` | `true` | Cria tópicos SNS, filas SQS, DLQs, assinaturas e políticas IAM de mensageria. |
| `create_runtime_iam_policies` | `true` | Cria políticas IAM gerenciadas para anexação posterior às roles dos workloads. |
| `domain_messaging_raw_message_delivery` | `true` | Entrega no SQS o envelope de domínio publicado no SNS, sem envelope adicional do SNS. |

## Tabelas DynamoDB

| Nome físico | Stream | TTL |
|---|---|---|
| `oficina-execution-lab-catalogo` | Desabilitado | Desabilitado |
| `oficina-execution-lab-estoque` | `NEW_AND_OLD_IMAGES` | Desabilitado |
| `oficina-execution-lab-execucoes` | `NEW_AND_OLD_IMAGES` | Desabilitado |
| `oficina-execution-lab-outbox` | `NEW_AND_OLD_IMAGES` | `expiresAt` |
| `oficina-execution-lab-idempotencia` | Desabilitado | `expiresAt` |

As tabelas usam `PAY_PER_REQUEST` e criptografia server-side. O módulo cria a política IAM `oficina-execution-lab-runtime-dynamodb`, que deve ser anexada somente ao runtime do `oficina-execution-service`.

## Mensageria SNS/SQS

O root module usa a tabela canônica `evento -> tópico -> produtor -> consumidores` do contrato da plataforma. O nome lógico do tópico permanece como metadado, mas o nome físico troca `.` por `-`, por exemplo:

```text
oficina.execution.execucao-finalizada -> oficina-execution-execucao-finalizada
```

Para cada evento:

- é criado um tópico SNS;
- é criada uma DLQ com o padrão físico derivado de `<topico>.dlq`;
- é criada uma fila SQS por consumidor com o padrão físico derivado de `<topico>.<consumidor>`;
- a fila consumidora recebe redrive para a DLQ após 5 recebimentos;
- a assinatura SNS -> SQS usa `RawMessageDelivery=true`.

As políticas IAM de mensageria são separadas por serviço:

- `oficina-lab-domain-messaging-<servico>-producer`, com `sns:Publish` apenas nos tópicos produzidos pelo serviço;
- `oficina-lab-domain-messaging-<servico>-consumer`, com ações mínimas de consumo apenas nas filas do serviço.

Essas políticas são criadas para anexação posterior às roles dos workloads Kubernetes. O módulo não cria roles de serviço nem altera service accounts.

Por compatibilidade com o VocLabs, as IAM managed policies são criadas sem tags. A role do laboratório permite criar policies, mas pode negar `iam:TagPolicy`; os demais recursos de SNS, SQS e DynamoDB permanecem tagueados pelo provider padrão.

## Outputs

Use os outputs do ambiente `lab` para integrar pipelines, manifests e documentação operacional:

```bash
terraform -chdir=terraform/environments/lab output execution_dynamodb_table_names
terraform -chdir=terraform/environments/lab output domain_messaging_topic_names_by_event
terraform -chdir=terraform/environments/lab output domain_messaging_consumer_queue_urls
terraform -chdir=terraform/environments/lab output domain_messaging_producer_policy_arns
terraform -chdir=terraform/environments/lab output domain_messaging_consumer_policy_arns
```

## Validação local

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/lab init -backend=false
terraform -chdir=terraform/environments/lab validate
```
