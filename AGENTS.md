# AGENTS.md

## Contexto

Este repositório é o destino canônico da infraestrutura executável da suíte da oficina mecânica. Ele concentra Terraform, scripts operacionais, manifests Kubernetes, ambiente local integrado e workflows de deploy/destroy do ambiente `lab`.

O repositório normativo da plataforma é [../oficina-platform](../oficina-platform/). Antes de alterar nomes canônicos, contratos, secrets, variáveis, rotas públicas, padrões de deploy ou decisões arquiteturais, consulte os documentos relacionados no `oficina-platform`, especialmente:

- [Escopo do Repositório Unificado de Infraestrutura](../oficina-platform/docs/infrastructure-repository-scope.md)
- [Plano de migração para o repositório unificado de infraestrutura](../oficina-platform/docs/infrastructure-migration-plan.md)
- [Nomes de runtime, secrets e infraestrutura](../oficina-platform/docs/infra-runtime-naming.md)
- [Estratégia de entrega dos manifestos Kubernetes](../oficina-platform/docs/kubernetes-manifest-strategy.md)
- [Ferramentas de validação local](../oficina-platform/docs/validation-tooling.md)

## Diretrizes

- Preserve AWS, região `us-east-1`, ambiente `lab` e infraestrutura compartilhada `eks-lab`, salvo decisão normativa explícita no `oficina-platform`.
- Preserve este repositório como fonte canônica de Terraform, Kubernetes executável, scripts operacionais e workflows de infraestrutura.
- Não mova código de domínio de microsserviços para este repositório.
- Não altere nomes de secrets, variáveis, buckets, databases, tabelas DynamoDB, tópicos, filas, Deployments, Services ou rotas sem procurar o mesmo nome nos documentos relacionados e normalizar o escopo afetado.
- Quando adaptar artefatos históricos de `../oficina-infra-db` ou `../oficina-infra-k8s`, use esses repositórios apenas como fonte de consulta ou cópia controlada.
- Ao mexer em manifests dos microsserviços, preserve os nomes canônicos `oficina-os-service`, `oficina-billing-service` e `oficina-execution-service`.
- Ao mexer em `scripts/manual/apply-microservices.sh`, confirme compatibilidade com os workflows dos três microsserviços.

## Validação

Antes de encerrar alterações relevantes, execute validação proporcional ao impacto.

Validação geral do repositório:

```bash
bash scripts/actions/validate.sh
```

Terraform:

```bash
terraform fmt -check -recursive terraform
TERRAFORM_ACTION=validate scripts/actions/ci-terraform.sh
tflint --chdir terraform/environments/lab
```

Scripts shell:

```bash
find scripts -type f -name '*.sh' -print0 | xargs -0 bash -n
find scripts -type f -name '*.sh' -print0 | xargs -0 shellcheck
shfmt -d scripts
```

YAML, Kubernetes e Kustomize:

```bash
find . -path ./.git -prune -o \( -name '*.yaml' -o -name '*.yml' \) -print0 | xargs -0 yq e '.' >/dev/null
kubectl kustomize k8s/base/microservices >/tmp/oficina-infra-microservices-rendered.yaml
kubectl kustomize k8s/overlays/lab >/tmp/oficina-infra-lab-rendered.yaml
kubectl kustomize k8s/base/microservices | kubeconform -strict -summary
kubectl kustomize k8s/overlays/lab | kubeconform -strict -summary
```

GitHub Actions:

```bash
actionlint
```

Use `gh` autenticado para investigar falhas reais de CI/CD antes de inferir causa por leitura estática:

```bash
gh auth status
gh run view <run-id> --log
```

Se uma ferramenta complementar não estiver disponível, registre a limitação na resposta final e execute a melhor validação equivalente disponível.

## Commits

Ao concluir alteração relevante neste repositório, crie commit local em português seguindo Conventional Commits, por exemplo:

```bash
git commit -m "ci: ajusta deploy dos microsserviços"
```

Não faça `git push`, salvo se o usuário pedir explicitamente.
