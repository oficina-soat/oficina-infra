# Hospedagem opcional da UI

A composição em `terraform/optional/ui-hosting/lab` hospeda o `oficina-ui` em S3 privado e CloudFront. Ela é deliberadamente independente da infraestrutura obrigatória: possui root module e state próprios e não referencia recursos dos states de EKS, bancos, mensageria, API Gateway ou Lambdas.

## Recursos

- bucket S3 privado, criptografado, versionado e acessível somente pelo CloudFront via OAC;
- CloudFront com certificado padrão, TLS 1.2, compressão e classe de preço econômica;
- cache longo para artefatos versionados e cache desabilitado para `index.html` e `config/*`;
- fallback `403/404` para `index.html`, necessário às rotas da SPA;
- CSP, HSTS, proteção contra framing e MIME sniffing, políticas de referência, permissões e isolamento cross-origin;
- outputs exclusivos para o pipeline do `oficina-ui`.

## State e execução

O workflow `UI Hosting Lab` é manual. Ele aceita `plan`, `apply` ou `destroy` e usa por padrão a key independente `oficina/lab/optional/ui-hosting/terraform.tfstate`. O bucket do backend é derivado automaticamente da conta, infraestrutura compartilhada e região AWS; `TF_STATE_BUCKET`, `TF_STATE_REGION` e `TF_STATE_DYNAMODB_TABLE` permanecem disponíveis somente como overrides. Configure no repositório:

- secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e, quando necessário, `AWS_SESSION_TOKEN`;
- var `UI_CONNECT_SRC_ORIGINS` como lista JSON contendo os origins públicos das APIs.

Aplicar ou destruir esse workflow não executa o workflow `Deploy Lab` e não altera componentes obrigatórios.
