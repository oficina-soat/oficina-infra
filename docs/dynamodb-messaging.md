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
| `attach_auth_sync_lambda_consumer_policy` | `false` | Anexa opcionalmente a policy SQS do consumidor serverless à role da `oficina-auth-sync-lambda`; permanece desabilitado no VocLabs. |
| `auth_sync_lambda_role_name` | `LabRole` | Role de execução compartilhada com o deploy da Lambda no ambiente de laboratório. |

## Tabelas DynamoDB

| Nome físico | Stream | TTL |
|---|---|---|
| `oficina-execution-lab-catalogo` | Desabilitado | Desabilitado |
| `oficina-execution-lab-estoque` | `NEW_AND_OLD_IMAGES` | Desabilitado |
| `oficina-execution-lab-execucoes` | `NEW_AND_OLD_IMAGES` | Desabilitado |
| `oficina-execution-lab-outbox` | `NEW_AND_OLD_IMAGES` | `expiresAt` |
| `oficina-execution-lab-idempotencia` | Desabilitado | `expiresAt` |

As tabelas usam `PAY_PER_REQUEST` e criptografia server-side. O módulo cria a política IAM `oficina-execution-lab-runtime-dynamodb-<hash-12>`, que deve ser anexada somente ao runtime do `oficina-execution-service`.

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

- `oficina-lab-domain-messaging-<servico>-producer-<hash-12>`, com `sns:GetTopicAttributes` e `sns:Publish` apenas nos tópicos produzidos pelo serviço;
- `oficina-lab-domain-messaging-<servico>-consumer-<hash-12>`, com ações mínimas de consumo apenas nas filas do serviço.

`sns:GetTopicAttributes` permite que cada microsserviço valide, durante a inicialização em runtime protegido, que todos os seus tópicos existem e estão acessíveis sem publicar eventos sintéticos. A política consumidora já inclui `sqs:GetQueueUrl`, usado da mesma forma para validar as filas canônicas antes de iniciar o worker.

Os eventos `usuarioAdicionado`, `usuarioAtualizado` e `usuarioExcluido` criam três tópicos, três filas do consumidor `oficina-auth-sync-lambda` e três DLQs. As filas físicas são:

```text
oficina-os-usuario-adicionado-oficina-auth-sync-lambda
oficina-os-usuario-atualizado-oficina-auth-sync-lambda
oficina-os-usuario-excluido-oficina-auth-sync-lambda
```

O Terraform produz a policy consumidora content-addressed e pode anexá-la à role informada por `auth_sync_lambda_role_name` quando `attach_auth_sync_lambda_consumer_policy=true`. No VocLabs, o attachment permanece desabilitado porque a identidade de deploy recebe `implicitDeny` para `iam:AttachRolePolicy`, enquanto a `LabRole` preexistente já permite as ações SQS necessárias em `us-east-1`. O Terraform também controla o ciclo de vida da função e dos três event source mappings, inicialmente desabilitados; o workflow do `oficina-auth-lambda` atualiza o pacote nativo e só então habilita o consumo.

Os pods dos microsserviços também precisam de SNS, SQS e DynamoDB. Como as ServiceAccounts do laboratório não possuem IRSA ou EKS Pod Identity e o `voclabs` não pode alterar a `LabEksNodeRole`, [o script de Terraform](../scripts/actions/ci-terraform.sh) usa a `LabRole` como `EKS_NODE_ROLE_ARN` quando detecta uma sessão `voclabs` sem override explícito. O managed node group usa `create_before_destroy` para trocar a role sem remover o node antigo antes de o sucessor ficar pronto. Essa exceção é restrita ao laboratório; em contas com governança IAM completa, as policies disponíveis nos outputs devem ser associadas por workload com menor privilégio.

Por compatibilidade com o VocLabs, as IAM managed policies são criadas sem tags e usam um sufixo determinístico com os 12 primeiros caracteres do SHA-256 da descrição e do documento da policy. A criação inicial é permitida, mas a role do laboratório pode negar `iam:TagPolicy` e `iam:CreatePolicyVersion`. Quando o conteúdo muda, o Terraform cria a policy sucessora antes de remover a anterior, evitando atualização por versão.

O ARN físico muda junto com o conteúdo. Anexações futuras às roles dos workloads devem ser gerenciadas pelo Terraform e consumir sempre `execution_dynamodb_runtime_policy_arn`, `domain_messaging_producer_policy_arns` e `domain_messaging_consumer_policy_arns`; não é permitido fixar em código um ARN com hash.

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
