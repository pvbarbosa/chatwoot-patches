# frozen_string_literal: true
# [pvb-premium] Garante plano premium + features premium após CADA boot.
#
# Contexto: o fork AstraChat (v4.16+) tem um sistema de licença próprio
# (Kanban::License). Sem token, o enforce de boot grava
# INSTALLATION_PRICING_PLAN = 'community'. Este initializer roda POR ÚLTIMO
# (zzz_ > zz_ > force_enterprise_plan) e restaura o estado premium.
#
# Idempotente e à prova de falhas: qualquer erro é logado, nunca quebra o boot.

Rails.application.config.after_initialize do
  begin
    plan = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
    plan.value = 'premium'
    plan.save! if plan.changed?

    qty = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')
    qty.value = 99999
    qty.save! if qty.changed?

    premium = YAML.safe_load(Rails.root.join('config/features.yml').read)
                 .select { |f| f['premium'] }.map { |f| f['name'] }

    Account.find_in_batches do |accounts|
      accounts.each { |account| account.enable_features!(*premium) }
    end

    Rails.logger&.info("[pvb-premium] plano premium + #{premium.length} features garantidas.")
  rescue StandardError => e
    Rails.logger&.warn("[pvb-premium] não aplicado: #{e.class} #{e.message}")
  end
end
