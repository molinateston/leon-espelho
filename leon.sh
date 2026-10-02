#!/usr/bin/env bash
# INSTALAÇÃO DO LEON PELO TERMINAL DA VPS, EM UM COMANDO SÓ.
#
# O dono cola UMA linha no Terminal do navegador (Hostinger) e responde o que este
# script perguntar. Nada de editar comando, nada de aspas, nada de WSL.
#
# Uso oficial (o que a página manda colar). 23/09, lei do dono: cliente nenhum depende da VPS
# do dono; o comando sai do GitHub e a central fica de reserva:
#   curl -fsSL https://raw.githubusercontent.com/molinateston/leon-espelho/main/leon.sh | bash
# (o endereço antigo, https://licenca.leonardomolina.com.br/leon.sh, continua valendo.)
# Com licença assinada (LEON_LICENCA_ASSINADA, quando o dono ligar), a instalação inteira sai
# do GitHub, sem a central: cole a licença que chegou na compra em LEON_LICENCA=... antes do bash.
#
# A prova de erro: cada tropeço que um cliente real viveu virou uma trava aqui.
#  - lixo do "colar" do terminal do navegador (^[[200~ e afins): sanitizado em toda leitura.
#  - aspas curvas do WhatsApp/Telegram nos dados colados: convertidas.
#  - dado colado com espaço no fim, quebra de linha, tab: aparados.
#  - e-mail/token/nome errados: validados NA HORA, com nova chance, sem derrubar a instalação.
#  - rodar de novo depois de um tropeço: reaproveita o que já está certo e não repete o pareamento.
#  - motor: pergunta em português, sem jargão, com o padrão pronto no Enter.
set -uo pipefail

SUPORTE="https://wa.me/5511988890934"
CENTRAL="${LEON_CENTRAL:-https://licenca.leonardomolina.com.br}"
ESPELHO="${LEON_ESPELHO:-https://raw.githubusercontent.com/molinateston/leon-espelho/main}"

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

# Sistema: o LEON foi testado em Ubuntu 22.04 e 24.04. Em outro sistema ele
# TENTA assim mesmo, nunca barra na porta. Onde o gestor de pacotes é
# diferente (fora da familia Debian/Ubuntu) pode faltar algo no meio; o dono
# fica avisado e o suporte resolve o resto.
if [ -r /etc/os-release ]; then
  . /etc/os-release
  case "${ID:-}:${VERSION_ID:-}" in
    ubuntu:22.04|ubuntu:24.04) : ;;                       # testado, segue calado
    *)
      if command -v apt-get >/dev/null 2>&1; then
        amarelo "Aviso: ${PRETTY_NAME:-este sistema} não é o testado (Ubuntu 22.04/24.04), mas uso o mesmo gestor de pacotes. Sigo a instalação normalmente."
      else
        amarelo "Aviso: ${PRETTY_NAME:-este sistema} usa outro gestor de pacotes (não é Debian/Ubuntu). Vou tentar mesmo assim; se algum pacote não instalar, chama o suporte: $SUPORTE"
      fi
      ;;
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
# COMANDO PRE-PREENCHIDO (24/08, lei do dono: "ele tem que responder perguntas no
# instalador... nao rola um comando unico?"): a pagina gera o comando com as respostas
# JA DENTRO, por variavel de ambiente. Aqui elas VENCEM o estado de tentativa anterior.
# Validacao continua a mesma logo abaixo: valor invalido cai na pergunta normal.
_ENV_EMAIL="${EMAIL:-}"; _ENV_NOME="${NOME:-}"; _ENV_GENDER="${GENDER:-}"
_ENV_TOKEN="${TOKEN:-${BOT_TOKEN:-}}"; _ENV_ENGINE="${ENGINE:-${LEON_ENGINE:-}}"
EMAIL="$(le_do_env LEON_LICENSE_EMAIL)"; [ -n "$EMAIL" ] || EMAIL="$(le_do_env EMAIL)"; [ -n "$EMAIL" ] || EMAIL="$(le_do_env LICENSE_EMAIL)"
NOME="$(le_do_env AGENT_NAME)"
TOKEN="$(le_do_env TELEGRAM_BOT_TOKEN)"; [ -n "$TOKEN" ] || TOKEN="$(le_do_env BOT_TOKEN)"
GENDER="$(le_do_env AGENT_GENDER)"
# ambiente vence o estado, MAS passa pela MESMA regua das perguntas: valor invalido
# vira vazio e cai na pergunta normal (nunca entra lixo calado).
[ -n "$_ENV_EMAIL" ] && { printf '%s' "$_ENV_EMAIL" | LC_ALL=C grep -qE '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' && EMAIL="$_ENV_EMAIL" || _ENV_EMAIL=""; }
[ -n "$_ENV_NOME" ] && { printf '%s' "$_ENV_NOME" | LC_ALL=C grep -qE '^[^/\\<>|;&$`"'"'"'*?]{1,40}$' && NOME="$_ENV_NOME" || _ENV_NOME=""; }
case "$_ENV_GENDER" in male|female) GENDER="$_ENV_GENDER" ;; *) _ENV_GENDER="" ;; esac
if [ -n "$_ENV_TOKEN" ]; then
  if printf '%s' "$_ENV_TOKEN" | LC_ALL=C grep -qE '^[0-9]{6,}:[A-Za-z0-9_-]{20,}$' \
     && curl -fsS --max-time 20 "https://api.telegram.org/bot$_ENV_TOKEN/getMe" </dev/null 2>/dev/null | grep -q '"ok":true'; then
    TOKEN="$_ENV_TOKEN"
  else
    amarelo "  o token que veio no comando não passou na conferência do Telegram; vou perguntar."
    TOKEN=""
  fi
