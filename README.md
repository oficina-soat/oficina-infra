# oficina-infra

Repositório canônico de infraestrutura compartilhada da suíte da oficina mecânica.

Este repositório concentra os artefatos executáveis que antes ficavam distribuídos entre `oficina-infra-db` e `oficina-infra-k8s`, preservando as decisões de governança do `oficina-platform`.

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

Arquivos principais:

- [terraform/environments/lab/](terraform/environments/lab/)
- [terraform/modules/rds-postgres/](terraform/modules/rds-postgres/)
- [scripts/manual/bootstrap-service-databases.sh](scripts/manual/bootstrap-service-databases.sh)

## Validação local

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/lab init -backend=false
terraform -chdir=terraform/environments/lab validate
find scripts -type f -name '*.sh' -print0 | xargs -0 bash -n
```
