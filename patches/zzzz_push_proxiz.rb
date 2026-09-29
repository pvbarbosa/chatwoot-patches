# frozen_string_literal: true
# [pvb-proxiz] Notificação push estilo WhatsApp (restaurado da v4.15.1).
#
# Título = nome do contato/grupo; corpo = mensagem. push_message_body devolve
# "Remetente: conteúdo". Como o remetente já vai no título, em conversa 1:1
# removemos o "Nome: " do começo do corpo. Em GRUPO (identifier @g.us)
# mantemos, pois o participante fica dentro do conteúdo.
#
# História: este patch vivia aplicado direto na imagem v4.15.1 (sem versionamento)
# e se perdeu no update para a v4.17.1. Agora é parte do repo de patches.

Rails.application.config.after_initialize do
  module PvbProxizPush
    def push_message
      message = super
      conv = notification.try(:conversation)
      return message if conv.blank?

      body = notification.push_message_body.to_s.strip
      if body.present?
        contact = conv.contact
        contact_name = contact&.name.to_s.strip
        grupo = contact&.identifier.to_s.end_with?('@g.us')
        message[:title] = contact_name if contact_name.present?
        body = body.sub(/\A#{Regexp.escape(contact_name)}:\s*/, '') if !grupo && contact_name.present?
        message[:body] = body
      end
      message
    end
  end

  begin
    Notification::PushNotificationService.prepend(PvbProxizPush)
  rescue StandardError => e
    Rails.logger&.warn("[pvb-proxiz] não aplicado: #{e.class} #{e.message}")
  end
end
