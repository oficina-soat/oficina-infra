# Kubernetes

Estrutura Kubernetes do ambiente `lab`.

- [components/new-relic-otel-collector/values.lab.yaml](components/new-relic-otel-collector/values.lab.yaml) define os valores Helm do New Relic OpenTelemetry Collector do ambiente `lab`.
- [components/mailhog/](components/mailhog/) mantém o MailHog usado pelos fluxos de notificação em laboratório.
- [overlays/lab/](overlays/lab/) renderiza os componentes compartilhados do cluster que não dependem de instalação Helm.

O New Relic OpenTelemetry Collector não é referenciado pelo overlay Kustomize porque sua instalação canônica usa o chart Helm `newrelic/nr-k8s-otel-collector`. Use [New Relic OpenTelemetry Collector no EKS lab](../docs/new-relic-otel-collector.md) e [scripts/manual/install-new-relic-otel-collector.sh](../scripts/manual/install-new-relic-otel-collector.sh) para instalar ou atualizar o release.

Este repositório é a fonte canônica dos manifests Kubernetes executáveis dos microsserviços da Fase 4, conforme a [Estratégia de entrega dos manifestos Kubernetes](../../oficina-platform/docs/kubernetes-manifest-strategy.md).

Os templates normativos ficam no `oficina-platform`:

- `templates/kubernetes/base/oficina-os-service/`;
- `templates/kubernetes/base/oficina-billing-service/`;
- `templates/kubernetes/base/oficina-execution-service/`.

Os manifests executáveis devem ser materializados neste repositório em:

```text
k8s/base/microservices/
  oficina-os-service/
  oficina-billing-service/
  oficina-execution-service/
```

Esses manifests já estão materializados em [base/microservices/](base/microservices/). O overlay [overlays/lab/](overlays/lab/) continua restrito aos componentes compartilhados que não dependem de imagem dos microsserviços. Os Deployments dos microsserviços são aplicados por [scripts/manual/apply-microservices.sh](../scripts/manual/apply-microservices.sh), que prepara secrets Kubernetes, substitui issuer/JWKS e usa imagens publicadas no ECR. Não aplique [base/microservices/](base/microservices/) diretamente no cluster, porque a base mantém placeholders de imagem e autenticação.

Renderização:

```bash
kubectl kustomize k8s/overlays/lab
kubectl kustomize k8s/base/microservices
```
