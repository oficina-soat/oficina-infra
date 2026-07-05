# RDS PostgreSQL compartilhado

Este documento registra o provisionamento do RDS PostgreSQL compartilhado do ambiente `lab`.

O padrão implementado segue o contrato canônico do `oficina-platform`:

- instância RDS: `oficina-postgres-lab`;
- região: `us-east-1`;
- ambiente: `lab`;
- infraestrutura compartilhada: `eks-lab`;
- database do `oficina-os-service`: `oficina_os`;
- owner do `oficina-os-service`: `oficina_os_user`;
- secret AWS do `oficina-os-service`: `oficina/lab/database/oficina-os-service`;
- database do `oficina-billing-service`: `oficina_billing`;
- owner do `oficina-billing-service`: `oficina_billing_user`;
- secret AWS do `oficina-billing-service`: `oficina/lab/database/oficina-billing-service`.

## Artefatos

| Artefato | Função |
|---|---|
| [terraform/modules/rds-postgres/](../terraform/modules/rds-postgres/) | Módulo Terraform da instância RDS, subnet group, security group, parameter group e logs. |
| [terraform/environments/lab/](../terraform/environments/lab/) | Ambiente canônico `lab` com state remoto `oficina/lab/infra/terraform.tfstate`. |
| [scripts/manual/bootstrap-service-databases.sh](../scripts/manual/bootstrap-service-databases.sh) | Bootstrap idempotente dos databases, owners, permissões e secrets por serviço. |

## Isolamento

O Terraform provisiona a instância compartilhada. O script de bootstrap cria os databases e usuários independentes depois que o RDS está disponível.

Não há migration de domínio neste repositório. As migrations de `oficina_os` e `oficina_billing` pertencem aos repositórios `oficina-os-service` e `oficina-billing-service`.

O bootstrap aplica:

```sql
REVOKE CONNECT ON DATABASE oficina_os FROM PUBLIC;
REVOKE CONNECT ON DATABASE oficina_billing FROM PUBLIC;
GRANT CONNECT ON DATABASE oficina_os TO oficina_os_user;
GRANT CONNECT ON DATABASE oficina_billing TO oficina_billing_user;
```

Depois, em cada database, o schema `public` fica sob ownership do usuário do próprio serviço.

## Execução para RDS novo

Use este fluxo apenas quando a instância `oficina-postgres-lab` ainda não existir no ambiente AWS:

```bash
cp terraform/environments/lab/terraform.tfvars.example terraform/environments/lab/terraform.tfvars
terraform -chdir=terraform/environments/lab init
terraform -chdir=terraform/environments/lab plan
terraform -chdir=terraform/environments/lab apply
```

Após o apply, execute o bootstrap:

```bash
scripts/manual/bootstrap-service-databases.sh
```

O script lê `db_endpoint`, `db_port`, `db_username` e `db_master_user_secret_arn` dos outputs Terraform quando as variáveis equivalentes não forem informadas.

O deploy automatizado executa o mesmo bootstrap por [scripts/actions/ci-deploy.sh](../scripts/actions/ci-deploy.sh), desde que `BOOTSTRAP_SERVICE_DATABASES=true`.

## Adoção do RDS existente

Quando o RDS `oficina-postgres-lab` já existir no state legado de `oficina-infra-db`, não execute um `apply` direto com state vazio. Primeiro importe os recursos existentes para o state do `oficina-infra`:

```bash
TF_STATE_BUCKET=<bucket-state> TERRAFORM_ACTION=init scripts/actions/ci-terraform.sh
scripts/manual/import-existing-rds.sh
terraform -chdir=terraform/environments/lab plan
```

Se o plano não recriar a instância, aplique e execute o bootstrap:

```bash
terraform -chdir=terraform/environments/lab apply
scripts/manual/bootstrap-service-databases.sh
```

O script [scripts/manual/import-existing-rds.sh](../scripts/manual/import-existing-rds.sh) usa os identificadores atuais do ambiente `lab` extraídos do state legado e pode receber overrides por variável de ambiente.
