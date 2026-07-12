# 🚀 Chatwoot Premium Patch

Habilita permanentemente os recursos enterprise no Chatwoot (fork AstraOnline).

## 📂 Estrutura

```
chatwoot-patches/
├── patches/
│   ├── chatwoot_hub.rb                  # Força pricing_plan = 'premium'
│   ├── check_new_versions_job.rb        # Remove overwrite do plano pelo hub
│   └── reconcile_plan_config_service.rb # No-op no reconciliador de planos
├── Dockerfile                           # Builda imagem com patches inclusos
├── apply-premium-patch.sh               # Script para aplicar após atualizações
└── README.md                            # Este arquivo
```

## 🐳 Opção 1: Dockerfile (recomendado)

Constrói uma imagem própria com os patches já inclusos:

```bash
cd /opt/stacks/chatwoot-patches

# Build da imagem
docker build -t astraonline/astrachat:premium .

# Atualizar serviços
docker service update --image astraonline/astrachat:premium chatwoot_chatwoot_app
docker service update --image astraonline/astrachat:premium chatwoot_chatwoot_sidekiq
```

### Para atualizar a versão:

1. Edite o `Dockerfile` e altere a linha `FROM` para a nova tag
2. Rebuild: `docker build -t astraonline/astrachat:premium .`
3. Atualize os serviços com `docker service update --image ...`

## 📜 Opção 2: Script de pós-atualização (fallback)

Use quando precisar aplicar os patches manualmente após um update:

```bash
bash /opt/stacks/chatwoot-patches/apply-premium-patch.sh
```

O script:
1. Aguarda os containers subirem
2. Copia os 3 patches para dentro do container
3. Configura o plano premium no banco de dados
4. Cria uma imagem commitada: `astraonline/astrachat:premium-latest`

## 🔧 O que cada patch faz

| Arquivo | Efeito |
|---|---|
| `chatwoot_hub.rb` | `ChatwootHub.pricing_plan` SEMPRE retorna `'premium'` (ignora DB e hub externo) |
| `check_new_versions_job.rb` | Job agendado NÃO sobrescreve mais o plano com resposta do hub |
| `reconcile_plan_config_service.rb` | Serviço de reconciliação não desabilita mais features premium |

## ✅ Verificação

Para confirmar que está funcionando:

```bash
docker exec $(docker ps --filter name=chatwoot_app --format '{{.ID}}' | head -1) \
  sh -c 'cd /app && bundle exec rails runner "puts ChatwootHub.pricing_plan"'
```

Deve retornar: `premium`
