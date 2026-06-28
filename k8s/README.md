# Kubernetes

Estrutura compartilhada do ambiente `lab`.

- [components/aws-observability/](components/aws-observability/) define recursos de observabilidade AWS-native reutilizáveis.
- [components/mailhog/](components/mailhog/) mantém o MailHog usado pelos fluxos de notificação em laboratório.
- [overlays/lab/](overlays/lab/) renderiza os componentes compartilhados do cluster.

Manifests específicos dos microsserviços devem permanecer nos repositórios `oficina-os-service`, `oficina-billing-service` e `oficina-execution-service`, usando os templates definidos no `oficina-platform`.

Renderização:

```bash
kubectl kustomize k8s/overlays/lab
```
