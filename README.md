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

Arquivos principais:

- [terraform/environments/lab/](terraform/environments/lab/)
- [terraform/modules/rds-postgres/](terraform/modules/rds-postgres/)
- [terraform/modules/eks/](terraform/modules/eks/)
- [terraform/modules/ecr/](terraform/modules/ecr/)
- [terraform/modules/api_gateway/](terraform/modules/api_gateway/)
- [k8s/overlays/lab/](k8s/overlays/lab/)
- [compose.local.yml](compose.local.yml)
- [scripts/local/bootstrap-local.sh](scripts/local/bootstrap-local.sh)
- [scripts/manual/bootstrap-service-databases.sh](scripts/manual/bootstrap-service-databases.sh)
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

Comando local equivalente:

```bash
TF_STATE_BUCKET=<bucket-state> scripts/actions/ci-deploy.sh
```
