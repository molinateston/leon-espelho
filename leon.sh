#!/usr/bin/env bash
# INSTALAÇÃO DO LEON PELO TERMINAL DA VPS, EM UM COMANDO SÓ.
#
# O dono cola UMA linha no Terminal do navegador (Hostinger) e responde o que este
# script perguntar. Nada de editar comando, nada de aspas, nada de WSL.
#
# Uso oficial (o que a página manda colar):
#   curl -fsSL https://licenca.leonardomolina.com.br/leon.sh | bash
#
# A prova de erro: cada tropeço que um cliente real viveu virou uma trava aqui.
#  - lixo do "colar" do terminal do navegador (^[[200~ e afins): sanitizado em toda leitura.
#  - aspas curvas do WhatsApp/Telegram nos dados colados: convertidas.
#  - dado colado com espaço no fim, quebra de linha, tab: aparados.
#  - e-mail/token/nome errados: validados NA HORA, com nova chance, sem derrubar a instalação.
#  - rodar de novo depois de um tropeço: reaproveita o que já está certo e não repete o pareamento.
#  - motor: pergunta em português, sem jargão, com o padrão pronto no Enter.
set -uo pipefail

SUPORTE="https://wa.me/5511961562217"
CENTRAL="${LEON_CENTRAL:-https://licenca.leonardomolina.com.br}"

vermelho() { printf '\033[1;31m%s\033[0m\n' "$*"; }
verde()    { printf '\033[1;32m%s\033[0m\n' "$*"; }
amarelo()  { printf '\033[1;33m%s\033[0m\n' "$*"; }
titulo()   { printf '\n\033[1m%s\033[0m\n' "$*"; }
morre()    { vermelho ""; vermelho "PAROU AQUI: $1"; vermelho "Se travar, chama o suporte: $SUPORTE"; exit 1; }

# ---------------------------------------------------------------------------
# LEITURA À PROVA DE COLAR. O Terminal do navegador injeta a sequência do modo
# "bracketed paste" (^[[200~ ... ^[[201~) e o WhatsApp troca aspas retas por
# curvas. Tudo isso entrava no dado e quebrava a instalação depois, longe daqui.
# ---------------------------------------------------------------------------
limpa() {
  printf '%s' "$1" \
    | sed -e 's/\x1b\[?*200~//g; s/\x1b\[?*201~//g' \
          -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
          -e 's/[“”]/"/g; s/[‘’]/'"'"'/g' \
          -e 's/\r//g' \
    | tr -d '\000-\010\013\014\016-\037' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

pergunta() {  # pergunta <texto> <nome-da-var> <regex> <dica> [padrao]
  local texto="$1" var="$2" regex="$3" dica="$4" padrao="${5:-}" resp=""
  while :; do
    printf '\n%s' "$texto"
    [ -n "$padrao" ] && printf ' [%s]' "$padrao"
    printf '\n> '
    # /dev/tty: o script chega por pipe (curl | bash), entao stdin nao e o teclado.
    # LEON_TEST_STDIN=1 le do stdin, so pra bancada automatizada.
    if [ "${LEON_TEST_STDIN:-}" = "1" ]; then IFS= read -r resp || morre "fim da entrada de teste."
    else IFS= read -r resp < /dev/tty || morre "não consegui ler a resposta no terminal (abra o Terminal do navegador e cole a linha lá)."; fi
    resp="$(limpa "$resp")"
    [ -z "$resp" ] && [ -n "$padrao" ] && resp="$padrao"
    # LC_ALL=C: sem isso, faixa de caracteres no regex estoura "Invalid collation character"
    # em locale UTF-8 e NENHUMA resposta seria aceita (o dono ficaria preso no loop).
    if printf '%s' "$resp" | LC_ALL=C grep -qE "$regex"; then
      printf -v "$var" '%s' "$resp"
      return 0
    fi
    amarelo "  $dica"
  done
}

# ---------------------------------------------------------------------------
titulo "INSTALAÇÃO DO LEON"
echo "Vou te perguntar 4 coisas e cuidar do resto. Leva alguns minutos."

[ "$(id -u)" -eq 0 ] || morre "este comando roda como root. No Terminal do navegador da Hostinger você já entra como root: cole a linha lá."
command -v curl >/dev/null 2>&1 || morre "o comando curl não existe nesta VPS (sistema fora do padrão)."

# Sistema suportado, dito em português antes de gastar o tempo do dono
if [ -r /etc/os-release ]; then
  . /etc/os-release
  case "${ID:-}:${VERSION_ID:-}" in
    ubuntu:22.04|ubuntu:24.04) : ;;
    *) morre "esta VPS roda ${PRETTY_NAME:-sistema desconhecido}. O LEON pede Ubuntu 22.04 ou 24.04. No painel da Hostinger: VPS, Sistema operacional, reinstalar com Ubuntu 24.04." ;;
  esac
fi

# Reexecução: se já existe instalação, o dono não repete nada à toa
ENV_ANTIGO=""
for _p in /home/leon/socio-ia/.env /root/socio-ia/.env; do
  [ -f "$_p" ] && { ENV_ANTIGO="$_p"; break; }
done
if [ -n "$ENV_ANTIGO" ]; then
  verde "Já existe um LEON instalado aqui. Vou usar os dados que já estão certos e só completar o que faltar."
