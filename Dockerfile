# =============================================================================
# Dockerfile - Chatwoot Premium Patch
# =============================================================================
# Usage:
#   docker build -t astraonline/astrachat:premium .
#   docker service update --image astraonline/astrachat:premium chatwoot_chatwoot_app
#   docker service update --image astraonline/astrachat:premium chatwoot_chatwoot_sidekiq
# =============================================================================

# ⚠️ ALTERE AQUI quando quiser atualizar a versão base
FROM astraonline/astrachat:v4.17.1-0.0.3

# Aplica os patches enterprise nos arquivos corretos
COPY patches/chatwoot_hub.rb                   /app/enterprise/lib/enterprise/chatwoot_hub.rb
COPY patches/check_new_versions_job.rb         /app/enterprise/app/jobs/enterprise/internal/check_new_versions_job.rb
COPY patches/reconcile_plan_config_service.rb  /app/enterprise/app/services/internal/reconcile_plan_config_service.rb

# Garante plano premium + features premium após cada boot (o enforce de licenca
# do fork grava 'community' no DB quando nao ha token de licenca)
COPY patches/zzz_premium_plan.rb               /app/config/initializers/zzz_premium_plan.rb

# Notificacao push estilo WhatsApp (titulo=contato, corpo=mensagem)
COPY patches/zzzz_push_proxiz.rb               /app/config/initializers/zzzz_push_proxiz.rb

# Mantém o entrypoint original da imagem base
