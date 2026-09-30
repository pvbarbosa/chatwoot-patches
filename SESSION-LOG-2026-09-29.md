# 📋 Log de Sessão — Update do Chatwoot 4.15.1 → 4.17.1

**Data:** 2026-09-29
**Servidor:** pvbarbosa.com.br (Docker Swarm, 1 nó: `proxiz-server-1`)
**Resultado:** ✅ sucesso, sem perda de dados. Rollback disponível.

---

## 1. Objetivo

Atualizar o Chatwoot (fork AstraChat `astraonline/astrachat`) da versão **4.15.1**
(base `v4.15.1-proxiz2`) para a **v4.17.1** (tag `v4.17.1-0.0.3`, publicada em 25/09/2026)
**sem perder** os patches premium que fazem o Chatwoot funcionar com o Wootrico
e o módulo astra (Kanban).

## 2. Estado inicial

| Item | Valor |
|---|---|
| Serviços | `chatwoot_chatwoot_app`, `chatwoot_chatwoot_sidekiq` (imagem `astraonline/astrachat:premium`), `chatwoot_chatwoot_redis` |
| Banco | Serviço `pgvector_pgvector` (pgvector/pgvector:pg16), DB `chatwoot`, 53 MB |
| Patches | repo `pvbarbosa/chatwoot-patches` @ `b015777` (3 patches: chatwoot_hub, check_new_versions_job, reconcile_plan_config_service) |
| Mounts antigos | 4 volumes: `chatwoot_storage` (`/app/storage`), `chatwoot_public` (`/app/public`), `chatwoot_mailer` (`/app/app/views/devise/mailer`), `chatwoot_mailers` (`/app/app/views/mailers`) |
| Rollback pré-existente | `ghcr.io/pvbarbosa/astrachat:premium` (imagem 4.15.1 patcheada) |

## 3. Verificações pré-flight

- **Compatibilidade dos patches:** os 3 arquivos-alvo existem na v4.17.1 com a
  mesma estrutura. O `check_new_versions_job.rb` enterprise novo ganhou
  `update_plan_info` (sobrescreve o plano com resposta do hub) — nosso patch
  (chamada só `super`) continua neutralizando.
- **Tags do fork no Docker Hub:** atual = `v4.15.1-proxiz2` (não-publicada);
  nova mais recente = `v4.17.1-0.0.3`. Ruby 3.4.4 em ambas (risco de gems baixo).
- **Volumes inspecionados:** `chatwoot_public` = assets padrão (shadowing);
  `chatwoot_storage` = 5.9 GB de anexos (dado do usuário, intocado);
  `chatwoot_mailer`/`chatwoot_mailers` = conteúdo antigo da imagem, sem
  customização real (o template "diferente" era o template upstream antigo
  preso no volume desde o 1º boot).

## 4. Backups (fase 1)

Criados em `/opt/backups/` (timestamp `20260929-173813`):

| Arquivo | Conteúdo |
|---|---|
| `chatwoot-db-20260929-173813.sql.gz` (2.9 MB) | `pg_dump` completo do DB `chatwoot` |
| `chatwoot_public-20260929-173813.tar.gz` (52 MB) | volume `chatwoot_public` antes do update |
| `chatwoot_mailer-20260929-173813.tar.gz` | volume `chatwoot_mailer` |
| `chatwoot_mailers-20260929-173813.tar.gz` | volume `chatwoot_mailers` |

Tags de rollback: `astraonline/astrachat:v4.15.1-premium-rollback` (local) e
`ghcr.io/pvbarbosa/astrachat:v4.15.1-premium` (digest `b5d69eef...`).

## 5. Build (fase 2)

`Dockerfile` atualizado: `FROM astraonline/astrachat:v4.17.1-0.0.3` + os patches.
Build ok, patches confirmados dentro da imagem.

## 6. Janela de manutenção (fase 3)

1. `docker service scale chatwoot_chatwoot_app=0 chatwoot_chatwoot_sidekiq=0`
2. Volume `chatwoot_public` sincronizado com os assets da imagem nova
   (limpado e repovoado de `/app/public` da imagem).
3. `docker service update --image ... premium-next` nos 2 serviços + scale 1.

## 7. Surpresa nº 1 — Integrity guard anti-tamper (v4.16+ do fork)

**Sintoma:** boot travado em "Migracao falhou (tentativa N/6)" com a mensagem
`[AstraChat] Configuração inválida: não é permitido mapear volume em /app`.

