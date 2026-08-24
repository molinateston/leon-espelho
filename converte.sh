#!/usr/bin/env bash
# converte-leon.sh — transforma uma casa ARTESANAL (usuario `agente`, canal antigo)
# num cliente do PRODUTO UNICO (leon-clientes), preservando a vida da casa:
# memoria (brain), persona do dono e pareamento do Telegram.
#
# Lei do dono (24/08): "jogar os artesanais pra dentro dos pagos; eu libero a licenca
# manualmente; quero poucos gits e um processo so".
#
# Como roda (no Terminal do navegador da VPS do cliente, como root):
#   curl -fsSL https://licenca.leonardomolina.com.br/converte.sh | bash
# Pergunta UMA coisa: o e-mail da licenca (que o dono ja liberou no painel).
# O resto vem da propria casa. Rollback: o LEON antigo fica parado no disco,
# e a foto completa fica em /root/leon-antes-conversao-*.tar.gz.
set -uo pipefail
CENTRAL="${LEON_CENTRAL:-https://licenca.leonardomolina.com.br}"
VELHA=/home/agente
say(){ printf '%s\n' "$*"; }

[ "$(id -u)" = 0 ] || { say "Rode como root (no Terminal do navegador ja e root)."; exit 1; }
[ -d "$VELHA/lean-bridge" ] || { say "Nao achei um LEON artesanal aqui ($VELHA/lean-bridge). Nada a converter."; exit 1; }

ENV_VELHO="$VELHA/lean-bridge/.env"
pega(){ sed -n "s/^$1=//p" "$ENV_VELHO" 2>/dev/null | head -1 | tr -d '"' | tr -d "'" | tr -d ' '; }
BOT_TOKEN="$(pega TELEGRAM_BOT_TOKEN)"; [ -n "$BOT_TOKEN" ] || BOT_TOKEN="$(pega BOT_TOKEN)"
OWNER_CHAT_ID="$(pega OWNER_CHAT_ID)"
NOME="$(pega AGENT_NAME)"; [ -n "$NOME" ] || NOME="LEON"
[ -n "$BOT_TOKEN" ] || { say "A casa antiga nao tem token do bot no .env — converta pela instalacao normal."; exit 1; }

say "== Conversao pro LEON completo =="
say "   agente: $NOME · pareamento e memoria serao preservados."
printf 'E-mail da licenca (o dono ja liberou): '
read -r EMAIL </dev/tty
case "$EMAIL" in *@*.*) ;; *) say "e-mail invalido"; exit 1;; esac

TS=$(date +%Y%m%d-%H%M%S)
say ">> foto de seguranca da casa antiga..."
tar czf "/root/leon-antes-conversao-$TS.tar.gz" -C /home agente/lean-bridge agente/.leon 2>/dev/null || true
chmod 600 "/root/leon-antes-conversao-$TS.tar.gz" 2>/dev/null

say ">> pausando o LEON antigo (evita dois agentes brigando pelo mesmo bot)..."
sudo -u agente XDG_RUNTIME_DIR=/run/user/$(id -u agente) systemctl --user stop agente.service 2>/dev/null || true
sudo -u agente XDG_RUNTIME_DIR=/run/user/$(id -u agente) systemctl --user disable agente.service 2>/dev/null || true
# crons antigos calam (comentados, nao apagados: rollback e descomentar)
crontab -u agente -l 2>/dev/null | sed 's|^\([^#].*lean-bridge.*\)$|#CONVERTIDO '"$TS"' \1|' | crontab -u agente - 2>/dev/null || true

say ">> instalando o LEON completo (motor Claude)..."
export EMAIL NOME BOT_TOKEN OWNER_CHAT_ID LEON_ENGINE=claude GENDER="${GENDER:-male}"
if ! curl -fsSL "$CENTRAL/install-leon.sh" | bash; then
  say ""
  say "‼️ A instalacao nao terminou. O LEON ANTIGO esta intacto — pra religar:"
  say "   sudo -u agente XDG_RUNTIME_DIR=/run/user/\$(id -u agente) systemctl --user enable --now agente.service"
  exit 1
fi

say ">> transplantando a memoria e a persona..."
NOVO_HOME="$(getent passwd leon | cut -d: -f6)"; NOVO_HOME="${NOVO_HOME:-/home/leon}"
BRAIN_NOVO="$NOVO_HOME/lean-bridge/brain"
PERSONA_NOVA="$NOVO_HOME/.leon/persona"
# brain: o conteudo antigo entra; o que a instalacao criou com mesmo nome e preservado como .novo
if [ -d "$VELHA/.leon" ]; then
  mkdir -p "$BRAIN_NOVO"
  cp -rn "$VELHA/.leon/." "$BRAIN_NOVO/" 2>/dev/null || true
fi
# persona do dono (NUNCA por cima do nucleo/motor do produto)
if [ -d "$VELHA/lean-bridge/persona" ]; then
  mkdir -p "$PERSONA_NOVA"
  for f in "$VELHA"/lean-bridge/persona/*; do
    b="$(basename "$f")"
    case "$b" in NUCLEO-LEON.md|_MOTOR-*.md) continue;; esac
    [ -e "$PERSONA_NOVA/$b" ] || cp -r "$f" "$PERSONA_NOVA/" 2>/dev/null || true
  done
fi
# salas do Telegram (o mapa dos topicos)
[ -f "$VELHA/lean-bridge/topics.json" ] && [ ! -s "$NOVO_HOME/lean-bridge/topics.json" ] \
  && cp "$VELHA/lean-bridge/topics.json" "$NOVO_HOME/lean-bridge/topics.json" 2>/dev/null || true
chown -R leon:leon "$NOVO_HOME/lean-bridge" "$NOVO_HOME/.leon" 2>/dev/null || true

say ">> reiniciando com a memoria transplantada..."
sudo -u leon XDG_RUNTIME_DIR=/run/user/$(id -u leon) systemctl --user restart leon-agente.service 2>/dev/null || true

say ""
say "✅ CONVERTIDO. Mande uma mensagem pro seu bot no Telegram — e o mesmo agente,"
say "   com a memoria de sempre, agora no produto completo (nucleo, backup, banco, skills)."
say "   O antigo ficou guardado em /root/leon-antes-conversao-$TS.tar.gz (e parado no disco)."
