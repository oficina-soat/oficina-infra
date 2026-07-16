# Hospedagem opcional da UI

A composição em `terraform/optional/ui-hosting/lab` hospeda o `oficina-ui` como website S3. Ela é deliberadamente independente da infraestrutura obrigatória: possui root module e state próprios e não referencia recursos dos states de EKS, bancos, mensageria, API Gateway ou Lambdas. Esse fallback existe porque a role `voclabs` do laboratório não possui permissões de CloudFront.

## Recursos

- bucket S3 criptografado e versionado, com leitura pública limitada aos objetos da UI;
- website S3 com `index.html` como documento inicial e de erro, necessário às rotas da SPA;
- cache dos objetos controlado pelos metadados definidos no upload do pipeline;
- outputs exclusivos para o pipeline do `oficina-ui`.

O endpoint de website S3 é HTTP e não adiciona os headers de segurança que existiam na composição CloudFront. Essa limitação é aceita somente no lab opcional. Uma publicação HTTPS deve usar uma camada externa compatível ou credenciais AWS com permissões de CloudFront antes de ser considerada para outro ambiente.

## State e execução

O workflow `UI Hosting Lab` é manual. Ele aceita `plan`, `apply` ou `destroy` e usa por padrão a key independente `oficina/lab/optional/ui-hosting/terraform.tfstate`. O bucket do backend é derivado automaticamente da conta, infraestrutura compartilhada e região AWS; `TF_STATE_BUCKET`, `TF_STATE_REGION` e `TF_STATE_DYNAMODB_TABLE` permanecem disponíveis somente como overrides. Configure no repositório:

- secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e, quando necessário, `AWS_SESSION_TOKEN`;
Assim, `action=apply` funciona apenas com as credenciais AWS do repositório e sem variáveis funcionais adicionais.

Aplicar ou destruir esse workflow não executa o workflow `Deploy Lab` e não altera componentes obrigatórios.
