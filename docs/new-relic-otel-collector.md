# New Relic OpenTelemetry Collector no EKS lab

O backend canônico de observabilidade da Fase 4 é o New Relic. No cluster `eks-lab`, a coleta deve ser feita pelo New Relic OpenTelemetry Collector instalado via Helm, com logs de pods, métricas Kubernetes/Prometheus e traces via OTLP/gRPC.

O collector roda dentro do cluster, mas a conta New Relic e a license key continuam externas. A chave não deve ser versionada neste repositório; ela deve ser informada por secret do GitHub ou variável local no momento do deploy.

## Artefatos

- [../k8s/components/new-relic-otel-collector/values.lab.yaml](../k8s/components/new-relic-otel-collector/values.lab.yaml) define os valores Helm do ambiente `lab`.
- [../scripts/manual/install-new-relic-otel-collector.sh](../scripts/manual/install-new-relic-otel-collector.sh) instala ou atualiza o release Helm `nr-k8s-otel-collector`.
- [../scripts/actions/ci-deploy.sh](../scripts/actions/ci-deploy.sh) pode instalar o collector automaticamente quando `INSTALL_NEW_RELIC_OTEL_COLLECTOR=true`.

## Variáveis

| Nome | Obrigatória | Padrão | Uso |
|---|---|---|---|
| `NEW_RELIC_LICENSE_KEY` | Sim, quando `UPSERT_NEW_RELIC_SECRET=true` | vazio | License key criada no New Relic e gravada no Secret Kubernetes `new-relic-license-key`. |
| `NEW_RELIC_NAMESPACE` | Não | `newrelic` | Namespace Kubernetes do collector. |
| `NEW_RELIC_OTEL_COLLECTOR_HELM_RELEASE` | Não | `nr-k8s-otel-collector` | Nome do release Helm. |
| `NEW_RELIC_OTEL_COLLECTOR_LOCAL_SERVICE_NAME` | Não | `nr-k8s-otel-collector-gateway` | Nome do Service interno usado pelos microsserviços para OTLP/gRPC. |
| `NEW_RELIC_LICENSE_KEY_SECRET_NAME` | Não | `new-relic-license-key` | Nome do Secret Kubernetes com a license key. |
| `NEW_RELIC_LICENSE_KEY_SECRET_KEY` | Não | `licenseKey` | Chave dentro do Secret Kubernetes. |
| `NEW_RELIC_CLUSTER_NAME` | Não | valor de `EKS_CLUSTER_NAME` | Nome do cluster reportado ao New Relic. |
| `NEW_RELIC_OTLP_ENDPOINT` | Não | `https://otlp.nr-data.net` | Endpoint OTLP externo do New Relic. Alterar quando a conta usar outra região. |
| `INSTALL_NEW_RELIC_OTEL_COLLECTOR` | Não | `false` | Habilita a instalação no deploy automatizado. |
| `UPSERT_NEW_RELIC_SECRET` | Não | `true` | Cria ou atualiza o Secret Kubernetes a partir de `NEW_RELIC_LICENSE_KEY`. |
| `SKIP_KUBECONFIG_UPDATE` | Não | `false` | Evita atualizar o kubeconfig quando o deploy já fez isso. |

## Instalação local

```bash
export NEW_RELIC_LICENSE_KEY=<license-key>
scripts/manual/install-new-relic-otel-collector.sh
```

Para reutilizar um Secret Kubernetes já existente:

```bash
UPSERT_NEW_RELIC_SECRET=false scripts/manual/install-new-relic-otel-collector.sh
```

## Deploy automatizado

No GitHub Environment `lab`, configure:

- secret `NEW_RELIC_LICENSE_KEY`;
- variável `INSTALL_NEW_RELIC_OTEL_COLLECTOR=true`;
- variável `NEW_RELIC_OTLP_ENDPOINT`, se a conta não usar o endpoint padrão `https://otlp.nr-data.net`.

O workflow de deploy executa o Terraform, aplica o overlay Kubernetes compartilhado e, quando habilitado, instala ou atualiza o collector via Helm.

## Endpoint OTLP interno

Com os valores padrão, os microsserviços devem usar:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://nr-k8s-otel-collector-gateway.newrelic.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

O Service interno `nr-k8s-otel-collector-gateway` expõe OTLP/gRPC em `4317` e OTLP/HTTP em `4318`.

## Coleta esperada

- Logs: coletados dos pods pelo receiver `filelog`.
- Métricas Prometheus e Kubernetes: coletadas pelos receivers `prometheus`, `hostmetrics`, `kubeletstats`, `k8s_events` e `kube-state-metrics`.
- Traces: recebidos por OTLP/gRPC no Service interno `nr-k8s-otel-collector-gateway`.

Depois da instalação no `eks-lab`, valide:

```bash
kubectl -n newrelic get pods
kubectl -n newrelic get svc nr-k8s-otel-collector-gateway
kubectl -n newrelic logs -l app.kubernetes.io/name=nr-k8s-otel-collector --tail=100
```

As evidências finais de logs, métricas, traces, dashboards e alertas devem ser registradas no [checklist final da Fase 4](../../oficina-platform/docs/phase-4-delivery-checklist.md).