**Causa:** initializer `zzz_integrity_guard` (bytecode YARV compilado) recusa
subir se houver mounts em paths de código: `/app/app`, `/app/lib`,
`/app/enterprise`, `/app/config`, `/app/db`, `/app/vendor`, `/app/bin`.
Só `/app/storage` é permitido. Os 3 mounts de views/assets violavam isso.

**Resolução:** remoção dos mounts via CLI (sem editar stack):

```bash
docker service update \
  --mount-rm /app/public \
  --mount-rm /app/app/views/devise/mailer \
  --mount-rm /app/app/views/mailers \
  chatwoot_chatwoot_app   # e idem sidekiq
```

Antes de remover, conferido arquivo por arquivo que NÃO havia customização
(backup tar.gz de cada volume fica em `/opt/backups/`).

**Consequência positiva:** e-mails agora usam os templates novos do fork
(`confirmation_instructions.liquid` etc.), e o frontend usa os assets Vite
compilados dentro da imagem.

## 8. Surpresa nº 2 — Enforce de licença do fork (`Kanban::License`)

**Sintoma:** após gravar `INSTALLATION_PRICING_PLAN = 'premium'` no DB,
minutos depois voltava a `community`.

**Investigação:**
- A v4.16+ do fork tem sistema de licença próprio: `Kanban::License`
  (bytecode em `app/services/kanban/license.yarb`), com token verificado
  contra o servidor `CHATWOOT_HUB_URL` (Ed25519, expiração, grace period).
- O initializer `force_enterprise_plan` (bytecode) roda no boot e define o
  plano como `Kanban::License.active? ? 'enterprise' : 'community'` — sem
  token, grava `community` no DB **a cada boot** (inclui processos rails
  runner efêmeros!).
- `Kanban::License.enable_premium_everywhere!` existe mas NÃO muda o plano —
  só gerencia features por conta (e aqui não fez nada, retorno `true`).
- Estado observado: `{packaged: true, active: false, server_url: nil, ...}`
  — build "packaged" com marcador `/usr/local/astrachat/.packaged`.

**Resolução definitiva:** novo patch `patches/zzz_premium_plan.rb` —
initializer com `Rails.application.config.after_initialize` que roda POR
ÚLTIMO (`zzz_` > `zz_` > `force_enterprise_plan`) e restaura em cada boot:

- `INSTALLATION_PRICING_PLAN = 'premium'`
- `INSTALLATION_PRICING_PLAN_QUANTITY = 99999`
- features premium (`config/features.yml` → `enable_features!`) em todas as contas

Idempotente, à prova de falhas (rescue + log). Validado em 3 boots seguidos:
o plano permanece `premium` (log `[pvb-premium] plano premium + 18 features garantidas`).

## 9. Validação final

```
services app/sidekiq: Running
plan=premium  features=61  conversas=78  inbox=proxiz (Channel::Api)
mensagens: 29.942 (intactas)
HTTP público https://chatwoot.pvbarbosa.com.br → 200
sidekiq: processando jobs normalmente
```

## 10. Artefatos gerados

- **GitHub:** `pvbarbosa/chatwoot-patches` @ `31d7b3d` — Dockerfile (base
  v4.17.1-0.0.3), novo patch `zzz_premium_plan.rb`, script
  `apply-premium-patch.sh` atualizado (4 patches), README com requisitos da v4.16+.
- **Imagem local:** `astraonline/astrachat:premium` (= base v4.17.1-0.0.3 + 4 patches).
- **GHCR:** `ghcr.io/pvbarbosa/astrachat:v4.17.1-premium`
  (digest `1b6d619f...`) — nova; `:v4.15.1-premium` (digest `b5d69eef...`) — rollback.

## 11. Receita para o PRÓXIMO update (checklist)

1. Escolher a tag no Docker Hub do fork (`astraonline/astrachat`), puxar e
   conferir que os 4 arquivos-alvo dos patches existem na imagem nova.
2. Backup: `pg_dump` do DB `chatwoot` + tar dos volumes que existirem.
3. `docker tag` da imagem atual como rollback (local + GHCR) e push.
4. Editar `FROM` no Dockerfile → `docker build -t astraonline/astrachat:premium .`
5. `docker service scale ..._app=0 ..._sidekiq=0`.
6. Se a stack tiver mounts em paths de código, removê-los
   (`--mount-rm`) — o guard da v4.16+ exige.
7. `docker service update --image astraonline/astrachat:premium` nos 2
   serviços + scale 1. Migrations rodam sozinhas no boot (retry embutido).
8. Validar: logs `[pvb-premium]`, plano `premium`, HTTP 200, sidekiq ativo.
9. Push da imagem nova no GHCR + commit/push do repo de patches.

