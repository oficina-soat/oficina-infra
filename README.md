# oficina-infra

Repositório canônico de infraestrutura compartilhada da suíte da oficina mecânica.

Este repositório concentra os artefatos executáveis que antes ficavam distribuídos entre `oficina-infra-db` e `oficina-infra-k8s`, preservando as decisões de governança do `oficina-platform`.

Inventário de cópia e adaptação: [Inventário de migração dos repositórios legados](docs/migration-inventory.md).

## Ambiente canônico

| Item | Valor |
|---|---|
| Região AWS | `us-east-1` |
| Ambiente | `lab` |
| Infraestrutura compartilhada | `eks-lab` |
| State Terraform | `oficina/lab/infra/terraform.tfstate` |

## RDS PostgreSQL compartilhado

O primeiro artefato provisionável deste repositório é o RDS PostgreSQL compartilhado da Fase 4:

```text
oficina-postgres-lab
+-- oficina_os / oficina_os_user
+-- oficina_billing / oficina_billing_user
```

Documentação operacional: [RDS PostgreSQL compartilhado](docs/rds-postgresql.md).

## DynamoDB e mensageria

O Terraform do ambiente `lab` provisiona as tabelas DynamoDB do `oficina-execution-service` e a mensageria SNS/SQS da Fase 4:

- tabelas `oficina-execution-lab-catalogo`, `oficina-execution-lab-estoque`, `oficina-execution-lab-execucoes`, `oficina-execution-lab-outbox` e `oficina-execution-lab-idempotencia`;
- tópicos SNS canônicos convertidos para nomes físicos com hífen, por exemplo `oficina.execution.execucao-finalizada` como `oficina-execution-execucao-finalizada`;
- filas SQS por consumidor, DLQs por tópico e assinaturas com `RawMessageDelivery=true`;
- políticas IAM gerenciadas separadas para publicação, consumo e acesso DynamoDB.

Documentação operacional: [DynamoDB e mensageria da Fase 4](docs/dynamodb-messaging.md).

## Ambiente local integrado

Para testes locais de dependências e APIs dos três microsserviços, use o Compose local:

```bash
docker compose -f compose.local.yml up -d postgres dynamodb localstack
scripts/local/bootstrap-local.sh
```

Documentação: [Ambiente local integrado](docs/local-integration.md).

## Kubernetes dos microsserviços

Este repositório é a fonte canônica dos manifests Kubernetes executáveis dos microsserviços da Fase 4. A estratégia de entrega está definida em [Estratégia de entrega dos manifestos Kubernetes](../oficina-platform/docs/kubernetes-manifest-strategy.md).

Os manifests devem ser materializados em `k8s/base/microservices/<nome-do-servico>/` e referenciados pelo overlay `k8s/overlays/lab/` quando os recursos dependentes do ambiente estiverem prontos.

## Observabilidade Datadog

O Datadog Agent do ambiente `lab` é instalado via Helm no cluster `eks-lab`, usando API key fornecida por variável/secret de deploy e valores versionados em [k8s/components/datadog-agent/values.lab.yaml](k8s/components/datadog-agent/values.lab.yaml).

Documentação operacional: [Datadog Agent no EKS lab](docs/datadog-agent.md).

Arquivos principais:

- [terraform/environments/lab/](terraform/environments/lab/)
- [terraform/modules/rds-postgres/](terraform/modules/rds-postgres/)
- [terraform/modules/dynamodb_execution/](terraform/modules/dynamodb_execution/)
- [terraform/modules/domain_messaging/](terraform/modules/domain_messaging/)
- [terraform/modules/eks/](terraform/modules/eks/)
- [terraform/modules/ecr/](terraform/modules/ecr/)
- [terraform/modules/api_gateway/](terraform/modules/api_gateway/)
- [k8s/overlays/lab/](k8s/overlays/lab/)
- [k8s/components/datadog-agent/values.lab.yaml](k8s/components/datadog-agent/values.lab.yaml)
- [compose.local.yml](compose.local.yml)
- [scripts/local/bootstrap-local.sh](scripts/local/bootstrap-local.sh)
- [scripts/manual/bootstrap-service-databases.sh](scripts/manual/bootstrap-service-databases.sh)
- [scripts/manual/install-datadog-agent.sh](scripts/manual/install-datadog-agent.sh)
- [scripts/actions/ci-deploy.sh](scripts/actions/ci-deploy.sh)

## Validação local

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/lab init -backend=false
terraform -chdir=terraform/environments/lab validate
find scripts -type f -name '*.sh' -print0 | xargs -0 bash -n
```

## Deploy

O deploy automatizado usa o GitHub Environment `lab` e o state remoto `oficina/lab/infra/terraform.tfstate`.

Variáveis mínimas esperadas:

- `TF_STATE_BUCKET`
- `AWS_REGION=us-east-1`
- `EKS_CLUSTER_NAME=eks-lab`
- `EKS_CLUSTER_ROLE_ARN` e `EKS_NODE_ROLE_ARN`, quando `CREATE_EKS=true`
- `VPC_ID` e `SUBNET_IDS`, quando a rede não for criada pelo Terraform
- `CREATE_EXECUTION_DYNAMODB=false`, quando as tabelas DynamoDB não devem ser criadas pelo workflow
- `CREATE_DOMAIN_MESSAGING=false`, quando SNS/SQS da Fase 4 não devem ser criados pelo workflow
- `INSTALL_DATADOG_AGENT=true`, `DATADOG_API_KEY` e `DATADOG_SITE`, quando o Agent Datadog deve ser instalado no cluster

Comando local equivalente:

```bash
TF_STATE_BUCKET=<bucket-state> scripts/actions/ci-deploy.sh
```
