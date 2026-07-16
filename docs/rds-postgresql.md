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
- database das Lambdas de autenticação: `oficina_auth`;
- owner das Lambdas de autenticação: `oficina_auth_user`;
- secret AWS das Lambdas de autenticação: `oficina/lab/database/oficina-auth-lambda`.

## Artefatos

| Artefato | Função |
|---|---|
| [terraform/modules/rds-postgres/](../terraform/modules/rds-postgres/) | Módulo Terraform da instância RDS, subnet group, security group, parameter group e logs. |
| [terraform/environments/lab/](../terraform/environments/lab/) | Ambiente canônico `lab` com state remoto `oficina/lab/infra/terraform.tfstate`. |
| [scripts/manual/bootstrap-service-databases.sh](../scripts/manual/bootstrap-service-databases.sh) | Bootstrap idempotente dos databases, owners, permissões e secrets por serviço quando o executor tem rota direta para o RDS. |
| [scripts/manual/bootstrap-service-databases-k8s.sh](../scripts/manual/bootstrap-service-databases-k8s.sh) | Bootstrap idempotente por Job efêmero no EKS, usado pelo deploy automatizado para acessar o RDS privado dentro da VPC. |

## Isolamento

O Terraform provisiona a instância compartilhada. O script de bootstrap cria os databases e usuários independentes depois que o RDS está disponível.

Não há migration de domínio neste repositório. As migrations de `oficina_os` e `oficina_billing` pertencem aos repositórios `oficina-os-service` e `oficina-billing-service`.

O bootstrap aplica:

```sql
REVOKE CONNECT ON DATABASE oficina_os FROM PUBLIC;
REVOKE CONNECT ON DATABASE oficina_billing FROM PUBLIC;
REVOKE CONNECT ON DATABASE oficina_auth FROM PUBLIC;
GRANT CONNECT ON DATABASE oficina_os TO oficina_os_user;
GRANT CONNECT ON DATABASE oficina_billing TO oficina_billing_user;
GRANT CONNECT ON DATABASE oficina_auth TO oficina_auth_user;
```

Depois, em cada database, o schema `public` fica sob ownership do usuário do próprio serviço.

## Execução para RDS novo

Use este fluxo apenas quando a instância `oficina-postgres-lab` ainda não existir no ambiente AWS:

```bash
cp terraform/environments/lab/terraform.tfvars.example terraform/environments/lab/terraform.tfvars
TERRAFORM_ACTION=init scripts/actions/ci-terraform.sh
TERRAFORM_ACTION=plan scripts/actions/ci-terraform.sh
TERRAFORM_ACTION=apply scripts/actions/ci-terraform.sh
```

Após o apply, execute o bootstrap:

```bash
scripts/manual/bootstrap-service-databases.sh
```

O script lê `db_endpoint`, `db_port`, `db_username` e `db_master_user_secret_arn` dos outputs Terraform quando as variáveis equivalentes não forem informadas.

O deploy automatizado executa o bootstrap por [scripts/actions/ci-deploy.sh](../scripts/actions/ci-deploy.sh), desde que `BOOTSTRAP_SERVICE_DATABASES=true`. O padrão é `BOOTSTRAP_SERVICE_DATABASES_MODE=k8s`, que cria um Job efêmero no EKS usando [scripts/manual/bootstrap-service-databases-k8s.sh](../scripts/manual/bootstrap-service-databases-k8s.sh). Esse fluxo mantém o RDS privado: o runner do GitHub lê o secret master e atualiza os secrets dos serviços no AWS Secrets Manager, enquanto apenas a conexão `psql` roda dentro da VPC.

Use `BOOTSTRAP_SERVICE_DATABASES_MODE=local` somente em execução manual a partir de uma rede que tenha rota direta para o endpoint privado do RDS.

O bucket S3 do backend remoto é criado automaticamente por [scripts/actions/ci-terraform.sh](../scripts/actions/ci-terraform.sh) quando `BOOTSTRAP_TF_STATE_BUCKET=true`, que é o padrão do CI. Use `BOOTSTRAP_TF_STATE_BUCKET=false` apenas quando o bucket já for provisionado por outro fluxo e a execução deve falhar caso ele não exista.

No workflow de lab, `CREATE_EKS=true` é o padrão para que o security group do cluster seja autorizado automaticamente no RDS. O script [scripts/actions/ci-terraform.sh](../scripts/actions/ci-terraform.sh) também usa `RDS_DELETION_PROTECTION=false` e `SKIP_FINAL_SNAPSHOT=true` por padrão, evitando bloqueio de exclusão e exigência de `FINAL_SNAPSHOT_IDENTIFIER` nas execuções automatizadas do ambiente `lab`.

Para o destroy do lab, `DELETE_AUTOMATED_BACKUPS=true` também é o padrão. Esse valor remove os backups automáticos retidos pela AWS quando a instância RDS é destruída. Ele não remove snapshots manuais já existentes; snapshots manuais são artefatos independentes e precisam de limpeza operacional explícita quando não forem mais necessários.

Quando `TERRAFORM_ACTION=destroy`, [scripts/actions/ci-terraform.sh](../scripts/actions/ci-terraform.sh) força `deletion_protection=false`, `skip_final_snapshot=true` e `delete_automated_backups=true`. Antes do `terraform destroy`, o script consulta a instância `oficina-postgres-lab` e desabilita a proteção de exclusão via AWS CLI quando uma instância antiga ainda estiver protegida.

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
