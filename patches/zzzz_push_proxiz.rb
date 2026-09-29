# frozen_string_literal: true
# [pvb-proxiz] Notificação push estilo WhatsApp (v2, refinada com testes reais).
#
# Título = nome do contato/grupo; corpo = conteúdo da mensagem.
#
# Regras:
# - 1:1 — remove do corpo o remetente duplicado ("Nome:" do contato e o padrão
#   WhatsApp "*Qualquer Nome:*" embutido pelo pipeline EvoGO/wootrico). Mídia
#   vira "🎤 Áudio: legenda" (ou só o label, sem legenda).
# - GRUPO (identifier @g.us) — mantém o participante no corpo (design original):
#   texto = "Participante: mensagem"; mídia = "🎤 Áudio — Participante".

Rails.application.config.after_initialize do
  module PvbProxizPush
    MEDIA_LABELS = {
      'image' => '📷 Imagem', 'audio' => '🎤 Áudio', 'video' => '🎬 Vídeo',
      'sticker' => '🎨 Figurinha', 'location' => '📍 Localização',
      'file' => '📄 Documento'
    }.freeze

    WA_SENDER_PREFIX = /\A\*([^*:\n]{1,80}):\*\s*/.freeze

    def push_message
      message = super
      conv = notification.try(:conversation)
      return message if conv.blank?

      contact = conv.contact
      contact_name = contact&.name.to_s.strip
      grupo = contact&.identifier.to_s.end_with?('@g.us')

      msg = notification.try(:secondary_actor)
      msg = nil unless msg.is_a?(Message)
      if msg.blank? && conv.respond_to?(:messages)
        last = conv.messages.order(:id).last
        msg = last if last.is_a?(Message)
      end

      if msg&.attachments.present? && MEDIA_LABELS.key?(msg.attachments.first.file_type.to_s)
        body = media_body(msg, grupo, contact_name)
      else
        body = text_body(grupo, contact_name)
      end

      message[:title] = contact_name if contact_name.present?
      message[:body] = body
      message
    end

    private

    def text_body(grupo, contact_name)
      body = notification.push_message_body.to_s.strip
      body = remove_contact_prefix(body, contact_name)
      grupo ? body : body.sub(WA_SENDER_PREFIX, '')
    end

    def media_body(msg, grupo, contact_name)
      label = MEDIA_LABELS[msg.attachments.first.file_type.to_s]
      caption = remove_contact_prefix(msg.content.to_s.strip, contact_name)

      if grupo
        sender = caption.match(WA_SENDER_PREFIX)&.[](1)
        sender.present? ? "#{label} — #{sender}" : label
      elsif caption.present?
        "#{label}: #{caption.sub(WA_SENDER_PREFIX, '').truncate_words(10)}"
      else
        label
      end
    end

    def remove_contact_prefix(body, contact_name)
      return body if contact_name.blank?

      body.sub(/\A#{Regexp.escape(contact_name)}:\s*/, '')
    end
  end

  begin
    Notification::PushNotificationService.prepend(PvbProxizPush)
  rescue StandardError => e
    Rails.logger&.warn("[pvb-proxiz] não aplicado: #{e.class} #{e.message}")
  end
end