## 12. Rollback (se necessário um dia)

```bash
docker service update --image ghcr.io/pvbarbosa/astrachat:v4.15.1-premium chatwoot_chatwoot_app
docker service update --image ghcr.io/pvbarbosa/astrachat:v4.15.1-premium chatwoot_chatwoot_sidekiq
# re-adicionar mounts antigos se/quando necessário (tars em /opt/backups/)
# restaurar DB se migrations incompatíveis:
#   gunzip -c /opt/backups/chatwoot-db-20260929-173813.sql.gz | \
#   docker exec -i <pgvector> psql -U postgres -d chatwoot
```

## 13. Observações

- O stack file do swarm não foi editado — os `--mount-rm` vivem na spec do
  serviço. Se a stack for re-deployada do arquivo original, os mounts voltam
  e o guard vai travar o boot de novo (removê-los de novo, ou limpar o stack file).
- `Kanban::License` permanece inativo (sem token) — não afeta o uso, o
  `zzz_premium_plan.rb` cobre o plano e as features a cada boot.
- Espaço em disco: 41% usado (116G livres). Imagens antigas
  (`premium-next`, base v4.17.1) podem ser removidas se quiser liberar ~3 GB.

## 14. Adendo (mesmo dia) — Notificações push estilo WhatsApp restauradas

**Relato:** notificações mudaram após o update — antes mostravam que enviou e
a mensagem (estilo WhatsApp); depois, padrão genérico do Chatwoot.

**Causa:** a imagem v4.15.1 tinha um patch "Proxiz" aplicado direto no
`app/services/notification/push_notification_service.rb` (título = nome do
contato/grupo, corpo = conteúdo da mensagem, removendo o prefixo "Nome: " em
conversas 1:1; mantido em grupos `@g.us`). O patch NÃO estava versionado no
repo — o diff md5 entre imagens antiga/nova o revelou (comentário "Proxiz:").

**Fix definitivo:** novo patch `patches/zzzz_push_proxiz.rb` — initializer
`after_initialize` que faz `prepend` de um módulo sobrescrevendo
`push_message` (mesma lógica original). Versionado no repo, incluído no
Dockerfile e no apply-premium-patch.sh. Serviços atualizados com
`docker service update --force` (recria container com mesma tag).

**Validação:** `push_message` owner = `zzzz_push_proxiz.rb`; `PvbProxizPush`
nos ancestrais; plano premium; HTTP 200. Aplica-se a novas notificações
(browser push e FCM) — nada para refazer nos dispositivos.

**Refinamento v2 (após teste com mensagem real):** o relato inicial ("chegou
o nome, mas não a mensagem") tinha causa dupla: (a) a mensagem testada era
mídia sem texto — conteúdo literal `"*Anderson Adelino:*\n"` + anexo, então
não havia trecho para mostrar; (b) o nome do contato no Chatwoot
(`"Claude Code | Anderson Adelino"`) difere do nome WhatsApp do remetente
(`"*Anderson Adelino:*"` embutido no conteúdo pelo pipeline). Versão final:

- 1:1: corpo sem remetente (remove `Nome:` do contato E o padrão WhatsApp
  `*Qualquer Nome:*`); mídia = `🎤 Áudio: legenda` ou só o label.
- Grupo (`@g.us`): mantém participante no corpo; mídia = `🎤 Áudio — Participante`.

Testado com 4 casos reais do banco (1:1 texto, grupo texto, grupo áudio,
mídia sem legenda).

**Causa raiz final no Chrome (30/09):** o service worker da v4.17.1 do fork
**regrediu** — `showNotification(title, { tag, data })` sem `body`, então o
Chrome nunca exibia o texto da mensagem (só o título). O backend gerava o
payload correto (verificado: `body: "olá"` numa notificação real). Fix:
`patches/sw.js` com `body: notification.body`, aplicado em `/sw.js` e
`/packs/sw.js` via Dockerfile. IMPORTANTE: o Chrome mantém o SW antigo em
memória — fechar todas as abas do site e reabrir para trocar. Também vale
verificar `/packs/sw.js` no DevTools > Application > Service Workers.

Nota sobre os canais: VAPID_KEYS existe (browser push ativo); Firebase/
FIREBASE_CREDENTIALS ausentes, mas o relay do ChatwootHub
(`/send_push` → projeto FCM do fork) funciona (HTTP 200 + message name).
Subscriptions antigas: fcm 17/06, browser 11/08 e 14/08 — se o celular
não receber, re-registrar o app (logout/login no perfil).
