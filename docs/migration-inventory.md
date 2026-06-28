# Inventário de migração dos repositórios legados

Este inventário registra a cópia controlada de artefatos de `oficina-infra-db` e `oficina-infra-k8s` para o repositório canônico `oficina-infra`.

## Copiados e adaptados

| Origem | Destino | Adaptação |
|---|---|---|
| `oficina-infra-db/terraform/modules/rds-postgres` | [terraform/modules/rds-postgres/](../terraform/modules/rds-postgres/) | Baseline simplificado para a instância `oficina-postgres-lab`, sem database de aplicação legado. |
| `oficina-infra-k8s/terraform/modules/network` | [terraform/modules/network/](../terraform/modules/network/) | Mantido como rede mínima do ambiente `lab`, usando `eks-lab`. |
| `oficina-infra-k8s/terraform/modules/eks` | [terraform/modules/eks/](../terraform/modules/eks/) | Removida dependência de conta fixa; roles são informadas por variável. |
| `oficina-infra-k8s/terraform/modules/ecr` | [terraform/modules/ecr/](../terraform/modules/ecr/) | Usado para repositórios dos microsserviços `oficina-os-service`, `oficina-billing-service` e `oficina-execution-service`. |
| `oficina-infra-k8s/terraform/modules/api_gateway` | [terraform/modules/api_gateway/](../terraform/modules/api_gateway/) | Mantido como HTTP API genérico, sem rotas legadas do `oficina-app`. |
| `oficina-infra-k8s/terraform/modules/internal_nodeport_nlb` | [terraform/modules/internal_nodeport_nlb/](../terraform/modules/internal_nodeport_nlb/) | Mantido para futuras exposições privadas por NodePort quando necessário. |
| `oficina-infra-k8s/terraform/modules/terraform_shared_data_bucket` | [terraform/modules/terraform_shared_data_bucket/](../terraform/modules/terraform_shared_data_bucket/) | Mantido para bootstrap opcional do bucket compartilhado. |
| `oficina-infra-k8s/k8s/components/aws-observability` | [k8s/components/aws-observability/](../k8s/components/aws-observability/) | Normalizado para serviços `oficina-*-service`, sem scrape estático do `oficina-app`. |
| `oficina-infra-k8s/k8s/components/mailhog` | [k8s/components/mailhog/](../k8s/components/mailhog/) | Mantido como componente compartilhado de laboratório para notificações. |
| Workflows e scripts dos repositórios legados | [.github/workflows/](../.github/workflows/) e [scripts/actions/](../scripts/actions/) | Recriados de forma enxuta para state unificado `oficina/lab/infra/terraform.tfstate`, sem disparos para repositórios legados. |

## Mantidos fora do `oficina-infra`

| Origem | Motivo |
|---|---|
| `oficina-infra-db/sql/` | Migrations e seeds de domínio pertencem aos repositórios dos microsserviços ou ficam como referência histórica. |
| `oficina-infra-k8s/k8s/base/oficina-app` | Deployment do backend monolítico legado, substituído por manifests próprios dos microsserviços. |
| `oficina-infra-k8s/k8s/overlays/lab-app` | Overlay específico do `oficina-app`. |
| `terraform.tfstate`, `terraform.tfvars`, arquivos `.idea/` e `.tmp/` | Estado local, configuração local ou artefatos temporários não versionáveis. |

## Pendências

- Adicionar DynamoDB do `oficina-execution-service`.
- Adicionar mensageria, filas, assinaturas e DLQs da Fase 4.
- Definir rotas reais do API Gateway quando os endpoints dos microsserviços estiverem publicados.
- Importar/adotar o RDS existente no state do `oficina-infra` quando as credenciais AWS do laboratório estiverem renovadas.