fi
le_do_env() { [ -n "$ENV_ANTIGO" ] && sed -n "s/^$1=//p" "$ENV_ANTIGO" 2>/dev/null | head -1 | tr -d '"' ; }

# a chave da licenca no .env do cliente e LEON_LICENSE_EMAIL (medido em instalacao real)
EMAIL="$(le_do_env LEON_LICENSE_EMAIL)"; [ -n "$EMAIL" ] || EMAIL="$(le_do_env EMAIL)"; [ -n "$EMAIL" ] || EMAIL="$(le_do_env LICENSE_EMAIL)"
NOME="$(le_do_env AGENT_NAME)"
TOKEN="$(le_do_env TELEGRAM_BOT_TOKEN)"; [ -n "$TOKEN" ] || TOKEN="$(le_do_env BOT_TOKEN)"
GENDER="$(le_do_env AGENT_GENDER)"
DONO="$(le_do_env OWNER_CHAT_ID)"

titulo "1 de 4 · E-mail da compra"
echo "É o e-mail que você usou pra pagar o LEON. Ele libera o download."
[ -n "$EMAIL" ] && verde "  já tenho: $EMAIL" || \
  pergunta "Qual o e-mail da compra?" EMAIL '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' "Escreva o e-mail inteiro, com @ e o ponto do final."

titulo "2 de 4 · Nome do agente"
echo "Como você vai chamar ele no Telegram."
[ -n "$NOME" ] && verde "  já tenho: $NOME" || \
  # Nome aceita acento (Sofia, Jose, Antonio): o grep com faixa de caracteres estoura no
  # locale UTF-8, entao a regra e por EXCLUSAO (sem caractere que quebre shell/arquivo).
  pergunta "Qual nome?" NOME '^[^/\\<>|;&$`"'"'"'*?]{1,40}$' "Nome curto, sem barras nem simbolos estranhos." "LEON"
NOME="$(printf '%s' "$NOME" | tr ' ' '-')"

titulo "3 de 4 · Voz"
echo "A voz que ele usa quando responde em áudio."
if [ -n "$GENDER" ]; then verde "  já tenho: $GENDER"; else
  pergunta "Digite 1 para masculina ou 2 para feminina" _V '^[12]$' "Digite só 1 ou 2." "1"
  [ "$_V" = "2" ] && GENDER="female" || GENDER="male"
fi

titulo "4 de 4 · Token do bot do Telegram"
echo "No Telegram, procure @BotFather, mande /newbot, escolha um nome e um usuário terminado em bot."
echo "Ele devolve um código no formato 123456789:AAxxxxx. É esse."
if [ -n "$TOKEN" ]; then verde "  já tenho o token guardado"; else
  while :; do
    pergunta "Cole o token do bot:" TOKEN '^[0-9]{6,}:[A-Za-z0-9_-]{20,}$' "O token tem números, dois-pontos e uma sequência longa. Copie inteiro do BotFather."
    # </dev/null: sem isso o curl herda o stdin do script e engole as respostas seguintes
    if curl -fsS --max-time 20 "https://api.telegram.org/bot$TOKEN/getMe" </dev/null 2>/dev/null | grep -q '"ok":true'; then
      verde "  token conferido com o Telegram."
      break
    fi
    amarelo "  o Telegram não aceitou esse token. Confira se copiou inteiro e tente de novo."
    TOKEN=""
  done
fi

titulo "Motor de inteligência"
echo "1 = Codex (assinatura do ChatGPT)   2 = Claude (assinatura da Anthropic)"
pergunta "Digite 1 ou 2" _M '^[12]$' "Digite só 1 ou 2." "1"
[ "$_M" = "2" ] && ENGINE="claude" || ENGINE="codex"

titulo "Tudo certo, começando"
echo "  e-mail: $EMAIL"
echo "  nome:   $NOME"
echo "  voz:    $GENDER"
echo "  motor:  $ENGINE"
[ -n "$DONO" ] && echo "  dono do Telegram: já pareado (não vou pedir de novo)"
echo ""
echo "Agora eu instalo. Pode demorar alguns minutos e vai passar muito texto."
echo "Se aparecer um link com um código, abra o link, entre na sua conta e digite o código."
echo ""

INSTALADOR="$(mktemp /tmp/leon-install.XXXXXX.sh)"
trap 'rm -f -- "$INSTALADOR"' EXIT
curl -fsSL --retry 3 --retry-delay 2 --max-time 120 "$CENTRAL/install-leon.sh" -o "$INSTALADOR" </dev/null \
  || morre "não consegui baixar o instalador (a VPS está sem internet?)."
bash -n "$INSTALADOR" || morre "o instalador baixou corrompido. Rode o mesmo comando de novo."

export LEON_ENGINE="$ENGINE" EMAIL="$EMAIL" NOME="$NOME" GENDER="$GENDER" BOT_TOKEN="$TOKEN"
[ -n "$DONO" ] && export OWNER_CHAT_ID="$DONO"
bash "$INSTALADOR"
RC=$?

if [ "$RC" -eq 0 ]; then
  titulo "PRONTO"
  verde "Manda uma mensagem pro teu bot no Telegram. Ele responde."
else
  vermelho ""
  vermelho "A instalação parou (código $RC). NADA foi perdido: rode o mesmo comando de novo,"
  vermelho "que eu continuo de onde parei. Se repetir, chama o suporte: $SUPORTE"
  exit "$RC"
fi
