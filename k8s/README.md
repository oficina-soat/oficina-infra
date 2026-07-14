# Kubernetes

Estrutura Kubernetes do ambiente `lab`.

- [components/new-relic-otel-collector/values.lab.yaml](components/new-relic-otel-collector/values.lab.yaml) define os valores Helm do New Relic OpenTelemetry Collector do ambiente `lab`.
- [components/mailhog/](components/mailhog/) mantém o MailHog usado pelos fluxos de notificação em laboratório.
- [overlays/lab/](overlays/lab/) renderiza os componentes compartilhados do cluster que não dependem de instalação Helm.

O New Relic OpenTelemetry Collector não é referenciado pelo overlay Kustomize porque sua instalação canônica usa o chart Helm `newrelic/nr-k8s-otel-collector`. Use [New Relic OpenTelemetry Collector no EKS lab](../docs/new-relic-otel-collector.md) e [scripts/manual/install-new-relic-otel-collector.sh](../scripts/manual/install-new-relic-otel-collector.sh) para instalar ou atualizar o release.

Cada microsserviço é a fonte canônica de sua base Kubernetes executável, conforme a [Estratégia de entrega dos manifestos Kubernetes](../../oficina-platform/docs/infrastructure/kubernetes-manifest-strategy.md). Este repositório mantém os componentes compartilhados e a composição do ambiente `lab`.

Os templates normativos ficam no `oficina-platform`:

- `templates/kubernetes/base/oficina-os-service/`;
- `templates/kubernetes/base/oficina-billing-service/`;
- `templates/kubernetes/base/oficina-execution-service/`.

Os manifests executáveis são materializados nos repositórios dos serviços em:

```text
../oficina-os-service/k8s/base/
../oficina-billing-service/k8s/base/
../oficina-execution-service/k8s/base/
```

O overlay [overlays/lab/](overlays/lab/) permanece restrito aos componentes compartilhados. Os Deployments são aplicados por [scripts/manual/apply-microservices.sh](../scripts/manual/apply-microservices.sh), que lê as bases dos serviços, prepara secrets Kubernetes, substitui issuer/JWKS e usa imagens publicadas no ECR. Não aplique as bases diretamente no cluster enquanto mantiverem placeholders de imagem e autenticação.

Renderização:

```bash
kubectl kustomize k8s/overlays/lab
```
