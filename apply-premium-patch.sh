#!/bin/bash
# =============================================================================
# apply-premium-patch.sh
# =============================================================================
# Aplica os patches enterprise no Chatwoot APÓS uma atualização.
#
# Como usar:
#   1. Atualize os serviços (docker service update ...)
#   2. Execute: bash /opt/stacks/chatwoot-patches/apply-premium-patch.sh
# =============================================================================

set -e

echo "========================================"
echo " Chatwoot Premium Patch"
echo "========================================"

# Aguarda os containers iniciarem
echo "[1/6] Aguardando containers subirem..."
sleep 15

# Pega o ID do container do app
CID=$(docker ps --filter name=chatwoot_app --format '{{.ID}}' | head -1)
if [ -z "$CID" ]; then
  echo "ERRO: Container chatwoot_app nao encontrado!"
  exit 1
fi
echo "  Container: $CID"

PATCHES_DIR="/opt/stacks/chatwoot-patches/patches"

# Aplica os 3 patches
echo "[2/6] Aplicando chatwoot_hub.rb..."
docker cp "$PATCHES_DIR/chatwoot_hub.rb" "$CID:/app/enterprise/lib/enterprise/chatwoot_hub.rb"

echo "[3/6] Aplicando check_new_versions_job.rb..."
docker cp "$PATCHES_DIR/check_new_versions_job.rb" "$CID:/app/enterprise/app/jobs/enterprise/internal/check_new_versions_job.rb"

echo "[4/6] Aplicando reconcile_plan_config_service.rb..."
docker cp "$PATCHES_DIR/reconcile_plan_config_service.rb" "$CID:/app/enterprise/app/services/internal/reconcile_plan_config_service.rb"

# Atualiza/configura o plano no banco de dados
echo "[5/6] Configurando plano premium no banco de dados..."
docker exec $CID sh -c 'cd /app && bundle exec rails runner "
  cfg = InstallationConfig.find_or_initialize_by(name: \"INSTALLATION_PRICING_PLAN\")
  cfg.value = \"premium\"
  cfg.save!

  qty = InstallationConfig.find_or_initialize_by(name: \"INSTALLATION_PRICING_PLAN_QUANTITY\")
  qty.value = 99999
  qty.save!

  features = YAML.safe_load(Rails.root.join(\"config/features.yml\").read)
  premium = features.select { |f| f[\"premium\"] }.map { |f| f[\"name\"] }
  Account.find_in_batches do |accounts|
    accounts.each do |account|
      account.enable_features!(*premium)
    end
  end
  puts \"Plano premium configurado com #{premium.length} features ativadas.\"
" 2>/dev/null'

# Commit da imagem para preservar os patches
echo "[6/6] Salvando nova imagem Docker..."
docker commit $CID astraonline/astrachat:premium-latest

echo ""
echo "========================================"
echo " ✅ Premium Patch aplicado com sucesso!"
echo "========================================"
echo "Nova imagem: astraonline/astrachat:premium-latest"
echo ""
echo "Para usar esta imagem permanentemente:"
echo "  docker service update --image astraonline/astrachat:premium-latest chatwoot_chatwoot_app"
echo "  docker service update --image astraonline/astrachat:premium-latest chatwoot_chatwoot_sidekiq"
