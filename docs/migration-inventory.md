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
| `oficina-infra-k8s/terraform/modules/terraform_shared_data_bucket` | [terraform/modules/terraform_shared_data_bucket/](../terraform/modules/terraform_shared_data_bucket/) | Mantido para bootstrap opcional do bucket compartilhado. |
| `oficina-infra-k8s/k8s/components/mailhog` | [k8s/components/mailhog/](../k8s/components/mailhog/) | Mantido como componente compartilhado de laboratório para notificações. |
| Workflows e scripts dos repositórios legados | [.github/workflows/](../.github/workflows/) e [scripts/actions/](../scripts/actions/) | Recriados de forma enxuta para state unificado `oficina/lab/infra/terraform.tfstate`, sem disparos para repositórios legados. |

## Criados para a Fase 4

| Destino | Descrição |
|---|---|
| [terraform/modules/dynamodb_execution/](../terraform/modules/dynamodb_execution/) | Provisiona as tabelas DynamoDB canônicas do `oficina-execution-service`, com streams, TTL e política IAM de runtime. |
| [terraform/modules/domain_messaging/](../terraform/modules/domain_messaging/) | Provisiona tópicos SNS, filas SQS, DLQs, assinaturas e políticas IAM de produtores/consumidores conforme o contrato de mensageria da plataforma. |

## Mantidos fora do `oficina-infra`

| Origem | Motivo |
|---|---|
| `oficina-infra-db/sql/` | Migrations e seeds de domínio pertencem aos repositórios dos microsserviços ou ficam como referência histórica. |
| `oficina-infra-k8s/k8s/base/oficina-app` | Deployment do backend monolítico legado, substituído por manifests próprios dos microsserviços. |
| `oficina-infra-k8s/k8s/overlays/lab-app` | Overlay específico do `oficina-app`. |
| `oficina-infra-k8s/k8s/components/aws-observability` | Manifests AWS-native legados de observabilidade foram substituídos pelo New Relic OpenTelemetry Collector canônico. |
| `oficina-infra-k8s/terraform/modules/internal_nodeport_nlb` | Módulo especulativo de NLB interno por NodePort não está conectado ao root module do `lab` e foi removido do destino canônico. |
| `terraform.tfstate`, `terraform.tfvars`, arquivos `.idea/` e `.tmp/` | Estado local, configuração local ou artefatos temporários não versionáveis. |

## Pendências

- Definir rotas reais do API Gateway quando os endpoints dos microsserviços estiverem publicados.
- Importar/adotar o RDS existente no state do `oficina-infra` quando as credenciais AWS do laboratório estiverem renovadas.