fi
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
case "$_ENV_ENGINE" in
  claude|codex) ENGINE="$_ENV_ENGINE"; verde "  já tenho: $ENGINE" ;;
  *)
    pergunta "Digite 1 ou 2" _M '^[12]$' "Digite só 1 ou 2." "1"
    [ "$_M" = "2" ] && ENGINE="claude" || ENGINE="codex" ;;
esac

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

# LACRE DO INSTALADOR (01/10): o install-leon.sh só roda se o sha256 dele bater com o
# manifesto-instalador.json ASSINADO pela mesma chave Ed25519 de produção que assina o
# release-manifest (a que o install-leon.sh pina; conferida pela impressão antes do uso).
# GitHub primeiro, central de reserva; cada origem passa pela conferência inteira e, se nenhuma
# passar (adulterado, assinatura errada, arquivo ausente ou vazio, rede), nada roda.
# Sem chave por variável de ambiente, de propósito: um comando colado de fonte falsa não traz a
# própria âncora. A prova troca a chave numa CÓPIA deste arquivo (test/prova-lacre-instalador.cjs).
CHAVE_INSTALADOR='-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAzLQi1On9pdcj/g7Z8WxHxPeTijp0t3yhGnfoZfDzpXI=
-----END PUBLIC KEY-----'
FP_INSTALADOR='eb70521f5e4dd9bb1cd11e6ceb0b2bddd65596558322908a2d04fd3dec5cbe08'
command -v openssl >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 \
  || morre "faltam o openssl ou o sha256sum nesta VPS; sem eles não consigo conferir o instalador. Rode: apt-get install -y openssl coreutils"
LACRE="$(mktemp -d /tmp/leon-install.XXXXXX)" || morre "não consegui criar a pasta temporária em /tmp."
trap 'rm -rf -- "$LACRE"' EXIT
INSTALADOR="$LACRE/install-leon.sh"
printf '%s\n' "$CHAVE_INSTALADOR" > "$LACRE/chave.pem"
[ "$(sha256sum < "$LACRE/chave.pem" | cut -d' ' -f1)" = "$FP_INSTALADOR" ] \
  || morre "a chave de conferência deste comando não bate com a impressão. Baixe o comando de novo da página oficial."
baixa() { curl -fsSL --max-filesize "$3" --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 120 "$1" -o "$2" </dev/null 2>/dev/null && [ -s "$2" ]; }
lacre_origem() {  # <base-url>: 0 só com assinatura e sha conferidos; senão MOTIVO diz o que falhou
  local b="$1" esperado
  rm -f -- "$LACRE/m.json" "$LACRE/m.sig" "$INSTALADOR"
  baixa "$b/manifesto-instalador.json" "$LACRE/m.json" 65536 || { MOTIVO="manifesto do instalador ausente ou vazio"; return 1; }
  baixa "$b/manifesto-instalador.sig" "$LACRE/m.sig" 64 || { MOTIVO="assinatura do manifesto ausente ou vazia"; return 1; }
  openssl pkeyutl -verify -rawin -pubin -inkey "$LACRE/chave.pem" -in "$LACRE/m.json" -sigfile "$LACRE/m.sig" >/dev/null 2>&1 \
    || { MOTIVO="a assinatura do manifesto do instalador não confere"; return 1; }
  esperado="$(sed -n 's/^[[:space:]]*"install-leon\.sh"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{64\}\)".*/\1/p' "$LACRE/m.json" | head -1)"
  [ -n "$esperado" ] || { MOTIVO="o manifesto assinado não cita o install-leon.sh"; return 1; }
  baixa "$b/install-leon.sh" "$INSTALADOR" 8388608 || { MOTIVO="instalador ausente ou vazio"; return 1; }
  [ "$(sha256sum < "$INSTALADOR" | cut -d' ' -f1)" = "$esperado" ] \
    || { MOTIVO="o instalador é diferente do que foi assinado (adulterado ou publicação pela metade)"; return 1; }
}
MOTIVO=""
if lacre_origem "$ESPELHO"; then ORIGEM_INST=github
else
  MOTIVO_GH="$MOTIVO"
  lacre_origem "$CENTRAL" || morre "o instalador NÃO passou na conferência de segurança (GitHub: $MOTIVO_GH; central: $MOTIVO). Por segurança não rodei nada. Espere 10 minutos e rode o mesmo comando de novo."
  ORIGEM_INST=central
  amarelo "  aviso: o GitHub não passou na conferência ($MOTIVO_GH); usei a central, conferida pela assinatura."
fi
bash -n "$INSTALADOR" || morre "o instalador baixou corrompido. Rode o mesmo comando de novo."
echo "  instalador baixado e conferido pela assinatura (origem: $ORIGEM_INST)"

export LEON_ENGINE="$ENGINE" EMAIL="$EMAIL" NOME="$NOME" GENDER="$GENDER" BOT_TOKEN="$TOKEN"
export LEON_ESPELHO="$ESPELHO"
[ -n "$DONO" ] && export OWNER_CHAT_ID="$DONO"
# licença assinada (G3): só atravessa se veio no comando; o instalador confere offline.
if [ -n "${LEON_LICENCA:-}" ]; then export LEON_LICENCA="$(limpa "$LEON_LICENCA")" LEON_LICENCA_ASSINADA=1; fi
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
