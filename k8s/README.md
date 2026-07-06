# Kubernetes

Estrutura Kubernetes do ambiente `lab`.

- [components/aws-observability/](components/aws-observability/) define recursos de observabilidade AWS-native reutilizáveis.
- [components/new-relic-otel-collector/values.lab.yaml](components/new-relic-otel-collector/values.lab.yaml) define os valores Helm do New Relic OpenTelemetry Collector do ambiente `lab`.
- [components/mailhog/](components/mailhog/) mantém o MailHog usado pelos fluxos de notificação em laboratório.
- [overlays/lab/](overlays/lab/) renderiza os componentes compartilhados do cluster.

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

O overlay `lab` deve referenciar esses manifests quando os secrets, imagens ECR e recursos AWS dependentes estiverem prontos.

Renderização:

```bash
kubectl kustomize k8s/overlays/lab
```
