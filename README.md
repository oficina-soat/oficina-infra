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

## Observabilidade New Relic

O New Relic OpenTelemetry Collector do ambiente `lab` é instalado via Helm no cluster `eks-lab`, usando license key fornecida por variável/secret de deploy e valores versionados em [k8s/components/new-relic-otel-collector/values.lab.yaml](k8s/components/new-relic-otel-collector/values.lab.yaml).

Documentação operacional: [New Relic OpenTelemetry Collector no EKS lab](docs/new-relic-otel-collector.md).

Arquivos principais:

- [terraform/environments/lab/](terraform/environments/lab/)
- [terraform/modules/rds-postgres/](terraform/modules/rds-postgres/)
- [terraform/modules/dynamodb_execution/](terraform/modules/dynamodb_execution/)
- [terraform/modules/domain_messaging/](terraform/modules/domain_messaging/)
- [terraform/modules/eks/](terraform/modules/eks/)
- [terraform/modules/ecr/](terraform/modules/ecr/)
- [terraform/modules/api_gateway/](terraform/modules/api_gateway/)
- [k8s/overlays/lab/](k8s/overlays/lab/)
- [k8s/components/new-relic-otel-collector/values.lab.yaml](k8s/components/new-relic-otel-collector/values.lab.yaml)
- [compose.local.yml](compose.local.yml)
- [scripts/local/bootstrap-local.sh](scripts/local/bootstrap-local.sh)
- [scripts/manual/bootstrap-service-databases.sh](scripts/manual/bootstrap-service-databases.sh)
- [scripts/manual/bootstrap-service-databases-k8s.sh](scripts/manual/bootstrap-service-databases-k8s.sh)
- [scripts/manual/install-new-relic-otel-collector.sh](scripts/manual/install-new-relic-otel-collector.sh)
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
Quando `TF_STATE_BUCKET` não for informado, o script deriva o bucket canônico a partir da conta AWS da execução, no formato `tf-shared-eks-lab-<aws-account-id>-us-east-1`.

Por padrão, [scripts/actions/ci-terraform.sh](scripts/actions/ci-terraform.sh) cria e configura esse bucket antes do `terraform init` quando ele ainda não existe, aplicando versionamento, criptografia SSE-S3, bloqueio de acesso público e ownership `BucketOwnerEnforced`. Para exigir um bucket pré-criado, defina `BOOTSTRAP_TF_STATE_BUCKET=false`.

Variáveis mínimas esperadas:

- `TF_STATE_BUCKET`, opcional quando o bucket usa o nome canônico derivado
- `BOOTSTRAP_TF_STATE_BUCKET=true`, para criar/configurar automaticamente o bucket S3 do backend antes do `terraform init`
- `AWS_REGION=us-east-1`
- `EKS_CLUSTER_NAME=eks-lab`
- `CREATE_EKS=true`, padrão do workflow para manter o lab alinhado ao deploy Kubernetes
- `EKS_CLUSTER_ROLE_ARN` e `EKS_NODE_ROLE_ARN`, quando `CREATE_EKS=true`; no VocLabs, [scripts/actions/ci-terraform.sh](scripts/actions/ci-terraform.sh) tenta descobrir automaticamente roles com `LabEksClusterRole` e `LabEksNodeRole` no nome quando essas variáveis não forem informadas
- `SKIP_FINAL_SNAPSHOT=true`, padrão do workflow para destruir o RDS de lab sem exigir `FINAL_SNAPSHOT_IDENTIFIER`
- `DELETE_AUTOMATED_BACKUPS=true`, padrão do workflow para remover backups automáticos do RDS no destroy do lab
- `VPC_ID` e `SUBNET_IDS`, quando a rede não for criada pelo Terraform
- `BOOTSTRAP_SERVICE_DATABASES_MODE=k8s`, padrão do workflow para executar o bootstrap PostgreSQL por Job efêmero dentro do EKS; use `local` apenas quando o runner tiver rota direta para o RDS
- `DB_BOOTSTRAP_NAMESPACE`, `DB_BOOTSTRAP_IMAGE` e `DB_BOOTSTRAP_TIMEOUT`, opcionais para customizar o Job efêmero de bootstrap dos databases
- `CREATE_EXECUTION_DYNAMODB=false`, quando as tabelas DynamoDB não devem ser criadas pelo workflow
- `CREATE_DOMAIN_MESSAGING=false`, quando SNS/SQS da Fase 4 não devem ser criados pelo workflow
- `INSTALL_NEW_RELIC_OTEL_COLLECTOR=true`, `NEW_RELIC_LICENSE_KEY` e `NEW_RELIC_OTLP_ENDPOINT`, quando o New Relic OpenTelemetry Collector deve ser instalado no cluster

Comando local equivalente:

```bash
TF_STATE_BUCKET=<bucket-state> scripts/actions/ci-deploy.sh
```

Quando as credenciais AWS locais apontam para a conta correta e o bucket usa o nome canônico, o comando também pode ser executado sem `TF_STATE_BUCKET`.
