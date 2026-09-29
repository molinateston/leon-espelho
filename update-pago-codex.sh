#!/usr/bin/env bash
# Atualizador pago do LEON Codex.
#
# O pacote novo e preparado em um diretorio irmao do runtime. A troca usa
# somente renames no mesmo filesystem. O processo que disparou a atualizacao
# pertence ao cgroup do LEON e pode morrer durante o restart; por isso a prova
# final e o rollback ficam armados em um finalizador de uma execucao no cron.
set -Eeuo pipefail
umask 077
LEON_RELEASE_TRUST_FINGERPRINT='eb70521f5e4dd9bb1cd11e6ceb0b2bddd65596558322908a2d04fd3dec5cbe08'
LEON_NODE_VERSION=22.22.0

write_release_public_key() {
  local output="$1"
  cat > "$output" <<'PEM'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAzLQi1On9pdcj/g7Z8WxHxPeTijp0t3yhGnfoZfDzpXI=
-----END PUBLIC KEY-----
PEM
  [ "$(sha256sum "$output" | awk '{print $1}')" = "$LEON_RELEASE_TRUST_FINGERPRINT" ]
}

semver_ge() {
  "$PYTHON_BIN" - "$1" "$2" <<'PY'
import re, sys
def parse(value):
    # A alternancia PRECISA de grupo: sem ele o "0|" solto casava a string inteira "0"
    # e qualquer versao comecada em zero (0.153.3, 0.147.0) caia como invalida (exit 2).
    # Release do bridge comeca em 2, entao o defeito dormia; versao de CLI e sempre 0.x.
    if not re.fullmatch(r"(?:0|[1-9]\d*)(?:\.(?:0|[1-9]\d*)){2}", value): raise SystemExit(2)
    return tuple(map(int,value.split(".")))
raise SystemExit(0 if parse(sys.argv[1]) >= parse(sys.argv[2]) else 1)
PY
}

read_installed_release_version() {
  local marker="$1"
  "$PYTHON_BIN" - "$marker" <<'PY'
import os, re, stat, sys
path=sys.argv[1]
try:
    seen=os.lstat(path)
except FileNotFoundError:
    print("0.0.0")
    raise SystemExit(0)
except OSError:
    raise SystemExit(1)
try:
    if not stat.S_ISREG(seen.st_mode) or seen.st_nlink != 1 or seen.st_size > 64: raise ValueError()
    fd=os.open(path,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0))
    try: before=os.fstat(fd); raw=os.read(fd,65); after=os.fstat(fd)
    finally: os.close(fd)
    if (seen.st_dev,seen.st_ino)!=(before.st_dev,before.st_ino): raise ValueError()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1: raise ValueError()
    if (before.st_dev,before.st_ino,before.st_size)!=(after.st_dev,after.st_ino,after.st_size) or after.st_nlink != 1: raise ValueError()
    value=raw.decode("ascii").strip()
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)",value): raise ValueError()
except Exception: raise SystemExit(1)
print(value)
PY
}

release_marker_lstat_state() {
  "$PYTHON_BIN" - "$1" <<'PY'
import os,sys
try:
    os.lstat(sys.argv[1])
except FileNotFoundError:
    print("absent")
except OSError:
    raise SystemExit(1)
else:
    print("present")
PY
}

read_installed_release_identity() {
  local runtime="$1" marker="$1/.leon-release.json" legacy="$1/.leon-release-version" legacy_version marker_state
  marker_state="$(release_marker_lstat_state "$marker")" || return 1
  if [ "$marker_state" = "absent" ]; then
    legacy_version="$(read_installed_release_version "$legacy")" || return 1
    printf '%s\t\n' "$legacy_version"
    return 0
  fi
  [ "$marker_state" = "present" ] || return 1
  "$PYTHON_BIN" - "$marker" <<'PY'
import json, os, re, stat, sys
path=sys.argv[1]
try:
    seen=os.lstat(path)
    if not stat.S_ISREG(seen.st_mode) or seen.st_nlink!=1 or seen.st_size>512: raise ValueError()
    if seen.st_uid!=os.getuid() or stat.S_IMODE(seen.st_mode)&0o077: raise ValueError()
    fd=os.open(path,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0))
    try: before=os.fstat(fd); raw=os.read(fd,513); after=os.fstat(fd)
    finally: os.close(fd)
    if (seen.st_dev,seen.st_ino)!=(before.st_dev,before.st_ino): raise ValueError()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1: raise ValueError()
    if (before.st_dev,before.st_ino,before.st_size)!=(after.st_dev,after.st_ino,after.st_size) or after.st_nlink!=1 or len(raw)!=before.st_size: raise ValueError()
    value=json.loads(raw)
    if set(value)!={"version","manifestSha256"}: raise ValueError()
    version=value["version"]; digest=value["manifestSha256"]
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)",version): raise ValueError()
    if not re.fullmatch(r"[0-9a-f]{64}",digest): raise ValueError()
except Exception: raise SystemExit(1)
print(f"{version}\t{digest}")
PY
}

release_identity_acceptable() {
  "$PYTHON_BIN" - "$1" "$2" "$3" "$4" <<'PY'
import re,sys
candidate,candidate_digest,installed,installed_digest=sys.argv[1:]
def semver(value):
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)",value): raise SystemExit(2)
    return tuple(map(int,value.split(".")))
new,old=semver(candidate),semver(installed)
if new>old: raise SystemExit(0)
if new<old: raise SystemExit(1)
raise SystemExit(0 if installed_digest and candidate_digest==installed_digest else 1)
PY
}

write_release_identity() {
  local destination="$1" release_version="$2" release_digest="$3"
  printf '{"manifestSha256":"%s","version":"%s"}\n' "$release_digest" "$release_version" > "$destination"
  chmod 0600 "$destination"
}

# MANIFESTO DE INTEGRIDADE DO RUNTIME (camada tecnica da lei "o agente nao mexe no
# proprio codigo"). Grava o sha256 de cada arquivo do motor no momento em que a release
# entra no disco. O bridge confere isso no boot e avisa o dono se algo divergir.
#
# Cobre o codigo que EXECUTA, e so ele. Estado que muda em uso legitimo (.env,
# sessions.json, topics.json, brain, estado do onboarding) fica de fora de proposito:
# incluir arquivo que muda sozinho produziria alarme falso todo boot, e alarme falso
# ensina o dono a ignorar o alarme.
write_runtime_files_manifest() {
  # `local a="$1" b="$a/x"` NAO enxerga o $a da mesma linha: o b sai como "/x" e o
  # manifesto ia parar na raiz do disco. Duas linhas, de proposito.
  local stage="$1"
  local destination="$stage/.leon-runtime-files.sha256"
  local rel
  : > "$destination"
  for rel in bridge.cjs capabilities.json \
    appserver/adapter.cjs appserver/index.cjs \
    lib-motores/codex-appserver.cjs lib/onboarding.js lib/meta-connect.js lib/meta-graph.js lib/license.js \
    workers/piper.js workers/edge-tts.js workers/hostinger-health.cjs; do
    [ -f "$stage/$rel" ] && [ ! -L "$stage/$rel" ] || continue
    printf '%s  %s\n' "$(sha256sum "$stage/$rel" | awk '{print $1}')" "$rel" >> "$destination"
  done
  chmod 0600 "$destination"
}

verify_signed_artifact() {
  local artifact="$1" expected_hash="$2" expected_bytes="$3" label="$4"
  "$PYTHON_BIN" - "$artifact" "$expected_hash" "$expected_bytes" <<'PY' \
    || fatal "$label difere do artefato assinado; runtime preservado."
import hashlib,os,stat,sys
path,expected_hash,expected_bytes=sys.argv[1],sys.argv[2],int(sys.argv[3])
try:
    seen=os.lstat(path)
    if not stat.S_ISREG(seen.st_mode) or seen.st_nlink!=1 or seen.st_size!=expected_bytes: raise ValueError()
    fd=os.open(path,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0))
    try:
        before=os.fstat(fd); digest=hashlib.sha256()
        while True:
            block=os.read(fd,1024*1024)
            if not block: break
            digest.update(block)
        after=os.fstat(fd)
    finally: os.close(fd)
    if (seen.st_dev,seen.st_ino)!=(before.st_dev,before.st_ino): raise ValueError()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or before.st_size!=expected_bytes: raise ValueError()
    if (before.st_dev,before.st_ino,before.st_size)!=(after.st_dev,after.st_ino,after.st_size) or after.st_nlink!=1: raise ValueError()
    if digest.hexdigest()!=expected_hash: raise ValueError()
except Exception: raise SystemExit(1)
PY
}

validate_download_file() {
  local artifact="$1" max_bytes="$2" exact_bytes="${3:-}"
  "$PYTHON_BIN" - "$artifact" "$max_bytes" "$exact_bytes" <<'PY'
import os,stat,sys
path,max_bytes,exact=sys.argv[1],int(sys.argv[2]),sys.argv[3]
try:
    seen=os.lstat(path)
    if not stat.S_ISREG(seen.st_mode) or seen.st_nlink!=1 or seen.st_size>max_bytes: raise ValueError()
    if seen.st_uid!=os.getuid() or stat.S_IMODE(seen.st_mode)&0o077: raise ValueError()
    if exact and seen.st_size!=int(exact): raise ValueError()
    fd=os.open(path,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0))
    try: before=os.fstat(fd); raw=os.read(fd,max_bytes+1); after=os.fstat(fd)
    finally: os.close(fd)
    if (seen.st_dev,seen.st_ino)!=(before.st_dev,before.st_ino): raise ValueError()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or before.st_size>max_bytes: raise ValueError()
    if (before.st_dev,before.st_ino,before.st_size)!=(after.st_dev,after.st_ino,after.st_size) or after.st_nlink!=1 or len(raw)!=before.st_size: raise ValueError()
except Exception: raise SystemExit(1)
PY
}

verify_release_manifest() {
  local manifest="$1" signature="$2" public_key="$3" metadata="$4"
  write_release_public_key "$public_key" || return 1
  openssl pkeyutl -verify -rawin -pubin -inkey "$public_key" \
    -in "$manifest" -sigfile "$signature" >/dev/null 2>&1 || return 1
  "$PYTHON_BIN" - "$manifest" "$LEON_RELEASE_TRUST_FINGERPRINT" > "$metadata" <<'PY'
import json,re,sys
manifest,fingerprint=sys.argv[1:]
try: data=json.load(open(manifest,encoding="utf-8"))
except Exception: raise SystemExit(1)
if set(data)!={"schema","kind","channel","version","minVersion","codexCliVersion","nodeVersion","keyFingerprint","artifacts"}: raise SystemExit(1)
if data["schema"]!=2 or data["kind"]!="leon-codex-release" or data["channel"]!="stable": raise SystemExit(1)
if data["keyFingerprint"]!=fingerprint: raise SystemExit(1)
version_re=re.compile(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)")
if not version_re.fullmatch(str(data["version"])) or not version_re.fullmatch(str(data["minVersion"])): raise SystemExit(1)
# codexCliVersion virou MINIMA (nao mais versao exata cravada): a casa que roda um CLI
# igual ou mais novo sobe normal. Continua obrigatoriamente um semver assinado pela central.
# Node segue cravado: e o runtime que o pacote realmente exige, nao um piso.
if not version_re.fullmatch(str(data["codexCliVersion"])) or data["nodeVersion"]!="22.22.0": raise SystemExit(1)
artifacts=data["artifacts"]
if set(artifacts)!={"base","bundle","skills","updater"}: raise SystemExit(1)
expected={
 "base":("leon-base-curated.tar.gz","/download-codex",True),
 "bundle":("leon-codex-appserver-v2.tar.gz","/leon-codex-appserver-v2.tar.gz",False),
 "skills":("leon-skills-codex-minimal.tar.gz","/leon-skills-codex-minimal.tar.gz",False),
 "updater":("update-pago-codex.sh","/update-pago-codex.sh",False),
}
print("version="+data["version"]); print("minVersion="+data["minVersion"]); print("channel="+data["channel"]); print("codexCliVersion="+data["codexCliVersion"]); print("nodeVersion="+data["nodeVersion"])
for key,(name,url,licensed) in expected.items():
    item=artifacts[key]
    if set(item)!={"file","url","sha256","bytes","licensed"}: raise SystemExit(1)
    if item["file"]!=name or item["url"]!=url or item["licensed"] is not licensed: raise SystemExit(1)
    if not re.fullmatch(r"[0-9a-f]{64}",str(item["sha256"])) or not isinstance(item["bytes"],int) or not 1<=item["bytes"]<=536_870_912: raise SystemExit(1)
    print(f"{key}_sha256={item['sha256']}"); print(f"{key}_bytes={item['bytes']}"); print(f"{key}_url={item['url']}")
PY
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${BASH_SOURCE[0]}"
TEST_MODE="${LEON_UPDATE_TEST_MODE:-0}"
FINALIZE_MODE=0
[ "${1:-}" = "--finalize" ] && FINALIZE_MODE=1

INSTALL_DIR="${LEON_INSTALL_DIR:-$SELF}"
SERVICE="${LEON_SERVICE:-leon-agente.service}"
SYSTEMCTL=/bin/systemctl
CURL_BIN=curl
CRONTAB_BIN="crontab"
NODE_BIN=""
PYTHON_BIN="python3"
if [ "$TEST_MODE" = "1" ]; then
  SYSTEMCTL="${LEON_SYSTEMCTL:-$SYSTEMCTL}"
  CURL_BIN="${LEON_CURL_BIN:-$CURL_BIN}"
  CRONTAB_BIN="${LEON_CRONTAB_BIN:-$CRONTAB_BIN}"
  NODE_BIN="${LEON_NODE_BIN:-}"
  PYTHON_BIN="${LEON_PYTHON_BIN:-$PYTHON_BIN}"
fi

# 02/set (feature-detect, achado do Fable): --retry-all-errors só existe em curl >= 7.71 (2020).
# Em curl velho (Ubuntu 20.04 tem 7.68, Debian 10 tem 7.64), passar essa opção DERRUBA o curl com
# exit 2 ANTES de tocar a rede — mataria TODO /atualiza permanente, mudo, no cliente com curl antigo,
# e o instalador não bloqueia OS velho. Detecto UMA vez (sem rede, --version). Se o curl suporta,
# CURL_RETRY_ALL="--retry-all-errors"; senão fica VAZIO. Nos curls de download uso $CURL_RETRY_ALL
# SEM ASPAS de propósito: em curl velho expande pra nada = comportamento antigo, que funcionava.
# NÃO botar aspas aqui — aspas virariam um argumento vazio "" que o curl também rejeita.
CURL_RETRY_ALL=""
if "$CURL_BIN" --retry-all-errors --version >/dev/null 2>&1; then
  CURL_RETRY_ALL="--retry-all-errors"
fi

if [ "$(id -u)" -eq 0 ] && [ "$TEST_MODE" != "1" ]; then
  printf 'ERRO: o atualizador deve rodar como o usuário do LEON, nunca como root.\n' >&2
  exit 1
fi
if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ] || [ -L "$HOME" ]; then
  printf 'ERRO: HOME do usuário LEON ausente, inválido ou simbólico.\n' >&2
  exit 1
fi
cd -- "$HOME" || {
  printf 'ERRO: não foi possível entrar no HOME do usuário LEON.\n' >&2
  exit 1
}

if ! printf %s "$SERVICE" | grep -qE '^[A-Za-z0-9_.@-]+\.service$'; then
  printf 'ERRO: nome de servico invalido.\n' >&2
  exit 1
fi

service_read() {
  "$SYSTEMCTL" "$@"
}

service_write() {
  if [ "$TEST_MODE" = "1" ] || [ "$(id -u)" -eq 0 ]; then
    "$SYSTEMCTL" "$@"
  else
    sudo -n "$SYSTEMCTL" "$@"
  fi
}

# 24/09 (rodada 3): o leitor e o do bridge (leon_preserva env-valor, RE_KV). O grep '^CHAVE='
# de antes nao via 'CODEX_BIN = /opt/meu-codex/bin/codex' (espaco em volta do '=', que o bridge
# aceita), devolvia vazio e o /atualiza trocava o binario proprio do dono pelo do produto.
env_get_from() {
  local file="$1" key="$2"
  leon_preserva env-valor "$file" "$key" 2>/dev/null || true
}

# Lê uma única chave do .env pelo mesmo fd validado. Notificações e smokes
# acontecem depois de renames; nunca voltamos a abrir o caminho com grep, nem
# deixamos uma cópia temporária contendo o token em caso de sinal/crash.
# 24/09 (rodada 5, LEITOR UNICO): as guardas de arquivo e o leitor sao os do leon_preserva
# (env-valor-seguro): aspas, comentario no fim, espaco em volta do '=', CRLF e BOM na primeira
# linha saem como o bridge le. Linha fora do formato ou chave repetida: sai 1.
safe_env_value() {
  local file="$1" key="$2"
  leon_preserva env-valor-seguro "$file" "$key"
}

# >>> LEON-PRESERVA v1 (fonte unica: instalador/preserva-casa.py; a prova confere byte a byte)
leon_preserva() {
  "${PYTHON_BIN:-python3}" - "$@" <<'LEON_PRESERVA_PY'
# LEON-PRESERVA v1 (23/09): o que e do dono fica como o dono deixou.
#
# FONTE UNICA. Este arquivo e copiado BYTE A BYTE para dentro de update-pago-codex.sh,
# install-leon.sh e install-codex.sh (funcao leon_preserva, heredoc LEON_PRESERVA_PY), porque
# os tres sao baixados sozinhos e nao enxergam arquivo vizinho. test/prova-preserva-estrutural.sh
# confere que as tres copias sao identicas a este arquivo.
#
# LEI DO DONO: atualizar ou reinstalar NUNCA apaga, esconde ou troca integracao, configuracao,
# escolha ou contexto do cliente. Tres reprovacoes da mesma classe (filtro por allowlist na
# escrita, bloco gerenciado que vencia o dono, #LEON-GUARDADO que tirava a chave do ar)
# trocaram o desenho: o arquivo do dono e a BASE e o produto so ACRESCENTA.
#
# SUBCOMANDOS
#   env-acrescenta ENV PADROES TROCAS SAIDA RELATORIO [LEON_DATA_DIR]
#       .env: toda linha do dono sai byte a byte. So entra no FIM a chave que falta, com o
#       padrao do produto (ou com o valor que uma versao velha escondeu em #LEON-GUARDADO).
#       A unica excecao e PRODUTO_ENV abaixo, e so quando o chamador provou que o valor atual
#       e invalido (ele passa a chave em TROCAS). Saida 3 = o .env do dono tem linha que o
#       bridge recusaria; nada e escrito e o chamador para sem mexer em nada.
#       CODEX_BIN em TROCAS so troca quando o valor atual, lido como o bridge le, esta vazio ou
#       dentro de <LEON_DATA_DIR>/codex-cli (o chamador passa LEON_DATA_DIR). Sem LEON_DATA_DIR,
#       ou com binario do dono fora dessa pasta, a linha do dono fica (relatorio: binario-do-dono).
#   home-do-motor ENV MOTOR PADRAO
#       A pasta que o bridge usa HOJE pro motor (codex ou claude), na ordem do homeDoMotor do
#       bridge.cjs: a chave do .env (CODEX_HOME / CLAUDE_CONFIG_DIR); senao ~/.<motor> quando
#       tem credencial (auth.json ou .credentials.json); senao PADRAO. Sem .env (instalacao do
#       zero) sai PADRAO. Os tres escritores gravam ISTO quando a chave falta num .env que ja
#       existe: gravar a pasta do LEON mudaria a casa do login e dos MCPs do dono.
#   toml-funde ATUAL MOLDE SAIDA RELATORIO RUNTIME
#       config.toml do Codex no CODEX_HOME do LEON: o texto do dono e a base. Chave ou tabela
#       que so o dono tem fica byte a byte; nas que os dois declaram vale o dono; o molde so
#       acrescenta o que falta. Excecao: SEGURANCA_* abaixo. Saida 3 = o chamador mantem o
#       arquivo do dono INTACTO (a seguranca nao cabe sem reescrever estrutura do dono; o python
#       nao tem leitor TOML; ou o tomllib recusa mas o Codex pinado le, como BOM no comeco ou
#       tabela inline em varias linhas do TOML 1.1). Saida 2 = ilegivel DE VERDADE: o tomllib
#       recusa E o Codex pinado tambem recusa (LEON_PRESERVA_CODEX = binario do Codex,
#       LEON_PRESERVA_PATH = PATH com o node dele). Sem Codex pra julgar nao sai 2: sai 3.
#       BOM UTF-8 no comeco: analisa sem ele e devolve o arquivo com ele.
#   env-valor ENV CHAVE
#       Le UMA chave do jeito que o bridge le (comentario no fim e aspas saem, espaco em volta do
#       '=', CRLF, BOM na primeira linha). Todo leitor dos escritores usa isto: valor com aspas ou
#       comentario e escolha valida do dono.
#   env-valor-seguro ENV CHAVE
#       O mesmo leitor, sobre o arquivo aberto uma vez so com as guardas do bridge (arquivo
#       comum, 0600 sem grupo/outros, dono = quem roda, nlink 1, ate 256 KiB, sem troca no meio).
#       Linha fora do formato ou chave repetida = sai 1 (o bridge recusaria o arquivo inteiro).
#   env-exporta ENV
#       'export CHAVE=<valor com aspas de shell>' pra cada chave ativa, lido como o bridge le. E o
#       que o vigia do /atualiza avalia antes de disparar o atualizador (a linha crua exportada
#       levava aspas e comentario literais pro atualizador). .env que o bridge recusaria: nada.
#   bases-do-dono ENV HOME [CHAVE=valor ...]
#       LEITOR UNICO DAS PASTAS (24/09, rodada 5). Imprime 'CHAVE=<valor com aspas de shell>' pras
#       pastas que o bridge deriva do LEON_DATA_DIR, na ORDEM do bridge: (1) LEON_DATA_DIR do .env
#       (senao HOME/.leon); (2) BRAIN_DIR do .env ou <dados>/brain, e dele MEMVIVA_FILE e
#       ASSUNTOS_FILE; (3) LEON_STATE_DIR do .env ou <dados>/state, e dele LEON_MISSIONS_DIR e
#       LEON_PROMISES_DIR; (4) PERSONA_DIR; e LEON_SKILLS_PESSOAIS_DIR, LEON_TMPDIR,
#       LEON_MISSION_OUTPUT_DIR, LEON_WORK_AREA, LEON_SKILLS_DIR (vazio quando o .env nao declara:
#       o padrao do catalogo e de cada escritor). Com .env existente vale SO o .env (o bridge apaga
#       do ambiente toda chave da allowlist antes de ler o .env); os CHAVE=valor do chamador so
#       valem na instalacao do zero (sem .env). A funcao de shell leon_bases_do_dono (no mesmo
#       bloco embutido) avalia esta saida no topo de cada escritor e no finalizador.
#   skills-do-dono BACKUP CATALOGO_NOVO PESSOAIS [REGISTRO]
#       Antes de apagar backup de catalogo: toda entrada do backup que nao e do produto vai
#       para skills-pessoais; dentro de pasta com nome do produto, arquivo que nao existe na
#       mesma pasta do catalogo novo vai para skills-pessoais/<nome>.catalogo-antigo-N/.
#       REGISTRO = arquivo com o digest do catalogo que o produto instalou (skills-registra).
#       Backup igual ao registro = catalogo intocado, sai 0 sem copiar nada. Registro ausente
#       ou diferente = alguem mexeu (ate a 2.4.48 o LEON podia editar o catalogo): sai 10.
#       Saida 10 = o backup tem coisa do dono (NUNCA apagar o backup).
#   skills-registra CATALOGO REGISTRO
#       Grava o digest do catalogo que o produto acabou de instalar (depois da saude aprovada).
#   codex-home-do-dono ENV LEON_DATA_DIR
#       Sai 0 quando o CODEX_HOME da casa e do dono: o .env declara outra pasta, ou nao declara
#       nenhuma e ~/.codex tem credencial (o bridge usa o ~/.codex do dono), ou a pasta do
#       LEON e link (ou passa por link) pra outro lugar, ou o config.toml dela e link. Nesses
#       casos o produto nao escreve config.toml nenhum (merge atraves de link escreveria no
#       ~/.codex pessoal do dono). Sai 1 = pasta do LEON de verdade.
import hashlib
import json
import math
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time

try:
    import tomllib as _toml
except ImportError:  # Python 3.10 e 3.9 (Ubuntu 22.04, Debian 11): o instalador garante o tomli
    try:
        import tomli as _toml
    except ImportError:
        _toml = None

# ---------------------------------------------------------------------------------------------
# A LISTA EXPLICITA do .env: as UNICAS chaves que o produto pode mudar numa linha que ja existe,
# e so quando o valor atual e invalido (quem prova a invalidez e o chamador; aqui so se recusa
# qualquer chave fora desta lista).
PRODUTO_ENV = {
    "LEON_CODEX_CLI_VERSION": "versao do Codex CLI pinada; muda so quando o CLI da casa ficou abaixo do minimo da release e o atualizador instalou o novo (o velho continua no disco)",
    "CODEX_BIN": "binario pinado do Codex; muda junto com a versao acima, ou quando o caminho atual nao e executavel, e so se ele aponta pra dentro de <LEON_DATA_DIR>/codex-cli (binario proprio do dono fica)",
    "CLAUDE_BIN": "binario do Claude; muda so quando o CLI da casa ficou abaixo do minimo e o atualizador instalou o novo",
    "LEON_MACHINE_ID": "id derivado da maquina (MAC + hostname) que a central usa na ativacao; muda so na reinstalacao, quando nao bate com a maquina onde o instalador roda",
    "LEON_LICENSE_KEY": "chave que a central devolve na ativacao; muda so quando a atual falta, esta malformada ou difere da que a central acabou de devolver",
    "TELEGRAM_BOT_TOKEN": "so na reinstalacao, quando o Telegram recusa o token atual (getMe) e o dono informou outro que o Telegram aceita",
}

# A LISTA EXPLICITA do config.toml: o que o produto precisa por seguranca, contra o dono.
SEGURANCA_DEFINIR = [
    ("approval_policy",),    # o bridge decide aprovacao por thread; o config fora da ponte nunca pergunta menos que o produto
    ("sandbox_mode",),       # danger-full-access (decisao do dono 04/09); outro modo mata o Codex no bwrap
    ("allow_login_shell",),  # shell de login leria o .profile do usuario com segredo
]
SEGURANCA_DEFINIR_PREFIXO = [("shell_environment_policy", "filters")]  # segredo nunca vaza pro shell do Codex
SEGURANCA_REMOVER = [("default_permissions",), ("permissions",), ("sandbox_workspace_write",)]  # perfil nomeado liga o bwrap e o Codex morre (provado no 99)
GERENCIADO = [("mcp_servers", "meta-ads")]  # modo filtro do produto; a url crua expunha 106 ferramentas com escrita
# O gerenciado so troca pelo bloco do molde quando o MOLDE declara o bloco. Molde sem o bloco
# (o molde nao achou o token) e o dono com o bloco do filtro do produto (command node, args
# terminando em meta-mcp-codex-filter.cjs): o bloco do dono FICA. Qualquer outro bloco
# meta-ads do dono (url crua) sai, que e o motivo do gerenciado existir.
FILTRO_META = "meta-mcp-codex-filter.cjs"
# Mais: ("projects", <pasta do runtime>, "trust_level") = "untrusted". O runtime nunca e confiavel.

# Nomes que o catalogo do PRODUTO ja teve (tarballs publicados 2.0.14 a 2.6.8, repositorio
# molinateston/soft inteiro). Entrada de catalogo antigo com outro nome e do dono.
PRODUTO_SKILLS = set("""
.claude-plugin .fonte-unica-sha .git LICENSE OFICINA-TESTE-DE-OBEDIENCIA.md README.md SKILLS-MANIFEST.json
_fonte canvas-design docx pdf pptx scripts skill-creator skills-manifest.json synced xlsx
soft-apostila soft-apresentacao soft-atendimento-reclamacao soft-atendimento-triagem soft-consultoria-instagram
soft-conteudo soft-conteudo-carrossel soft-conteudo-headlines soft-conteudo-impulsionar soft-conteudo-multiplataforma
soft-conteudo-planner soft-conteudo-reels soft-conteudo-stories soft-contratos-consultoria soft-criativo-campeao
soft-critico-copy soft-designer soft-editor-video soft-email-sequencia soft-exportar-documentos soft-financeiro
soft-funil soft-funil-carta soft-funil-isca soft-funil-landing soft-funil-lowticket soft-funil-miniwebinar
soft-funil-nutricao soft-funil-quiz soft-funil-recorrencia soft-funil-recuperacao soft-funil-upsell soft-funil-vsl
soft-gestao-agil soft-google-docs soft-lancamento-pago soft-launch soft-leon soft-members soft-negocio-metricas
soft-organizacao-vps soft-plano-negocio soft-plano-ofertas soft-plano-posicionamento soft-posicionamento
soft-proposta-comercial soft-reel-7seg soft-sdr-kit soft-seo-auditoria soft-sistema soft-trafego-meta soft-treino
soft-treino-dieta soft-tweet-card soft-vendas soft-vendas-call-prep soft-vendas-closer soft-vendas-contratos
soft-vendas-copiloto soft-vendas-estrategias soft-vendas-objecao soft-vendas-outreach soft-vendas-posvenda
soft-vendas-proposta soft-vendas-prospeccao soft-vendas-script soft-vendas-sdr soft-voz-leo-molina soft-webinar
soft-webinar-chat soft-webinar-mensagens soft-webinar-oferta soft-webinar-paginas soft-webinar-plano
soft-webinar-script soft-webinar-slides soft-webinario
""".split())

RE_KV = re.compile(r"^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$")                      # o mesmo do bridge
RE_GUARDADO = re.compile(r"^#LEON-GUARDADO fora-da-allowlist ([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$")
RE_ESTRITO = re.compile(r"""^\s*LEON_ENV_ESTRITO\s*=\s*["']?1["']?\s*(?:#.*)?$""")


def grava(caminho, dados, modo=0o600):
    temp = caminho + ".preserva-new"
    try:
        os.unlink(temp)
    except FileNotFoundError:
        pass
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), modo)
    try:
        os.write(fd, dados)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.chmod(temp, modo)
    os.replace(temp, caminho)


BOM_ENV = "\ufeff"


def linhas_do_env(texto):
    """As linhas como o bridge ve: o espaco do regex do JavaScript engole o U+FEFF no comeco da linha 1.
    So a LEITURA tira o BOM; quem escreve devolve o arquivo com ele (byte a byte)."""
    if texto.startswith(BOM_ENV):
        texto = texto[len(BOM_ENV):]
    return texto.split("\n")


def valor_do_bridge(bruto):
    v = re.sub(r"\s+#.*$", "", bruto).strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1]
    return v


def confere_env(linhas):
    """As mesmas recusas do readSafeEnvFile do bridge. Devolve (problemas, ativas)."""
    problemas, ativas = [], {}
    for i, l in enumerate(linhas):
        if not l.strip() or re.match(r"^\s*#", l):
            continue
        m = RE_KV.match(l)
        if not m:
            problemas.append("formato linha:%d" % (i + 1))
            continue
        k = m.group(1)
        if k in ativas:
            problemas.append("repetida %s" % k)
            continue
        v = valor_do_bridge(m.group(2))
        if re.search(r"[\r\n\x00]", v) or len(v) > 8192:
            problemas.append("valor %s" % k)
        ativas[k] = i
    return problemas, ativas


def le_pares(caminho):
    pares = []
    if caminho and os.path.exists(caminho):
        for l in open(caminho, encoding="utf-8").read().split("\n"):
            if not l.strip():
                continue
            k, sep, v = l.partition("=")
            if not sep or not re.fullmatch(r"[A-Z][A-Z0-9_]*", k):
                raise SystemExit("par invalido em " + caminho)
            pares.append((k, v))
    return pares


def valor_ativo(env, chave):
    """Valor da chave como o bridge le (None = nao declarada)."""
    achado = None
    if env and os.path.exists(env):
        for l in linhas_do_env(open(env, encoding="utf-8", errors="replace").read()):
            m = RE_KV.match(l) if l.strip() and not re.match(r"^\s*#", l) else None
            if m and m.group(1) == chave:
                achado = valor_do_bridge(m.group(2))
    return achado


def dentro_de(raiz, caminho):
    try:
        r, c = os.path.normpath(os.path.abspath(raiz)), os.path.normpath(os.path.abspath(caminho))
        return os.path.commonpath([r, c]) == r
    except ValueError:
        return False


MOTOR_CHAVE = {"codex": "CODEX_HOME", "claude": "CLAUDE_CONFIG_DIR"}


def tem_credencial(pasta):
    return any(os.path.exists(os.path.join(pasta, n)) for n in ("auth.json", ".credentials.json"))


def home_do_motor(env, motor, padrao):
    """A ordem do homeDoMotor do bridge.cjs (passos 1, 3 e 4). No passo 4 o bridge usa
    <LEON_DATA_DIR do .env>/<motor>: com LEON_DATA_DIR declarado, e ELE que vale (o PADRAO do
    chamador so vale quando o .env nao declara, e ai e <HOME>/.leon/<motor>, o mesmo do bridge)."""
    if not env or not os.path.exists(env):
        return padrao
    declarado = valor_ativo(env, MOTOR_CHAVE[motor])
    if declarado:
        return declarado
    casa = os.environ.get("HOME", "")
    if casa:
        pessoal = os.path.join(casa, "." + motor)
        if tem_credencial(pessoal):
            return pessoal
    dados = valor_ativo(env, "LEON_DATA_DIR")
    if dados:
        return os.path.join(dados, motor)
    return padrao


# Pastas que o bridge deriva do LEON_DATA_DIR (bridge.cjs 2788, 2789, 3705, 3742, 3746, 3747,
# 4403, 4506, 4518, 4593, 4594), na ordem em que ele resolve. Cada uma: (chave, base, sufixo).
BASES_DO_DONO = [
    ("LEON_DATA_DIR", "HOME", ".leon"),
    ("BRAIN_DIR", "LEON_DATA_DIR", "brain"),
    ("MEMVIVA_FILE", "BRAIN_DIR", "MEMORIA-VIVA.md"),
    ("ASSUNTOS_FILE", "BRAIN_DIR", "ASSUNTOS-VIVOS.md"),
    ("LEON_STATE_DIR", "LEON_DATA_DIR", "state"),
    ("LEON_MISSIONS_DIR", "LEON_STATE_DIR", "missions"),
    ("LEON_PROMISES_DIR", "LEON_STATE_DIR", "promises"),
    ("PERSONA_DIR", "LEON_DATA_DIR", "persona"),
    ("LEON_SKILLS_PESSOAIS_DIR", "LEON_DATA_DIR", "skills-pessoais"),
    ("LEON_TMPDIR", "LEON_DATA_DIR", "tmp"),
    ("LEON_MISSION_OUTPUT_DIR", "LEON_DATA_DIR", "mission-output"),
    ("LEON_WORK_AREA", "HOME", "trabalho"),
    ("LEON_SKILLS_DIR", None, None),   # sem padrao aqui: casa Claude e casa Codex divergem
]


def bases_do_dono(env, casa, pares):
    """{chave: pasta} como o bridge resolve pra esta casa. pares = CHAVE=valor do chamador, que
    so valem sem .env (instalacao do zero)."""
    tem_env = bool(env) and os.path.isfile(env)
    do_chamador = {}
    for p in pares:
        k, sep, v = p.partition("=")
        if not sep or k not in {b[0] for b in BASES_DO_DONO}:
            raise SystemExit("par invalido pra bases-do-dono: " + k)
        do_chamador[k] = v
    r = {"HOME": casa}
    for k, base, sufixo in BASES_DO_DONO:
        v = (valor_ativo(env, k) or "") if tem_env else do_chamador.get(k, "")
        if k == "LEON_SKILLS_PESSOAIS_DIR" and v:
            v = re.sub(r"^\$LEON_DATA_DIR(?=/|$)", lambda _m: r["LEON_DATA_DIR"], v)   # bridge 4404
        if not v and base:
            v = os.path.join(r[base], sufixo)
        r[k] = v
    del r["HOME"]
    return r


def env_acrescenta(env, padroes_arq, trocas_arq, saida, relatorio, data_dir=""):
    bruto = open(env, "rb").read() if os.path.exists(env) else b""
    rel = []
    try:
        texto = bruto.decode("utf-8")
    except UnicodeDecodeError:
        texto = None
    if texto is None or "\x00" in texto:
        open(relatorio, "w").write("recusa arquivo-nao-e-texto-utf8\n")
        return 3
    bom = BOM_ENV if texto.startswith(BOM_ENV) else ""
    linhas = linhas_do_env(texto)
    problemas, ativas = confere_env(linhas)
    if problemas:
        open(relatorio, "w").write("".join("recusa %s\n" % p for p in problemas))
        return 3
    estrito = any(RE_ESTRITO.match(l) for l in linhas)
    guardadas = {}
    for l in linhas:
        g = RE_GUARDADO.match(l)
        if g and g.group(1) not in ativas:
            guardadas[g.group(1)] = g.group(2)
    padroes, trocas = le_pares(padroes_arq), le_pares(trocas_arq)
    fora = [k for k, _ in trocas if k not in PRODUTO_ENV]
    if fora:
        raise SystemExit("troca pedida fora da lista do produto: " + " ".join(fora))
    if "CODEX_BIN" in ativas:
        # binario do dono fica: a troca so vale com o valor atual (lido como o bridge le) vazio
        # ou dentro de <LEON_DATA_DIR>/codex-cli. Sem LEON_DATA_DIR nao ha como provar: fica.
        atual_bin = valor_do_bridge(RE_KV.match(linhas[ativas["CODEX_BIN"]]).group(2))
        if atual_bin and not (data_dir and dentro_de(os.path.join(data_dir, "codex-cli"), atual_bin)):
            # binario do dono: a versao pinada anda junto com ele (24/09, rodada 5). Trocar so a
            # versao deixava o .env dizendo um CLI e rodando outro.
            if any(k in ("CODEX_BIN", "LEON_CODEX_CLI_VERSION") for k, _ in trocas):
                rel.append("binario-do-dono CODEX_BIN")
            trocas = [(k, v) for k, v in trocas if k not in ("CODEX_BIN", "LEON_CODEX_CLI_VERSION")]
    novas = []
    feitas = set()
    for k, v in trocas:
        if k in ativas:
            i = ativas[k]
            m = RE_KV.match(linhas[i])
            # o mesmo valor como o bridge le (aspas, comentario no fim) nao e troca: a linha fica
            if valor_do_bridge(m.group(2)) != valor_do_bridge(v):
                linhas[i] = k + "=" + v
                rel.append("trocada " + k)
        elif k not in feitas:
            novas.append(k + "=" + v)
            rel.append("nova " + k)
        feitas.add(k)
    for k, v in padroes:
        if k in ativas or k in feitas:
            if k in ativas and k not in feitas and valor_do_bridge(RE_KV.match(linhas[ativas[k]]).group(2)) != valor_do_bridge(v):
                rel.append("escolha-do-dono " + k)
            continue
        feitas.add(k)
        gv = guardadas.get(k)
        if gv is not None and not estrito and not re.search(r"[\r\n\x00]", gv) and len(gv) <= 8192:
            novas.append(k + "=" + gv)
            rel.append("religada " + k)
        else:
            novas.append(k + "=" + v)
            rel.append("nova " + k)
    if not estrito:
        for k, gv in guardadas.items():
            if k in feitas or re.search(r"[\r\n\x00]", gv) or len(gv) > 8192:
                continue
            feitas.add(k)
            novas.append(k + "=" + gv)
            rel.append("religada " + k)
    corpo = "\n".join(linhas)
    if novas:
        if corpo and not corpo.endswith("\n"):
            corpo += "\n"
        corpo += "# LEON %s: chaves que faltavam neste .env (nenhuma linha acima foi mudada)\n" % time.strftime("%Y-%m-%d", time.gmtime())
        corpo += "".join(n + "\n" for n in novas)
    p2, _ = confere_env(corpo.split("\n"))
    if p2:
        raise SystemExit("o .env acrescido nao passaria no bridge: " + " ".join(p2))
    grava(saida, (bom + corpo).encode("utf-8"))
    open(relatorio, "w").write("".join(r + "\n" for r in rel))
    return 0


# ------------------------------------------------------------------------- config.toml --------
class Ilegivel(Exception):
    pass


BOM = "\ufeff"


def codex_le(texto):
    """O Codex pinado le este config? True/False; None = nao ha Codex pra julgar."""
    codex = os.environ.get("LEON_PRESERVA_CODEX", "")
    if not codex or not os.path.isfile(codex) or not os.access(codex, os.X_OK):
        return None
    tmp = tempfile.mkdtemp(prefix="leon-juiz-codex-")
    try:
        grava(os.path.join(tmp, "config.toml"), texto.encode("utf-8"))
        env = {"PATH": os.environ.get("LEON_PRESERVA_PATH") or os.environ.get("PATH", "/usr/bin:/bin"),
               "HOME": os.environ.get("HOME", tmp), "CODEX_HOME": tmp, "LANG": "C.UTF-8"}
        try:
            r = subprocess.run([codex, "mcp", "list"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, env=env, timeout=90)
        except (OSError, subprocess.TimeoutExpired):
            return None
        return r.returncode == 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def carrega(texto):
    if _toml is None:
        raise Ilegivel("sem tomllib/tomli")
    try:
        return _toml.loads(texto)
    except Exception as e:  # noqa: BLE001
        raise Ilegivel(str(e))


def le_chave(s, pos):
    """Chave TOML (bare, "basica" ou 'literal', com pontos). Devolve (partes, pos depois)."""
    partes = []
    n = len(s)
    while True:
        while pos < n and s[pos] in " \t":
            pos += 1
        if pos < n and s[pos] == '"':
            j = pos + 1
            while j < n and s[j] != '"':
                j += 2 if s[j] == "\\" else 1
            # a chave "basica" e decodificada pelo proprio leitor TOML (\U0001F600, \e...): o
            # json.loads de antes estourava ValueError e o escritor saia 1 no meio
            try:
                partes.append(next(iter(carrega(s[pos:j + 1] + " = 0"))))
            except (Ilegivel, StopIteration) as e:
                raise Ilegivel("chave %s" % e)
            pos = j + 1
        elif pos < n and s[pos] == "'":
            j = s.find("'", pos + 1)
            if j < 0:
                raise Ilegivel("chave literal sem fim")
            partes.append(s[pos + 1:j])
            pos = j + 1
        else:
            m = re.compile(r"[A-Za-z0-9_-]+").match(s, pos)
            if not m:
                raise Ilegivel("chave")
            partes.append(m.group(0))
            pos = m.end()
        while pos < n and s[pos] in " \t":
            pos += 1
        if pos < n and s[pos] == ".":
            pos += 1
            continue
        return tuple(partes), pos


def declaracoes(texto):
    """Quebra o texto em declaracoes (cabecalho, chave=valor, vazio/comentario), com as linhas."""
    linhas = texto.split("\n")
    out, tabela, em_aot = [], (), False
    i, n = 0, len(linhas)
    while i < n:
        s = linhas[i].strip()
        if not s or s.startswith("#"):
            out.append({"k": "vazio", "ini": i, "fim": i})
            i += 1
            continue
        j, buf = i, linhas[i]
        while True:
            try:
                carrega(buf)
                break
            except Ilegivel:
                j += 1
                if j >= n:
                    raise Ilegivel("linha %d" % (i + 1))
                buf += "\n" + linhas[j]
        if s.startswith("[["):
            caminho, _ = le_chave(s, 2)
            out.append({"k": "aot", "ini": i, "fim": j, "path": caminho})
            tabela, em_aot = caminho, True
        elif s.startswith("["):
            caminho, _ = le_chave(s, 1)
            out.append({"k": "tab", "ini": i, "fim": j, "path": caminho})
            tabela, em_aot = caminho, False
        else:
            rel, _ = le_chave(linhas[i], 0)
            out.append({"k": "kv", "ini": i, "fim": j, "path": tabela + rel, "rel": rel, "aot": em_aot, "tabela": tabela})
        i = j + 1
    return linhas, out


def folhas(d, pre=()):
    r = {}
    for k, v in d.items():
        if isinstance(v, dict):
            sub = folhas(v, pre + (k,))
            if sub:
                r.update(sub)
            else:
                r[pre + (k,)] = {}
        else:
            r[pre + (k,)] = v
    return r


def pega(d, caminho):
    for p in caminho:
        if not isinstance(d, dict) or p not in d:
            return None, False
        d = d[p]
    return d, True


def comeca(caminho, prefixo):
    return caminho[:len(prefixo)] == prefixo


def chave_txt(k):
    return k if re.fullmatch(r"[A-Za-z0-9_-]+", k) else json.dumps(k, ensure_ascii=False)


def valor_txt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if math.isnan(v) or math.isinf(v):
            raise Ilegivel("float")
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "[" + ", ".join(valor_txt(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{ " + ", ".join(chave_txt(k) + " = " + valor_txt(x) for k, x in v.items()) + " }"
    if hasattr(v, "isoformat"):
        return v.isoformat()
    raise Ilegivel("tipo")


def eh_filtro_meta(bloco):
    """O bloco meta-ads no modo filtro do produto: command node, args terminando no filtro."""
    if not isinstance(bloco, dict) or bloco.get("command") != "node":
        return False
    args = bloco.get("args")
    return isinstance(args, list) and bool(args) and isinstance(args[-1], str) and args[-1].endswith(FILTRO_META)


def toml_funde(atual, molde_arq, saida, relatorio, runtime):
    molde_txt = open(molde_arq, encoding="utf-8").read()
    rel = []
    if not os.path.exists(atual) or os.path.getsize(atual) == 0:
        grava(saida, molde_txt.encode("utf-8"))
        open(relatorio, "w").write("novo config.toml do molde\n")
        return 0
    if _toml is None:
        # Python 3.10 sem tomli (Ubuntu 22.04): nao ter leitor nao faz o config do dono ilegivel.
        open(relatorio, "w").write("sem-leitor-toml (python sem tomllib/tomli)\n")
        return 3
    M = carrega(molde_txt)
    bom = ""
    try:
        texto = open(atual, encoding="utf-8").read()
        if texto.startswith(BOM):
            bom, texto = BOM, texto[len(BOM):]
        O = carrega(texto)
    except (Ilegivel, UnicodeDecodeError) as e:
        try:
            cru = open(atual, "rb").read().decode("utf-8")
        except UnicodeDecodeError:
            cru = None
        juiz = codex_le(cru) if cru is not None else False
        if juiz is True:
            open(relatorio, "w").write("o-codex-le (o leitor TOML do python recusa: %s)\n" % str(e)[:100])
            return 3
        if juiz is None:
            open(relatorio, "w").write("sem-codex-pra-julgar (o leitor TOML do python recusa: %s)\n" % str(e)[:100])
            return 3
        open(relatorio, "w").write("ilegivel %s\n" % str(e)[:120])
        return 2
    try:
        linhas, decl = declaracoes(texto)
    except (Ilegivel, ValueError) as e:
        # o tomllib leu o arquivo do dono; quem nao fechou foi a nossa leitura de estrutura: o
        # config fica INTACTO (3, aviso), nunca vira "ilegivel" (2) nem derruba o escritor (1)
        open(relatorio, "w").write("estrutura-nao-lida (o config do dono fica intacto: %s)\n" % str(e)[:100])
        return 3
    FM = {p: v for p, v in folhas(M).items() if not any(comeca(p, t) for t in SEGURANCA_REMOVER)}
    definir = {p: FM[p] for p in SEGURANCA_DEFINIR if p in FM}
    for p, v in FM.items():
        if any(comeca(p, pre) for pre in SEGURANCA_DEFINIR_PREFIXO):
            definir[p] = v
    if runtime:
        definir[("projects", runtime, "trust_level")] = "untrusted"
    # gerenciado: troca pelo do molde so quando o molde declara o bloco; sem o bloco no molde, o
    # bloco do filtro do produto que o dono tem fica (o molde so nao achou o token)
    fica_do_dono = []
    for t in GERENCIADO:
        ov, tem = pega(O, t)
        if tem and not pega(M, t)[1] and eh_filtro_meta(ov):
            fica_do_dono.append(t)
            rel.append("gerenciado-do-dono " + ".".join(t))
    tirar = SEGURANCA_REMOVER + [t for t in GERENCIADO if t not in fica_do_dono]
    remove = set()
    # 1) remocoes de seguranca e do gerenciado (o molde decide o gerenciado inteiro)
    for idx, d in enumerate(decl):
        if d["k"] in ("tab", "aot") and any(comeca(d["path"], t) for t in tirar):
            remove.update(range(d["ini"], d["fim"] + 1))
            for d2 in decl[idx + 1:]:
                if d2["k"] in ("tab", "aot"):
                    break
                if d2["k"] == "kv":
                    remove.update(range(d2["ini"], d2["fim"] + 1))
        elif d["k"] == "kv":
            if any(comeca(d["path"], t) for t in tirar):
                remove.update(range(d["ini"], d["fim"] + 1))
            elif any(comeca(t, d["path"]) and len(t) > len(d["path"]) and pega(O, t)[1] for t in tirar):
                open(relatorio, "w").write("seguranca-em-tabela-inline %s\n" % ".".join(d["path"]))
                return 3
    tirados = [t for t in tirar if pega(O, t)[1]]
    for t in tirados:
        rel.append("removida " + ".".join(t))
    # 2) seguranca: o valor do molde vence na chave que o dono tambem declara
    troca = {}
    for p, mv in definir.items():
        ov, tem = pega(O, p)
        if not tem or ov == mv:
            continue
        alvo = [d for d in decl if d["k"] == "kv" and d["path"] == p and not d["aot"]]
        if len(alvo) != 1:
            open(relatorio, "w").write("seguranca-fora-de-linha-propria %s\n" % ".".join(p))
            return 3
        d = alvo[0]
        troca[d["ini"]] = (d["fim"], ".".join(chave_txt(x) for x in d["rel"]) + " = " + valor_txt(mv))
        rel.append("seguranca " + ".".join(p))
    # 3) o que falta: folha do molde que o dono nao tem (nem ele nem um prefixo dela como valor)
    FO = folhas(O)
    for t in tirados:
        for p in list(FO):
            if comeca(p, t):
                del FO[p]

    def dono_tem(p):
        for k in range(1, len(p) + 1):
            v, tem = pega(O, p[:k])
            if tem and k < len(p) and not isinstance(v, dict):
                return True  # o dono tem um valor onde o molde tem tabela: vale o dono
            if tem and k == len(p):
                return not any(comeca(p, t) for t in tirados)
        return False
    faltam = [p for p in FM if not dono_tem(p)]
    for p in FO:
        if p in FM and FO[p] != FM[p] and p not in definir:
            rel.append("escolha-do-dono " + ".".join(p))
    cabecalhos = {}
    for idx, d in enumerate(decl):
        if d["k"] == "tab" and d["ini"] not in remove:
            cabecalhos[d["path"]] = idx
    primeiro_cab = next((idx for idx, d in enumerate(decl) if d["k"] in ("tab", "aot")), None)
    grupos = {}
    for p in faltam:
        grupos.setdefault(p[:-1], []).append(p)
    depois_de = {}   # linha -> [texto] (insere depois desta linha; -1 = topo do arquivo)
    fim_novos = []

    def fim_secao(idx_cab):
        ultimo = decl[idx_cab]["fim"]
        for d in decl[idx_cab + 1:]:
            if d["k"] in ("tab", "aot"):
                break
            if d["k"] == "kv":
                ultimo = d["fim"]
        return ultimo

    def monta(extra_depois, extra_fim):
        saida_l = []
        if -1 in extra_depois:
            saida_l.extend(extra_depois[-1])
        i = 0
        while i < len(linhas):
            if i in troca:
                fim, nova = troca[i]
                saida_l.append(nova)
                for k in range(i, fim + 1):
                    if k in extra_depois:
                        saida_l.extend(extra_depois[k])
                i = fim + 1
                continue
            if i not in remove:
                saida_l.append(linhas[i])
            if i in extra_depois:
                saida_l.extend(extra_depois[i])
            i += 1
        corpo = "\n".join(saida_l)
        if extra_fim:
            if corpo and not corpo.endswith("\n"):
                corpo += "\n"
            corpo += "\n" + "\n".join(extra_fim) + "\n"
        return corpo

    for pai in sorted(grupos, key=lambda c: (len(c), c)):
        ps = grupos[pai]
        linhas_kv = [chave_txt(p[-1]) + " = " + valor_txt(FM[p]) for p in ps]
        tentativa_depois = {k: list(v) for k, v in depois_de.items()}
        tentativa_fim = list(fim_novos)
        if pai == ():
            raiz = [d for d in decl[:primeiro_cab if primeiro_cab is not None else len(decl)] if d["k"] == "kv"]
            onde = raiz[-1]["fim"] if raiz else -1
            if onde == -1 and linhas_kv:
                linhas_kv = linhas_kv + [""]
            tentativa_depois.setdefault(onde, []).extend(linhas_kv)
        elif pai in cabecalhos:
            tentativa_depois.setdefault(fim_secao(cabecalhos[pai]), []).extend(linhas_kv)
        else:
            tentativa_fim.extend(([""] if tentativa_fim else []) + ["[" + ".".join(chave_txt(x) for x in pai) + "]"] + linhas_kv)
        try:
            carrega(monta(tentativa_depois, tentativa_fim))
        except Ilegivel:
            if any(p in definir for p in ps):
                open(relatorio, "w").write("seguranca-nao-coube %s\n" % ".".join(pai))
                return 3
            for p in ps:
                rel.append("nao-coube " + ".".join(p))
            continue
        depois_de, fim_novos = tentativa_depois, tentativa_fim
        for p in ps:
            rel.append("acrescentada " + ".".join(p))
    corpo = monta(depois_de, fim_novos)
    F = carrega(corpo)
    FF = folhas(F)
    # 4) a prova do que foi feito: dono intacto fora da lista, seguranca aplicada, molde onde faltava
    for p, v in FO.items():
        if p in definir:
            continue
        if FF.get(p, "\x00ausente") != v:
            raise SystemExit("o merge mudou a chave do dono " + ".".join(p))
    for p, v in definir.items():
        if FF.get(p, "\x00ausente") != v:
            open(relatorio, "w").write("seguranca-nao-aplicada %s\n" % ".".join(p))
            return 3
    for t in SEGURANCA_REMOVER:
        if pega(F, t)[1]:
            raise SystemExit("sobrou " + ".".join(t))
    for t in GERENCIADO:
        if pega(F, t)[0] != (pega(O, t)[0] if t in fica_do_dono else pega(M, t)[0]):
            raise SystemExit("gerenciado divergente " + ".".join(t))
    grava(saida, (bom + corpo).encode("utf-8"))
    open(relatorio, "w").write("".join(r + "\n" for r in rel))
    return 0


# ------------------------------------------------------------------------------ skills --------
def arvore(caminho):
    h = hashlib.sha256()
    for base, dirs, nomes in os.walk(caminho, followlinks=False):
        dirs.sort()
        for n in sorted(nomes):
            f = os.path.join(base, n)
            h.update(os.path.relpath(f, caminho).encode() + b"\0")
            if os.path.islink(f):
                h.update(b"L" + os.readlink(f).encode())
            else:
                with open(f, "rb") as fh:
                    h.update(hashlib.sha256(fh.read()).digest())
    return h.hexdigest()


def privatiza(destino):
    for base, dirs, nomes in os.walk(destino):
        os.chmod(base, 0o700)
        for x in nomes:
            f = os.path.join(base, x)
            if not os.path.islink(f):
                os.chmod(f, 0o600 | (stat.S_IMODE(os.lstat(f).st_mode) & 0o100))


def le_registro(registro):
    try:
        return open(registro, encoding="utf-8").read().strip()
    except OSError:
        return ""


def arquivos_do_dono_em_pasta_do_produto(backup, novo, nome):
    """Arquivos (e links) de backup/nome que nao existem em novo/nome, em caminho relativo."""
    ob, on = os.path.join(backup, nome), os.path.join(novo, nome)
    out = []
    for base, dirs, nomes in os.walk(ob, followlinks=False):
        dirs.sort()
        for d in list(dirs):
            if os.path.islink(os.path.join(base, d)):
                nomes.append(d)
                dirs.remove(d)
        for n in sorted(nomes):
            rel = os.path.relpath(os.path.join(base, n), ob)
            if not os.path.lexists(os.path.join(on, rel)):
                out.append(rel)
    return out


def skills_do_dono(backup, novo, pessoais, registro=None):
    if not os.path.isdir(backup) or os.path.islink(backup):
        return 0
    if registro is not None:
        reg = le_registro(registro)
        if reg and reg == arvore(backup):
            print("catalogo-intacto (igual ao que o produto instalou)")
            return 0
    produto = set(PRODUTO_SKILLS)
    if os.path.isdir(novo):
        produto.update(os.listdir(novo))
    do_dono = sorted(n for n in os.listdir(backup) if n not in produto)
    # Pasta com nome do produto nos dois catalogos: arquivo que so o backup tem e do dono.
    parciais = []
    for n in sorted(os.listdir(backup)):
        if n in do_dono or not os.path.isdir(os.path.join(backup, n)) or os.path.islink(os.path.join(backup, n)):
            continue
        if not os.path.isdir(os.path.join(novo, n)) or os.path.islink(os.path.join(novo, n)):
            continue
        so_no_backup = arquivos_do_dono_em_pasta_do_produto(backup, novo, n)
        if so_no_backup:
            parciais.append((n, so_no_backup))
    divergente = registro is not None
    if not do_dono and not parciais:
        if divergente:
            print("catalogo-antigo-divergente (%s): o backup fica" % ("sem registro do que o produto instalou" if not le_registro(registro) else "difere do que o produto instalou"))
            return 10
        return 0
    os.makedirs(pessoais, mode=0o700, exist_ok=True)
    for n, rels in parciais:
        obra = tempfile.mkdtemp(prefix=".catalogo-antigo-", dir=pessoais)
        try:
            for rel in rels:
                o, d = os.path.join(backup, n, rel), os.path.join(obra, rel)
                os.makedirs(os.path.dirname(d), exist_ok=True)
                if os.path.islink(o) or not os.path.isdir(o):
                    shutil.copy2(o, d, follow_symlinks=False)
                else:
                    shutil.copytree(o, d, symlinks=True)
            privatiza(obra)
            h, k, achou = arvore(obra), 1, None
            while os.path.lexists("%s.catalogo-antigo-%d" % (os.path.join(pessoais, n), k)):
                ex = "%s.catalogo-antigo-%d" % (os.path.join(pessoais, n), k)
                if achou is None and os.path.isdir(ex) and arvore(ex) == h:
                    achou = ex
                k += 1
            if achou:
                print("ja-estava " + n + " -> " + os.path.basename(achou))
            else:
                destino = "%s.catalogo-antigo-%d" % (os.path.join(pessoais, n), k)
                os.rename(obra, destino)
                obra = None
                print("copiada " + n + " (arquivos do dono dentro da pasta do produto: " + " ".join(rels[:20]) + ") -> " + os.path.basename(destino))
        finally:
            if obra:
                shutil.rmtree(obra, ignore_errors=True)
    for n in do_dono:
        origem = os.path.join(backup, n)
        destino = os.path.join(pessoais, n)
        if os.path.lexists(destino):
            if os.path.isdir(destino) and os.path.isdir(origem) and arvore(destino) == arvore(origem):
                print("ja-estava " + n)
                continue
            k = 1
            while os.path.lexists("%s.catalogo-antigo-%d" % (destino, k)):
                k += 1
            destino = "%s.catalogo-antigo-%d" % (destino, k)
        if os.path.isdir(origem) and not os.path.islink(origem):
            shutil.copytree(origem, destino, symlinks=True)
            privatiza(destino)
        else:
            shutil.copy2(origem, destino, follow_symlinks=False)
            if not os.path.islink(destino):
                os.chmod(destino, 0o600)
        print("copiada " + n + " -> " + os.path.basename(destino))
    return 10


def codex_home_do_dono(env, data_dir):
    """Sai 0 quando o CODEX_HOME desta casa e do DONO (o produto nao escreve config.toml nele):
    o .env declara outra pasta; ou nao declara nenhuma e ~/.codex tem credencial (o bridge usa o
    ~/.codex, homeDoMotor); ou a pasta do LEON (<LEON_DATA_DIR>/codex) e link, ou passa por
    link, pra outro lugar (o ~/.codex pessoal); ou o config.toml dela e link. Sai 1 = do LEON.
    LEON_DATA_DIR declarado no .env vence o do chamador (e o que o bridge usa)."""
    data_dir = valor_ativo(env, "LEON_DATA_DIR") or data_dir
    leon = os.path.join(data_dir, "codex")
    # a pasta que o bridge usa hoje: a declarada; sem CODEX_HOME no .env, o ~/.codex quando ele
    # tem credencial (homeDoMotor); senao a do LEON
    usa = home_do_motor(env, "codex", leon)
    if os.path.normpath(usa) != os.path.normpath(leon):
        print(("declarado " if valor_ativo(env, "CODEX_HOME") else "credencial-do-dono ") + usa)
        return 0
    if os.path.lexists(leon) and (os.path.islink(leon) or os.path.realpath(leon) != os.path.join(os.path.realpath(data_dir), "codex")):
        print("link " + leon + " -> " + os.path.realpath(leon))
        return 0
    if os.path.islink(os.path.join(leon, "config.toml")):
        print("config-link " + os.path.join(leon, "config.toml"))
        return 0
    return 1


def le_env_seguro(caminho):
    """O texto do .env aberto UMA vez, com as guardas do readSafeEnvFile do bridge; None = recusa."""
    try:
        visto = os.lstat(caminho)
        if not stat.S_ISREG(visto.st_mode) or visto.st_nlink != 1 or visto.st_uid != os.getuid() \
           or stat.S_IMODE(visto.st_mode) & 0o077 or visto.st_size > 256 * 1024:
            return None
        fd = os.open(caminho, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        try:
            antes = os.fstat(fd)
            cru = os.read(fd, antes.st_size + 1)
            depois = os.fstat(fd)
        finally:
            os.close(fd)
    except OSError:
        return None
    if not stat.S_ISREG(antes.st_mode) or antes.st_nlink != 1 or (antes.st_dev, antes.st_ino) != (visto.st_dev, visto.st_ino) \
       or (depois.st_dev, depois.st_ino) != (antes.st_dev, antes.st_ino) or depois.st_nlink != 1 \
       or depois.st_size != antes.st_size or len(cru) != antes.st_size:
        return None
    try:
        texto = cru.decode("utf-8")
    except UnicodeDecodeError:
        return None
    return None if "\x00" in texto else texto


def ativas_do_texto(texto):
    """{chave: valor como o bridge le}; None = o bridge recusaria o arquivo inteiro."""
    linhas = linhas_do_env(texto)
    problemas, idx = confere_env(linhas)
    if problemas:
        return None
    return {k: valor_do_bridge(RE_KV.match(linhas[i]).group(2)) for k, i in idx.items()}


def env_valor_seguro(caminho, chave):
    if not re.fullmatch(r"[A-Z][A-Z0-9_]*", chave):
        return 1
    texto = le_env_seguro(caminho)
    at = ativas_do_texto(texto) if texto is not None else None
    if at is None or chave not in at:
        return 1
    sys.stdout.write(at[chave])
    return 0


def env_exporta(caminho):
    texto = le_env_seguro(caminho)
    at = ativas_do_texto(texto) if texto is not None else None
    if at is None:
        return 3
    for k in sorted(at):
        print("export " + k + "=" + shlex.quote(at[k]))
    return 0


def main(argv):
    if not argv:
        raise SystemExit(64)
    cmd, a = argv[0], argv[1:]
    if cmd == "env-acrescenta" and len(a) in (5, 6):
        return env_acrescenta(*a)
    if cmd == "home-do-motor" and len(a) == 3 and a[1] in MOTOR_CHAVE:
        sys.stdout.write(home_do_motor(*a))
        return 0
    if cmd == "toml-funde" and len(a) == 5:
        try:
            return toml_funde(*a)
        except Ilegivel as e:
            # O texto do dono ja passou pela leitura: falha aqui e do merge, nao do dono. Intacto.
            open(a[3], "w").write("merge-nao-fechou %s\n" % str(e)[:120])
            return 3
    if cmd == "skills-do-dono" and len(a) in (3, 4):
        return skills_do_dono(*a)
    if cmd == "skills-registra" and len(a) == 2:
        if not os.path.isdir(a[0]) or os.path.islink(a[0]):
            return 1
        grava(a[1], (arvore(a[0]) + "\n").encode("utf-8"), 0o600)
        return 0
    if cmd == "codex-home-do-dono" and len(a) == 2:
        return codex_home_do_dono(*a)
    if cmd == "env-valor" and len(a) == 2:
        # le UMA chave como o bridge le (comentario no fim e aspas saem); sai 1 se nao tem
        achado = valor_ativo(a[0], a[1])
        if achado is None:
            return 1
        sys.stdout.write(achado)
        return 0
    if cmd == "env-valor-seguro" and len(a) == 2:
        return env_valor_seguro(*a)
    if cmd == "env-exporta" and len(a) == 1:
        return env_exporta(a[0])
    if cmd == "bases-do-dono" and len(a) >= 2:
        for k, v in bases_do_dono(a[0], a[1], a[2:]).items():
            print(k + "=" + shlex.quote(v))
        return 0
    if cmd == "lista-produto-env":
        for k in sorted(PRODUTO_ENV):
            print(k + "\t" + PRODUTO_ENV[k])
        return 0
    raise SystemExit(64)


sys.exit(main(sys.argv[1:]))
LEON_PRESERVA_PY
}
# leon_bases_do_dono <.env do dono> [home do dono]: as pastas como o bridge resolve pra esta
# casa (LEON_DATA_DIR do .env; dele BRAIN_DIR, MEMVIVA_FILE, ASSUNTOS_FILE, LEON_STATE_DIR,
# LEON_MISSIONS_DIR, LEON_PROMISES_DIR, PERSONA_DIR e as outras). Com .env existente vale so o
# .env, lido por leon_preserva; sem .env (instalacao do zero) valem so as pastas que o COMANDO
# passou, lidas UMA vez aqui, quando o bloco carrega e antes de o script calcular qualquer pasta
# (24/09, rodada 6). A saida de uma chamada nunca volta como entrada da seguinte: o instalador
# rodando como root calculava ~root/.leon no topo e a fase root herdava isso pra casa do leon.
if [ -z "${_LEON_BASES_DO_COMANDO_LIDO:-}" ]; then
  _LEON_BASES_DO_COMANDO=("LEON_DATA_DIR=${LEON_DATA_DIR:-}" "BRAIN_DIR=${BRAIN_DIR:-}" \
    "MEMVIVA_FILE=${MEMVIVA_FILE:-}" "ASSUNTOS_FILE=${ASSUNTOS_FILE:-}" \
    "LEON_STATE_DIR=${LEON_STATE_DIR:-}" "LEON_MISSIONS_DIR=${LEON_MISSIONS_DIR:-}" \
    "LEON_PROMISES_DIR=${LEON_PROMISES_DIR:-}" "PERSONA_DIR=${PERSONA_DIR:-}" \
    "LEON_SKILLS_PESSOAIS_DIR=${LEON_SKILLS_PESSOAIS_DIR:-}" "LEON_TMPDIR=${LEON_TMPDIR:-}" \
    "LEON_MISSION_OUTPUT_DIR=${LEON_MISSION_OUTPUT_DIR:-}" "LEON_WORK_AREA=${LEON_WORK_AREA:-}" \
    "LEON_SKILLS_DIR=${LEON_SKILLS_DIR:-}")
  _LEON_BASES_DO_COMANDO_LIDO=1
fi
leon_bases_do_dono() {
  local _lb_saida
  _lb_saida="$(leon_preserva bases-do-dono "$1" "${2:-$HOME}" "${_LEON_BASES_DO_COMANDO[@]}")" || return 1
  eval "$_lb_saida"
}
# <<< LEON-PRESERVA v1

# ENTRADA DO VIGIA (24/09, rodada 5; marca LEON-PRESERVA-ENTRADA v1). O vigia do /atualiza
# (scripts/update-verdict.sh, bloco LEON-HANDOFF-UPDATE) le o .env pelo MESMO leitor antes de
# disparar o atualizador: bash update-pago.sh --preserva env-exporta <.env>. A linha crua que ele
# exportava levava aspas e comentario literais (LEON_DATA_DIR="/x" # nota) pro atualizador.
if [ "${1:-}" = "--preserva" ]; then
  shift
  leon_preserva "$@"
  exit $?
fi

if [ "${LEON_TEST_RELEASE_HELPERS_ONLY:-0}" = "1" ]; then
  case "${1:-}" in
    identity-read) read_installed_release_identity "$2" ;;
    identity-accept) release_identity_acceptable "$2" "$3" "$4" "$5" ;;
    identity-write) write_release_identity "$2" "$3" "$4" ;;
    manifest-verify) verify_release_manifest "$2" "$3" "$4" "$5" ;;
    download-validate) validate_download_file "$2" "$3" "${4:-}" ;;
    env-value) safe_env_value "$2" "$3" ;;
    *) exit 64 ;;
  esac
  exit $?
fi

# Funcoes de rede/aviso movidas pra cima (03/09): o STAGE0 abaixo precisa delas
# antes do corpo. Sao puras: dependem so de TEST_MODE, CURL_BIN e safe_env_value.
curl_common() {
  if [ "$TEST_MODE" = "1" ]; then
    "$CURL_BIN" "$@"
  else
    "$CURL_BIN" --proto '=https' --tlsv1.2 "$@"
  fi
}

telegram_api_get_file() {
  local token="$1" endpoint="$2" output="$3" timeout="${4:-15}"
  printf %s "$token" | grep -qE '^[0-9]+:[A-Za-z0-9_-]{20,}$' || return 2
  case "$endpoint" in getMe) ;; *) return 2 ;; esac
  printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$token" "$endpoint" \
    | curl_common -fsS --max-time "$timeout" --config - --output "$output" 2>/dev/null
}

telegram_api_send_message() {
  local token="$1" chat="$2" text="$3" thread="${4:-}"
  printf %s "$token" | grep -qE '^[0-9]+:[A-Za-z0-9_-]{20,}$' || return 2
  printf %s "$chat" | grep -qE '^-?[1-9][0-9]*$' || return 2
  [ -z "$thread" ] || printf %s "$thread" | grep -qE '^[1-9][0-9]*$' || return 2
  if [ -n "$thread" ]; then
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" \
      | curl_common -sS --max-time 20 --config - \
          --data-urlencode "chat_id=$chat" \
          --data-urlencode "message_thread_id=$thread" \
          --data-urlencode "text=$text" >/dev/null 2>&1
  else
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" \
      | curl_common -sS --max-time 20 --config - \
          --data-urlencode "chat_id=$chat" \
          --data-urlencode "text=$text" >/dev/null 2>&1
  fi
}

notify_from_runtime() {
  local runtime="$1" text="$2" thread="${3:-}" chat_override="${4:-}" env_file token chat
  env_file="$runtime/.env"
  token="$(safe_env_value "$env_file" TELEGRAM_BOT_TOKEN 2>/dev/null)" || return 0
  chat="${chat_override:-$(safe_env_value "$env_file" OWNER_CHAT_ID 2>/dev/null)}"
  [ -n "$token" ] && [ -n "$chat" ] || return 0
  telegram_api_send_message "$token" "$chat" "$text" "$thread" || true
}

# FONTE PRINCIPAL = GITHUB (23/09, lei do dono: "cliente nenhum pode depender da VPS, e sim de
# repositorio git"). Ate aqui a central era a origem e o espelho publico no GitHub so a reserva
# (baixa_com_espelho, 23/08; manifesto com espelho, 23/09 manha). Agora inverte: manifesto
# assinado e cada artefato livre (atualizador, runtime, catalogo de skills) vem PRIMEIRO do
# espelho (LEON_ESPELHO, raw.githubusercontent.com/molinateston/leon-espelho) e a central vira
# reserva. A SEGURANCA NAO MUDA, venha de onde vier: chave pinada por fingerprint, assinatura
# Ed25519, contrato e anti-downgrade no manifesto; sha256 e tamanho pinados pelo manifesto em
# cada artefato. Manifesto que chega e nao confere ABORTA (falha fechada, nao troca de origem).
# ESPELHO ATRASADO: o espelho pode ficar atras da central (sincroniza por hora e no fim do rito).
# Se o manifesto do espelho nao e mais novo que o instalado, pergunto a central com timeout curto
# e fico com o MAIS NOVO dos dois; a verificacao depois e a mesma. Central fora: vale o espelho.
# Artefato: espelho primeiro; se o sha/tamanho nao bate com o manifesto (espelho atrasado ou
# adulterado), tenta a central; nada entra sem bater. Origem em MANIFESTO_ORIGEM e
# ARTEFATO_ORIGEM (espelho|central), pro upgrade.log e pro tx.
LEON_ESPELHO="${LEON_ESPELHO:-https://raw.githubusercontent.com/molinateston/leon-espelho/main}"
MANIFESTO_ORIGEM=""
MANIFESTO_NOTA=""
ARTEFATO_ORIGEM=""
# versao declarada no manifesto, SEM conferir assinatura: serve so pra ESCOLHER a origem; quem
# chama confere assinatura e contrato do escolhido depois.
versao_do_manifesto() {  # <arquivo.json>
  "$PYTHON_BIN" - "$1" <<'PY' 2>/dev/null
import json,re,sys
try: v=str(json.load(open(sys.argv[1],encoding="utf-8")).get("version",""))
except Exception: raise SystemExit(1)
if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)",v): raise SystemExit(1)
print(v)
PY
}
# json e sig da MESMA origem, sempre (nunca mistura um de cada lado).
baixa_par() {  # <base-url> <nome.json> <nome.sig> <saida.json> <saida.sig> <max-json> <tentativas> <connect-timeout>
  local b="$1" nj="$2" ns="$3" oj="$4" os="$5" mj="$6" tent="$7" ct="$8"
  [ -n "$b" ] || return 1
  { : > "$oj" && : > "$os"; } 2>/dev/null || return 1
  curl_common -fsSL --max-filesize "$mj" --retry "$tent" --retry-delay 2 --retry-connrefused $CURL_RETRY_ALL \
      --connect-timeout "$ct" --max-time 60 "$b/$nj" -o "$oj" 2>/dev/null \
   && curl_common -fsSL --max-filesize 64 --retry "$tent" --retry-delay 2 --retry-connrefused $CURL_RETRY_ALL \
      --connect-timeout "$ct" --max-time 60 "$b/$ns" -o "$os" 2>/dev/null
}
# So a ASSINATURA do par json/sig pela chave pinada (contrato e anti-downgrade ficam com quem
# chama). Serve pra ESCOLHER a origem; quem chama confere tudo de novo no par escolhido.
par_confere() {  # <arquivo.json> <arquivo.sig>
  local k
  k="$(mktemp "${TMPDIR:-/tmp}/leon-par.XXXXXX")" || return 1
  if write_release_public_key "$k" \
     && openssl pkeyutl -verify -rawin -pubin -inkey "$k" -in "$1" -sigfile "$2" >/dev/null 2>&1; then
    rm -f -- "$k"; return 0
  fi
  rm -f -- "$k"; return 1
}
baixa_manifesto_assinado() {  # <central> <nome.json> <nome.sig> <saida.json> <saida.sig> <max-json> <tentativas> [versao-instalada]
  local central="$1" nj="$2" ns="$3" oj="$4" os="$5" mj="$6" tent="$7" inst="${8:-}" ve="" vc="" tj="" ts=""
  MANIFESTO_ORIGEM=""; MANIFESTO_NOTA=""
  if [ -n "${LEON_ESPELHO:-}" ] && baixa_par "$LEON_ESPELHO" "$nj" "$ns" "$oj" "$os" "$mj" "$tent" 20; then
    MANIFESTO_ORIGEM=espelho
    # PAR DO ESPELHO QUE NAO CONFERE (23/09 noite, revisor): o raw.githubusercontent guarda
    # cache de uns 5 min POR ARQUIVO; logo depois de um push a casa pode receber o json novo com
    # o sig velho. A central passa pela MESMA verificacao, entao tentar ela nao afrouxa nada: so
    # troca de origem se o par da central conferir. Nao conferiu nenhum: devolve o par do
    # espelho e quem chama reprova a assinatura (falha fechada, como antes).
    if ! par_confere "$oj" "$os"; then
      MANIFESTO_NOTA="espelho com assinatura invalida"
      [ -n "$central" ] || return 0
      tj="$(mktemp "${TMPDIR:-/tmp}/leon-man-central.XXXXXX")" || return 0
      ts="$(mktemp "${TMPDIR:-/tmp}/leon-man-central.XXXXXX")" || { rm -f -- "$tj"; return 0; }
      if baixa_par "$central" "$nj" "$ns" "$tj" "$ts" "$mj" 1 10 && par_confere "$tj" "$ts"; then
        if cat -- "$tj" > "$oj" && cat -- "$ts" > "$os"; then
          MANIFESTO_ORIGEM=central
          MANIFESTO_NOTA="espelho com assinatura invalida (cache do GitHub?); usei a central, par conferido"
        else
          rm -f -- "$tj" "$ts"; return 1
        fi
      else
        MANIFESTO_NOTA="espelho com assinatura invalida e a central nao entregou par valido"
      fi
      rm -f -- "$tj" "$ts"
      return 0
    fi
    [ -n "$inst" ] && [ -n "$central" ] || return 0
    ve="$(versao_do_manifesto "$oj")" || return 0      # ilegivel: a verificacao depois reprova
    semver_ge "$inst" "$ve" 2>/dev/null || return 0    # o espelho ja traz versao nova: fica com ele
    tj="$(mktemp "${TMPDIR:-/tmp}/leon-man-central.XXXXXX")" || return 0
    ts="$(mktemp "${TMPDIR:-/tmp}/leon-man-central.XXXXXX")" || { rm -f -- "$tj"; return 0; }
    # espelho atrasado: a central so ganha se o par dela CONFERE (central com par ruim nao
    # derruba o espelho bom).
    if baixa_par "$central" "$nj" "$ns" "$tj" "$ts" "$mj" 1 5 && par_confere "$tj" "$ts" \
       && vc="$(versao_do_manifesto "$tj")" && ! semver_ge "$ve" "$vc" 2>/dev/null; then
      if cat -- "$tj" > "$oj" && cat -- "$ts" > "$os"; then
        MANIFESTO_ORIGEM=central
        MANIFESTO_NOTA="espelho atrasado ($ve); a central tem $vc"
      else
        rm -f -- "$tj" "$ts"; return 1
      fi
    fi
    rm -f -- "$tj" "$ts"
    return 0
  fi
  if baixa_par "$central" "$nj" "$ns" "$oj" "$os" "$mj" "$tent" 10; then
    MANIFESTO_ORIGEM=central
    MANIFESTO_NOTA="o espelho no GitHub nao respondeu; usei a central de reserva"
    return 0
  fi
  return 1
}
confere_sha_tamanho() {  # <arquivo> <sha256> <bytes>
  "$PYTHON_BIN" - "$1" "$2" "$3" <<'PY' 2>/dev/null
import hashlib,os,sys
p,h,n=sys.argv[1],sys.argv[2],int(sys.argv[3])
try:
    if os.path.getsize(p)!=n: raise SystemExit(1)
    d=hashlib.sha256()
    with open(p,"rb") as f:
        for b in iter(lambda: f.read(1<<20), b""): d.update(b)
except OSError: raise SystemExit(1)
raise SystemExit(0 if d.hexdigest()==h else 1)
PY
}
# Artefato citado no manifesto assinado: espelho primeiro, central de reserva; so aceita o que
# bate sha E tamanho do manifesto. Quem chama ainda roda verify_signed_artifact (dupla checagem).
baixa_artefato_verificado() {  # <central> <rel> <destino> <max-bytes> <sha256> <bytes> <tentativas>
  local central="$1" rel="$2" dest="$3" max="$4" sha="$5" n="$6" tent="$7" nome="${2##*/}"
  ARTEFATO_ORIGEM=""
  if [ -n "${LEON_ESPELHO:-}" ] && [ -n "$nome" ] \
     && curl_common -fsSL --max-filesize "$max" --retry "$tent" --retry-delay 2 --retry-connrefused $CURL_RETRY_ALL \
          --connect-timeout 20 --max-time 180 "$LEON_ESPELHO/$nome" -o "$dest" 2>/dev/null \
     && confere_sha_tamanho "$dest" "$sha" "$n"; then
    ARTEFATO_ORIGEM=espelho; return 0
  fi
  if [ -n "$central" ] \
     && curl_common -fsSL --max-filesize "$max" --retry "$tent" --retry-delay 2 --retry-connrefused $CURL_RETRY_ALL \
          --connect-timeout 10 --max-time 180 "$central$rel" -o "$dest" 2>/dev/null \
     && confere_sha_tamanho "$dest" "$sha" "$n"; then
    ARTEFATO_ORIGEM=central; return 0
  fi
  return 1
}
# LICENCA ASSINADA E PACOTE PAGO SEM VPS (23/09, item G3; flag LEON_LICENCA_ASSINADA nasce 0).
# Espelho em bash+python do lib/licenca-assinada.cjs: a casa confere a licenca OFFLINE com a
# chave publica da LICENCA pinada abaixo (separada da chave da release). Vazia = recurso inerte
# ate o dono gerar a chave de producao (ferramentas/licenca/gera-chave-licenca.sh). A prova
# confere que as copias (lib, instalador, atualizador) sao iguais. Nunca vem de variavel de ambiente.
LEON_LICENCA_PUB_B64=''
# Sucesso: imprime "<id>\t<valida_ate>\t<vencida 0|1>\t<chave_pacote ou ->" e sai 0.
# Licenca na lista de revogacao (lista CONFERIDA pela mesma chave): sai 3. Invalida/ausente: 1.
# ANTI-ROLLBACK (23/09 noite, igual ao lib/licenca-assinada.cjs): com [pasta-de-estado], a lista
# aceita fica guardada la (licencas-revogadas.assinada, 0600) e lista com seq MENOR que a guardada
# ou que a ultima vista pelo runtime (revogacao.seq no licenca-assinada.json) e ignorada: lista
# velha reenviada nao "desrevoga". Os ids que o runtime ja viu revogados continuam valendo.
licenca_confere() {  # <arquivo-da-licenca> [arquivo-da-lista-de-revogacao] [pasta-de-estado]
  [ -n "$LEON_LICENCA_PUB_B64" ] && [ -f "$1" ] || return 1
  "${PYTHON_BIN:-python3}" - "$1" "${2:-}" "$LEON_LICENCA_PUB_B64" "${3:-}" <<'PY'
import base64,datetime,json,os,re,subprocess,sys,tempfile,time
tok,rev,pub,estado=sys.argv[1:5]
def b64u(s):
    if not re.fullmatch(r"[A-Za-z0-9_-]+",s): raise ValueError()
    return base64.urlsafe_b64decode(s+"="*(-len(s)%4))
def abre(texto,tipo):
    p=texto.strip().split(".")
    if len(p)!=3 or p[0]!="leon1": raise ValueError()
    payload,sig=b64u(p[1]),b64u(p[2])
    if len(sig)!=64: raise ValueError()
    with tempfile.TemporaryDirectory() as t:
        with open(t+"/k.pem","w") as f: f.write("-----BEGIN PUBLIC KEY-----\n"+pub+"\n-----END PUBLIC KEY-----\n")
        with open(t+"/p","wb") as f: f.write(payload)
        with open(t+"/s","wb") as f: f.write(sig)
        r=subprocess.run(["openssl","pkeyutl","-verify","-pubin","-inkey",t+"/k.pem","-rawin","-in",t+"/p","-sigfile",t+"/s"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        if r.returncode!=0: raise ValueError()
    d=json.loads(payload.decode("utf-8"))
    if not isinstance(d,dict) or d.get("v")!=1 or d.get("tipo")!=tipo: raise ValueError()
    return d
def quando(s): return datetime.datetime.fromisoformat(str(s).replace("Z","+00:00")).timestamp()
try:
    raw=open(tok,encoding="utf-8").read(16385)
    if raw.lstrip().startswith("{"): raw=json.loads(raw)["token"]
    d=abre(raw,"leon-licenca")
    if not re.fullmatch(r"[A-Za-z0-9_-]{4,80}",str(d.get("id",""))) or d.get("produto")!="leon": raise ValueError()
    ate=quando(d["valida_ate"])
    if quando(d["emitida_em"])>ate: raise ValueError()
    cp=d.get("chave_pacote")
    if cp is not None and not re.fullmatch(r"[A-Za-z0-9+/]{43}=",str(cp)): raise ValueError()
except Exception: raise SystemExit(1)
def lista(texto):
    r=abre(texto,"leon-revogacao")
    s,ids=r.get("seq"),r.get("ids")
    if isinstance(s,bool) or not isinstance(s,int) or s<1 or not isinstance(ids,list): raise ValueError()
    return r
nova=txt_nova=None
if rev and os.path.isfile(rev) and os.path.getsize(rev)>0:
    try: txt_nova=open(rev,encoding="utf-8").read(1048577); nova=lista(txt_nova)
    except Exception: nova=None   # lista ilegivel ou adulterada nao revoga nem libera
guardada=None; gpath=os.path.join(estado,"licencas-revogadas.assinada") if estado else ""
if gpath and os.path.isfile(gpath):
    try: guardada=lista(open(gpath,encoding="utf-8").read(1048577))
    except Exception: guardada=None
seq_rt=0; ids_rt=[]
try:
    j=json.load(open(tok,encoding="utf-8")); rj=j.get("revogacao") or {}
    if isinstance(rj.get("seq"),int) and not isinstance(rj.get("seq"),bool): seq_rt=rj["seq"]
    if isinstance(rj.get("ids"),list): ids_rt=[x for x in rj["ids"] if isinstance(x,str)]
except Exception: pass
piso=max(guardada["seq"] if guardada else 0, seq_rt)
vale=guardada
if nova is not None:
    if nova["seq"]>=piso:
        vale=nova
        if gpath and (guardada is None or nova["seq"]>guardada["seq"]):
            try:
                fd,t=tempfile.mkstemp(dir=estado,prefix=".revogadas.")
                with os.fdopen(fd,"w",encoding="utf-8") as f: f.write(txt_nova)
                os.chmod(t,0o600); os.replace(t,gpath)
            except Exception: pass
    else:
        print(f"lista de revogacao velha (seq {nova['seq']} < {piso}); ignorada",file=sys.stderr)
if (vale and d["id"] in vale["ids"]) or d["id"] in ids_rt: raise SystemExit(3)
print(f'{d["id"]}\t{d["valida_ate"]}\t{1 if time.time()>ate else 0}\t{cp or "-"}')
PY
}
# Lista de revogacao: GitHub primeiro, central de reserva. Arquivo vazio = nenhuma lista (a
# licenca vale pelo que ela mesma diz). Quem le confere a assinatura (licenca_confere).
baixa_revogacao() {  # <central> <destino>
  : > "$2" 2>/dev/null || return 1
  { [ -n "${LEON_ESPELHO:-}" ] && curl_common -fsSL --max-filesize 1048576 --retry 2 --retry-delay 2 --connect-timeout 10 --max-time 30 \
      "$LEON_ESPELHO/licencas-revogadas.txt" -o "$2" 2>/dev/null; } \
  || { [ -n "$1" ] && curl_common -fsSL --max-filesize 1048576 --retry 1 --connect-timeout 5 --max-time 20 \
      "$1/licencas-revogadas.txt" -o "$2" 2>/dev/null; } \
  || : > "$2"
  return 0
}
# PACOTE PAGO CIFRADO NO ESPELHO. O espelho publico guarda <arquivo>.cifrado: o pacote pago em
# AES-256-CBC (PBKDF2) com a chave_pacote, que so viaja DENTRO da licenca assinada. Sem licenca,
# bytes inuteis. A integridade nao depende da cifra: sha256 e tamanho do pacote EM CLARO estao
# pinados no manifesto assinado e so o que bate entra.
pacote_cifrado_do_espelho() {  # <nome> <sha256> <bytes> <destino> <chave-b64>
  local nome="$1" sha="$2" n="$3" dest="$4" chave="$5" c
  [ -n "${LEON_ESPELHO:-}" ] && [ -n "$chave" ] && [ "$chave" != "-" ] || return 1
  c="$(mktemp "${TMPDIR:-/tmp}/leon-cifrado.XXXXXX")" || return 1
  if curl_common -fsSL --max-filesize "$((n + 4096))" --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 180 \
       "$LEON_ESPELHO/$nome.cifrado" -o "$c" 2>/dev/null \
     && printf '%s\n' "$chave" | openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -pass stdin -in "$c" -out "$dest" 2>/dev/null \
     && confere_sha_tamanho "$dest" "$sha" "$n"; then
    rm -f -- "$c"; return 0
  fi
  rm -f -- "$c"; : > "$dest" 2>/dev/null
  return 1
}
# COPIA GUARDADA DO PACOTE PAGO: todo pacote conferido fica em LEON_CACHE_PACOTES (0600, nome =
# sha256). Enquanto o pacote nao muda (o base nao muda desde a 2.4.45), o /atualiza nao precisa
# da central pra ele. Guarda no maximo 3 (a casa nao vira deposito).
# A central "nao respondeu" (e nao "recusou")? 0 = fora: sem codigo, transferencia quebrada,
# 408, 429 ou qualquer 5xx (o Cloudflare na frente da VPS devolve 520 a 530 com ela fora).
# Recusa explicita (401, 402, 403, 404) e qualquer outro codigo nao sao "fora".
central_fora_http() {  # <http_code> <curl_rc>
  case "${1:-000}" in
    000|408|429|5[0-9][0-9]) return 0 ;;
    200) [ "${2:-0}" != 0 ] ;;
    *) return 1 ;;
  esac
}
pacote_do_cache() {  # <sha256> <bytes> <destino>
  local f="${LEON_CACHE_PACOTES:-}/$1"
  [ -n "${LEON_CACHE_PACOTES:-}" ] && [ -f "$f" ] && [ ! -L "$f" ] && confere_sha_tamanho "$f" "$1" "$2" \
    && cat -- "$f" > "$3" && confere_sha_tamanho "$3" "$1" "$2"
}
guarda_pacote_no_cache() {  # <arquivo> <sha256>
  [ -n "${LEON_CACHE_PACOTES:-}" ] || return 0
  ( umask 077
    mkdir -p -- "$LEON_CACHE_PACOTES" && chmod 0700 -- "$LEON_CACHE_PACOTES" \
      && cp -- "$1" "$LEON_CACHE_PACOTES/.$2.novo" && mv -f -- "$LEON_CACHE_PACOTES/.$2.novo" "$LEON_CACHE_PACOTES/$2" \
      && ls -1t -- "$LEON_CACHE_PACOTES" | grep -E '^[0-9a-f]{64}$' | tail -n +4 | while read -r v; do rm -f -- "$LEON_CACHE_PACOTES/$v"; done
  ) 2>/dev/null || true
}

# --- LEON-STAGE0-BEGIN (contrato: esta string nunca sai do arquivo) -----------
# STAGE0 (03/09/2026): o arquivo instalado no cliente e este mesmo, mas o CORPO
# abaixo nunca executa localmente. Este head baixa o atualizador FRESCO e
# assinado da central e faz exec nele. Efeito: bug no atualizador se conserta
# na central e a frota se cura no proximo /atualiza ou madrugada, zero toque.
# (Era o "salto blindado": copiava a si mesmo pra /tmp e fazia exec. Agora o
# exec e no fresco. Mesmo PID, argv e env: bridge e vigia nao percebem.)
# Pula: --finalize (cron, offline por desenho), LEON_UPDATE_BLINDADO=1 (ja e o
# fresco rodando) e helpers-only (build/deploy, sem rede).
# O head e a UNICA peca que nao se autocura: por isso e minimo, leniente com o
# manifesto (so assinatura, chave, kind/canal/versao e o artefato do updater;
# Codex/Node/chaves novas ficam pro corpo fresco decidir) e congelado por pin
# no deploy (a regiao do pin vai da linha 1 ate LEON-STAGE0-END, inclusive as
# funcoes que ele usa: bump de Node/helpers = bump de pin, de proposito).
s0_verify_manifest() {  # leniente: aceita campos/artefatos futuros; exige so o que o head precisa
  local manifest="$1" signature="$2" public_key="$3" metadata="$4"
  write_release_public_key "$public_key" || return 1
  openssl pkeyutl -verify -rawin -pubin -inkey "$public_key" \
    -in "$manifest" -sigfile "$signature" >/dev/null 2>&1 || return 1
  "$PYTHON_BIN" - "$manifest" "$LEON_RELEASE_TRUST_FINGERPRINT" > "$metadata" <<'PY'
import json,re,sys
manifest,fingerprint=sys.argv[1:]
try: data=json.load(open(manifest,encoding="utf-8"))
except Exception: raise SystemExit(1)
if not isinstance(data,dict): raise SystemExit(1)
if data.get("schema")!=2 or data.get("kind")!="leon-codex-release" or data.get("channel")!="stable": raise SystemExit(1)
if data.get("keyFingerprint")!=fingerprint: raise SystemExit(1)
version=str(data.get("version",""))
if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)",version): raise SystemExit(1)
item=(data.get("artifacts") or {}).get("updater")
if not isinstance(item,dict): raise SystemExit(1)
if item.get("url")!="/update-pago-codex.sh" or item.get("licensed") is not False: raise SystemExit(1)
if not re.fullmatch(r"[0-9a-f]{64}",str(item.get("sha256",""))): raise SystemExit(1)
b=item.get("bytes")
if isinstance(b,bool) or not isinstance(b,int) or not 1<=b<=536_870_912: raise SystemExit(1)
print("version="+version); print("updater_sha256="+item["sha256"]); print("updater_bytes=%d"%b); print("updater_url="+item["url"])
PY
}
if [ "$FINALIZE_MODE" -eq 0 ] && [ -z "${LEON_UPDATE_BLINDADO:-}" ] \
   && [ "${LEON_TEST_RELEASE_HELPERS_ONLY:-0}" != "1" ] \
   && [ "${LEON_TEST_SKILLS_HELPERS_ONLY:-0}" != "1" ]; then
  S0_CHAT="${1:-}"; S0_THREAD="${2:-}"
  S0_MAN=""; S0_SIG=""; S0_PUB=""; S0_META=""; S0_CAND=""
  s0_log() { printf '%s [stage0] %s\n' "$(date '+%F %T')" "$*" >> "$INSTALL_DIR/upgrade.log" 2>/dev/null || true; }
  s0_clean() { rm -f -- "$S0_MAN" "$S0_SIG" "$S0_PUB" "$S0_META" "$S0_CAND" 2>/dev/null || true; }
  # kill/sinal no meio do download nao deixa sobra (exec bem-sucedido NAO dispara EXIT)
  trap 's0_clean' EXIT
  trap 's0_clean; exit 130' INT TERM   # sem o exit, o handler roda e o script SEGUE (diagnostico errado)
  s0_die() {  # nunca deixa o cliente pior: apaga so os proprios temporarios e sai 1
    s0_log "⚠️ $1"
    s0_clean
    # madrugada (update-auto, sem pedido humano): so log, sem mensagem repetida ao dono
    if [ -n "$S0_CHAT" ] || [ -z "${LEON_UPDATE_AUTO:-}" ]; then
      notify_from_runtime "$INSTALL_DIR" "⚠️ $2 Continuo no ar na versão de antes; nada foi trocado." "$S0_THREAD" "$S0_CHAT" || true
    fi
    exit 1
  }
  # shim: verify_signed_artifact chama fatal; o corpo redefine fatal mais abaixo.
  fatal() { s0_die "$1" "A atualização baixada não bateu com a assinatura da central."; }
  [ -f "$INSTALL_DIR/.env" ] || s0_die "sem .env em $INSTALL_DIR" "não achei a configuração da instalação."
  # safe_env_value = gate de permissao/formato (0600, chave unica); o valor cru pode
  # vir com aspas ou comentario (.env editado a mao): normaliza como o env_get_from.
  S0_RAW="$(safe_env_value "$INSTALL_DIR/.env" LEON_LICENSE_CENTRAL 2>/dev/null)" || S0_RAW="__S0_ENV_INVALIDO__"
  if [ "$S0_RAW" = "__S0_ENV_INVALIDO__" ]; then
    leon_preserva env-valor "$INSTALL_DIR/.env" LEON_LICENSE_CENTRAL >/dev/null 2>&1 \
      && s0_die ".env fora do padrão (permissão não é 0600, dono errado ou chave repetida)" "a configuração da instalação está com permissão ou formato errado." \
      || s0_die "LEON_LICENSE_CENTRAL ausente no .env" "a configuração da instalação não diz qual é a central."
  fi
  S0_CENTRAL="$S0_RAW"   # ja sai como o bridge le (leon_preserva env-valor-seguro)
  case "$S0_CENTRAL" in
    https://*) ;;
    "") s0_die "LEON_LICENSE_CENTRAL vazio no .env" "a configuração da instalação está com o endereço da central em branco." ;;
    *) s0_die "LEON_LICENSE_CENTRAL não é https ($S0_CENTRAL)" "o endereço da central na configuração não é https." ;;
  esac
  S0_MAN="$(mktemp "${TMPDIR:-/tmp}/leon-stage0.XXXXXX.json")"  || s0_die "mktemp falhou (TMPDIR cheio ou inexistente?)" "não consegui criar arquivo temporário (disco cheio?)."
  S0_SIG="$(mktemp "${TMPDIR:-/tmp}/leon-stage0.XXXXXX.sig")"   || s0_die "mktemp falhou" "não consegui criar arquivo temporário (disco cheio?)."
  S0_PUB="$(mktemp "${TMPDIR:-/tmp}/leon-stage0.XXXXXX.pem")"   || s0_die "mktemp falhou" "não consegui criar arquivo temporário (disco cheio?)."
  S0_META="$(mktemp "${TMPDIR:-/tmp}/leon-stage0.XXXXXX.env")"  || s0_die "mktemp falhou" "não consegui criar arquivo temporário (disco cheio?)."
  # versao instalada ANTES do download: decide se o espelho esta atrasado (baixa_manifesto_assinado)
  S0_ID="$(read_installed_release_identity "$INSTALL_DIR" 2>/dev/null)" || S0_ID=$'0.0.0\t'
  IFS=$'\t' read -r S0_INST_VER S0_INST_DIG <<< "$S0_ID"
  s0_log "buscando o atualizador assinado no espelho ($LEON_ESPELHO), central de reserva $S0_CENTRAL"
  baixa_manifesto_assinado "$S0_CENTRAL" release-manifest.json release-manifest.sig "$S0_MAN" "$S0_SIG" 524288 3 "${S0_INST_VER:-0.0.0}" \
   || s0_die "download do manifesto falhou no espelho ($LEON_ESPELHO) e na central" "não consegui baixar a atualização agora: nem o GitHub nem a central responderam. Tente /atualiza mais tarde."
  s0_log "manifesto assinado baixado; origem=$MANIFESTO_ORIGEM${MANIFESTO_NOTA:+ ($MANIFESTO_NOTA)}"
  validate_download_file "$S0_MAN" 524288 && validate_download_file "$S0_SIG" 64 64 \
   || s0_die "manifesto/assinatura fora do contrato de transporte" "a atualização servida veio fora do padrão."
  s0_verify_manifest "$S0_MAN" "$S0_SIG" "$S0_PUB" "$S0_META" \
   || s0_die "assinatura inválida ou manifesto sem o artefato do atualizador" "a atualização servida não passou na conferência de assinatura."
  # shellcheck disable=SC1090
  . "$S0_META"   # version, updater_sha256, updater_bytes, updater_url (url fixa, ja validada)
  S0_MAN_SHA="$(sha256sum "$S0_MAN" | awk '{print $1}')" || s0_die "sha256sum do manifesto falhou" "não consegui conferir a atualização."
  release_identity_acceptable "$version" "$S0_MAN_SHA" "${S0_INST_VER:-0.0.0}" "${S0_INST_DIG:-}" \
   || s0_die "origem=$MANIFESTO_ORIGEM serve $version, instalada ${S0_INST_VER:-?} (digest ${S0_INST_DIG:-sem}): recusado por downgrade/replay" "a atualização servida é uma versão que não posso aplicar por cima da instalada (mais antiga, ou a mesma com assinatura diferente)."
  # nome casa o cleanup do corpo (leon-update.*) e NAO contem 'update-pago.sh'.
  S0_CAND="$(mktemp "${TMPDIR:-/tmp}/leon-update.XXXXXX")" || s0_die "mktemp falhou" "não consegui criar arquivo temporário (disco cheio?)."
  baixa_artefato_verificado "$S0_CENTRAL" "$updater_url" "$S0_CAND" "$((updater_bytes + 1))" "$updater_sha256" "$updater_bytes" 3 \
   || s0_die "download do atualizador falhou (espelho e central, ou sha diferente do manifesto)" "não consegui baixar a atualização agora. Tente /atualiza mais tarde."
  s0_log "atualizador baixado; origem=$ARTEFATO_ORIGEM"
  verify_signed_artifact "$S0_CAND" "$updater_sha256" "$updater_bytes" "atualizador"
  # literal partido de proposito: o inteiro nunca pode existir neste arquivo.
  S0_FLAG="--dangerously-bypass-approvals-and-"'sandbox'
  if LC_ALL=C grep -q -- "$S0_FLAG" "$S0_CAND"; then
    s0_die "atualizador servido carrega flag proibida" "a atualização servida veio com defeito e eu barrei a troca."
  fi
  grep -q 'verify_release_manifest' "$S0_CAND" && grep -q 'LEON-STAGE0-BEGIN' "$S0_CAND" \
   || s0_die "atualizador servido não tem stage0 (release anterior a esta?)" "a central está servindo um atualizador antigo; recusei por segurança."
  bash -n "$S0_CAND" 2>/dev/null \
   || s0_die "atualizador servido falhou no teste de sintaxe" "a versão nova veio com defeito e eu barrei a troca."
  chmod 0700 "$S0_CAND" || s0_die "chmod do atualizador falhou" "não consegui preparar a atualização."
  rm -f -- "$S0_MAN" "$S0_SIG" "$S0_PUB" "$S0_META" 2>/dev/null || true
  S0_MAN=""; S0_SIG=""; S0_PUB=""; S0_META=""
  trap - EXIT INT TERM
  s0_log "atualizador $version (${updater_sha256:0:12}) conferido: assinatura, sha, tamanho, sintaxe; origem=$MANIFESTO_ORIGEM; passando o comando"
  export LEON_INSTALL_DIR="$INSTALL_DIR" LEON_UPDATE_BLINDADO=1 LEON_UPDATE_COPIA="$S0_CAND"
  exec /usr/bin/env bash "$S0_CAND" "$@"
fi
# --- LEON-STAGE0-END ----------------------------------------------------------

# ARQUIVOS DO RUNTIME NO MANIFESTO DE INTEGRIDADE — DEFINIDOS FORA DO CONGELADO.
# A cabeca STAGE0 (linha 1 ate LEON-STAGE0-END) e a unica peca que nao se autocura na
# frota: mexer nela obriga a recalcular o sha esperado da cabeca, e casa presa numa versao
# velha para de alcancar a release nova. Por isso a lista de arquivos do runtime NAO e
# editada la em cima. A cabeca fica byte a byte como estava, e a lista nova entra aqui
# embaixo, junto com a redefinicao da funcao que a consome.
#
# A cabeca nunca chama write_runtime_files_manifest (conferido: nenhuma chamada entre a
# linha 1 e o END); quem chama e o corpo, la pelo fim do arquivo. Entao redefinir a funcao
# depois do END e seguro e vale sempre — em bash a ultima definicao ganha, e ela ja esta
# no lugar muito antes da unica chamada.
LEON_RUNTIME_FILES="bridge.cjs capabilities.json
  appserver/adapter.cjs appserver/index.cjs
  lib-motores/codex-appserver.cjs lib-motores/claude.cjs lib-motores/index.cjs
  lib/onboarding.js lib/meta-connect.js lib/meta-graph.js lib/license.js
  workers/piper.js workers/edge-tts.js workers/hostinger-health.cjs"

# Esta e a definicao QUE VALE (redefine a gemea congelada la em cima, de proposito).
# A unica diferenca e a lista: aqui ela sai de LEON_RUNTIME_FILES, e cai no default
# historico se a variavel nao existir — updater antigo que so tenha a copia congelada
# segue gravando exatamente o que gravava antes.
write_runtime_files_manifest() {
  local stage="$1"
  local destination="$stage/.leon-runtime-files.sha256"
  local rel
  : > "$destination"
  for rel in ${LEON_RUNTIME_FILES:-bridge.cjs capabilities.json \
    appserver/adapter.cjs appserver/index.cjs \
    lib-motores/codex-appserver.cjs lib/onboarding.js lib/meta-connect.js lib/meta-graph.js lib/license.js \
    workers/piper.js workers/edge-tts.js workers/hostinger-health.cjs}; do
    [ -f "$stage/$rel" ] && [ ! -L "$stage/$rel" ] || continue
    printf '%s  %s\n' "$(sha256sum "$stage/$rel" | awk '{print $1}')" "$rel" >> "$destination"
  done
  chmod 0600 "$destination"
}

validate_runtime_roots() {
  local require_exists="${1:-0}"
  "$PYTHON_BIN" - "$require_exists" "$HOME" "$INSTALL_DIR" "$LEON_DATA_DIR" "$CODEX_HOME_DIR" \
    "$LEON_SKILLS_DIR" "$LEON_TMPDIR" "$LEON_WORK_AREA" "$LEON_STATE_DIR" \
    "$LEON_MISSIONS_DIR" "$LEON_PROMISES_DIR" "$LEON_DATA_DIR/persona" \
    "$LEON_DATA_DIR/brain" "$LEON_MISSION_OUTPUT_DIR" "$HOME/.ssh" <<'PY'
import os, stat, sys

require_exists = sys.argv[1] == "1"
names = ["home", "runtime", "data", "codex", "skills", "tmp", "work", "state",
         "mission_control", "promise_control", "persona", "brain", "mission_output", "ssh"]
paths = dict(zip(names, map(os.path.abspath, sys.argv[2:])))
home = paths["home"]

def contains(parent, child):
    try:
        return os.path.commonpath([parent, child]) == parent
    except ValueError:
        return False

if not os.path.isdir(home) or os.path.islink(home) or os.path.realpath(home) != home:
    raise SystemExit("home must be a real directory without symlinks")
for name, target in paths.items():
    if name == "home":
        continue
    if target == home or not contains(home, target):
        raise SystemExit(f"{name} must be a strict descendant of home")
    cursor = home
    for part in os.path.relpath(target, home).split(os.sep):
        cursor = os.path.join(cursor, part)
        try:
            info = os.lstat(cursor)
        except FileNotFoundError:
            break
        if stat.S_ISLNK(info.st_mode):
            raise SystemExit(f"symlink component rejected in {name}: {cursor}")
        if cursor != target and not stat.S_ISDIR(info.st_mode):
            raise SystemExit(f"non-directory parent rejected in {name}: {cursor}")
    if os.path.lexists(target):
        info = os.lstat(target)
        if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode) or os.path.realpath(target) != target:
            raise SystemExit(f"{name} is not a real directory")
    elif require_exists and name not in ("skills", "ssh"):
        raise SystemExit(f"{name} directory is missing")

protected = [paths[k] for k in ("runtime", "codex", "skills", "ssh")]
writable = [paths[k] for k in ("work", "brain", "tmp", "mission_output")]
control = [paths[k] for k in ("state", "mission_control", "promise_control", "persona")]
for left in writable:
    for right in protected:
        if contains(left, right) or contains(right, left):
            raise SystemExit(f"writable/protected overlap rejected: {left} <> {right}")
for index, left in enumerate(writable):
    for right in writable[index + 1:]:
        if contains(left, right) or contains(right, left):
            raise SystemExit(f"writable roots overlap: {left} <> {right}")
for left in writable:
    for right in control:
        if contains(left, right) or contains(right, left):
            raise SystemExit(f"model-writable/control overlap rejected: {left} <> {right}")
if contains(paths["runtime"], paths["data"]) or contains(paths["data"], paths["runtime"]):
    raise SystemExit("runtime and data directories must be disjoint")
PY
}

audit_skills_archive() {
  "$PYTHON_BIN" - "$1" <<'PY'
import posixpath,sys,tarfile
try: members=tarfile.open(sys.argv[1],"r:gz").getmembers()
except (OSError,tarfile.TarError): raise SystemExit(1)
if not members or len(members)>4096: raise SystemExit(1)
seen={}; root=False; manifest=False; total=0
for member in members:
    raw=member.name
    if not raw or raw.startswith("/") or "\\" in raw or any(ord(c)<32 for c in raw): raise SystemExit(1)
    name=posixpath.normpath(raw)
    if name in ("",".","..") or name.startswith("../"): raise SystemExit(1)
    if name=="leon-skills":
        if not member.isdir(): raise SystemExit(1)
        root=True
    elif not name.startswith("leon-skills/"): raise SystemExit(1)
    elif not (member.isdir() or member.isfile()): raise SystemExit(1)
    if name in seen: raise SystemExit(1)
    seen[name]="dir" if member.isdir() else "file"
    if member.isfile():
        total+=member.size
        if member.size>64*1024*1024 or total>256*1024*1024: raise SystemExit(1)
        if name=="leon-skills/skills-manifest.json": manifest=True
for name in seen:
    parts=name.split("/")
    for i in range(1,len(parts)):
        if seen.get("/".join(parts[:i]))=="file": raise SystemExit(1)
if not root or not manifest: raise SystemExit(1)
PY
}

validate_skills_manifest() {
  "$PYTHON_BIN" - "$1" <<'PY'
import hashlib,json,os,posixpath,re,stat,sys
root=os.path.abspath(sys.argv[1]); mp=os.path.join(root,"skills-manifest.json")
try:
 st=os.lstat(mp)
 if not stat.S_ISREG(st.st_mode) or st.st_nlink!=1 or st.st_size>512_000: raise ValueError()
 m=json.load(open(mp,encoding="utf-8"))
except Exception: raise SystemExit(1)
if set(m)!={"capabilities","content_tree_format","content_tree_sha256","excluded","files","kind","placeholders","schema","skill_count","skills","source"}: raise SystemExit(1)
# Release A transicional: aceita o catálogo MINIMAL (2 fixas pinadas) OU o CURATED (>=30, validação estrutural).
if m["schema"]!=2: raise SystemExit(1)
if not isinstance(m["skills"],list) or m["skill_count"]!=len(m["skills"]): raise SystemExit(1)
if not all(isinstance(s,str) and re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}",s) and s not in (".","..") for s in m["skills"]) or len(set(m["skills"]))!=len(m["skills"]): raise SystemExit(1)
if m["kind"]=="leon-codex-minimal-skills":
 if m["skills"]!=["soft-critico-copy","soft-designer"] or m["skill_count"]!=2: raise SystemExit(1)
elif m["kind"]=="leon-codex-curated-skills":
 if m["skill_count"]<30: raise SystemExit(1)
else:
 raise SystemExit(1)
if m["placeholders"]!={"@@LEON_SKILLS_DIR@@":"absolute read-only skills directory","@@LEON_WORK_AREA@@":"absolute user work directory"}: raise SystemExit(1)
# capabilities: metadado declaratorio, nao gate de seguranca. Exigimos o campo presente e do tipo objeto,
# sem pin de igualdade (o catalogo curado declara {catalog_scope,credentials_collected_in_chat,runtime_paths_normalized}).
if not isinstance(m["capabilities"],dict): raise SystemExit(1)
# Sem pin de commit (o catálogo curado atualiza): valida só repositório esperado e árvore limpa.
if not isinstance(m["source"],dict) or set(m["source"])!={"commit","dirty","repository"}: raise SystemExit(1)
if m["source"]["repository"]!="https://github.com/molinateston/soft.git" or m["source"]["dirty"] is not False: raise SystemExit(1)
if not re.fullmatch(r"[0-9a-f]{40}",str(m["source"]["commit"])): raise SystemExit(1)
entries={}; paths=[]; lines=[]
for item in m["files"]:
 if not isinstance(item,dict) or set(item)!={"path","sha256","bytes","mode"}: raise SystemExit(1)
 rel=item["path"]
 if not isinstance(rel,str) or not rel or rel.startswith("/") or "\\" in rel or posixpath.normpath(rel)!=rel or rel in entries: raise SystemExit(1)
 if any(p in ("",".","..") or p.casefold()=="keys" or p==".env" for p in rel.split("/")) or rel.split("/",1)[0] not in m["skills"]: raise SystemExit(1)
 if not re.fullmatch(r"[0-9a-f]{64}",str(item["sha256"])) or not isinstance(item["bytes"],int) or not 0<=item["bytes"]<=64*1024*1024 or item["mode"] not in ("0400","0500"): raise SystemExit(1)
 entries[rel]=item; paths.append(rel)
if paths!=sorted(paths,key=lambda p:p.encode()): raise SystemExit(1)
actual=[]
for base,dirs,names in os.walk(root,topdown=True,followlinks=False):
 for d in dirs:
  si=os.lstat(os.path.join(base,d))
  if not stat.S_ISDIR(si.st_mode) or stat.S_ISLNK(si.st_mode): raise SystemExit(1)
 for name in names:
  rel=os.path.relpath(os.path.join(base,name),root).replace(os.sep,"/")
  if rel!="skills-manifest.json": actual.append(rel)
if sorted(actual,key=lambda p:p.encode())!=paths: raise SystemExit(1)
for rel in paths:
 full=os.path.join(root,*rel.split("/")); si=os.lstat(full); item=entries[rel]
 if not stat.S_ISREG(si.st_mode) or si.st_nlink!=1: raise SystemExit(1)
 raw=open(full,"rb").read(); digest=hashlib.sha256(raw).hexdigest(); mode=f"{stat.S_IMODE(si.st_mode):04o}"
 if len(raw)!=item["bytes"] or digest!=item["sha256"] or mode!=item["mode"]: raise SystemExit(1)
 low=raw.lower()
 # Frente D: o catálogo curado cita "Claude"/"Codex" legitimamente (é o motor do produto),
 # então o veto ao literal "claude" saiu. O veto a "openclaw" (ferramenta interna do dono),
 # a private key e a bypasspermissions CONTINUA — o catálogo já é purgado de openclaw, então
 # este veto é defesa em profundidade e não deve disparar.
 if (b"open"+b"claw") in low or b"bypasspermissions" in low or b"-----begin private key-----" in low: raise SystemExit(1)
 # veto por PREFIXO a caminho privado do dono que por acaso sobreviva à sanitização do builder
 if b"/home/" in low or b"/root/" in low or b".openclaw" in low or b"leomolina" in low or b"leonardomolina" in low or b"raizonline" in low: raise SystemExit(1)
 lines.append(f"{digest}\t{len(raw)}\t{mode}\t{rel}\n".encode())
fmt="sha256<TAB>bytes<TAB>mode4<TAB>path<LF>; payload files only; path bytewise ascending"
if m["content_tree_format"]!=fmt or hashlib.sha256(b"".join(lines)).hexdigest()!=m["content_tree_sha256"]: raise SystemExit(1)
if any(f"{s}/SKILL.md" not in entries for s in m["skills"]): raise SystemExit(1)
PY
}

normalize_skills_catalog() {
  "$PYTHON_BIN" - "$1" "$2" "$3" <<'PY'
import json,os,sys
root,skills_dir,work_area=map(os.path.abspath,sys.argv[1:]); mp=os.path.join(root,"skills-manifest.json")
m=json.load(open(mp,encoding="utf-8")); entries={x["path"]:x for x in m["files"]}
for base,_,_ in os.walk(root): os.chmod(base,0o700)
for rel,item in entries.items():
 full=os.path.join(root,*rel.split("/")); raw=open(full,"rb").read()
 if b"@@LEON_" in raw:
  text=raw.decode("utf-8").replace("@@LEON_SKILLS_DIR@@",skills_dir).replace("@@LEON_WORK_AREA@@",work_area)
  if "@@LEON_" in text: raise SystemExit(1)
  raw=text.encode()
 tmp=full+".leon-new"; fd=os.open(tmp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,"O_NOFOLLOW",0),0o600)
 try: os.write(fd,raw); os.fsync(fd)
 finally: os.close(fd)
 os.replace(tmp,full); os.chmod(full,int(item["mode"],8))
os.unlink(mp)
for base,_,names in os.walk(root):
 for name in names:
  if b"@@LEON_" in open(os.path.join(base,name),"rb").read(): raise SystemExit(1)
for base,_,_ in sorted(os.walk(root),key=lambda x:x[0].count(os.sep),reverse=True): os.chmod(base,0o500)
PY
}

installed_skills_digest() {
  "$PYTHON_BIN" - "$1" <<'PY'
import hashlib,os,stat,sys
root=os.path.abspath(sys.argv[1]); lines=[]
if not os.path.isdir(root) or os.path.islink(root): raise SystemExit(1)
for base,dirs,names in os.walk(root,topdown=True,followlinks=False):
 for d in dirs:
  st=os.lstat(os.path.join(base,d))
  if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode) or stat.S_IMODE(st.st_mode)!=0o500: raise SystemExit(1)
 for name in names:
  full=os.path.join(base,name); rel=os.path.relpath(full,root).replace(os.sep,"/"); st=os.lstat(full)
  if not stat.S_ISREG(st.st_mode) or st.st_nlink!=1 or stat.S_IMODE(st.st_mode) not in (0o400,0o500): raise SystemExit(1)
  raw=open(full,"rb").read()
  if b"@@LEON_" in raw: raise SystemExit(1)
  lines.append((rel.encode(),f"{hashlib.sha256(raw).hexdigest()}\t{len(raw)}\t{stat.S_IMODE(st.st_mode):04o}\t{rel}\n".encode()))
print(hashlib.sha256(b"".join(line for _,line in sorted(lines))).hexdigest())
PY
}

validate_dedicated_codex_cli() {
  "$PYTHON_BIN" - "$1" "$2" "$3" <<'PY'
import os,stat,sys
binary,data_dir,version=sys.argv[1:]
data_dir=os.path.abspath(data_dir); release=os.path.join(data_dir,"codex-cli","releases",version)
expected=os.path.join(release,"bin","codex")
if os.path.abspath(binary)!=expected or not os.path.isdir(data_dir) or os.path.islink(data_dir): raise SystemExit(1)
cursor=data_dir
for part in ("codex-cli","releases",version,"bin"):
 cursor=os.path.join(cursor,part); info=os.lstat(cursor)
 if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode) or info.st_uid!=os.getuid() or stat.S_IMODE(info.st_mode)&0o022: raise SystemExit(1)
leaf=os.lstat(expected)
if leaf.st_uid!=os.getuid() or leaf.st_nlink!=1 or not (stat.S_ISREG(leaf.st_mode) or stat.S_ISLNK(leaf.st_mode)): raise SystemExit(1)
resolved=os.path.realpath(expected)
if os.path.commonpath([release,resolved])!=release: raise SystemExit(1)
target=os.stat(expected)
if not stat.S_ISREG(target.st_mode) or target.st_uid!=os.getuid() or stat.S_IMODE(target.st_mode)&0o022 or not os.access(expected,os.X_OK): raise SystemExit(1)
PY
}

# ---- SUBIDA DO MOTOR PELO CAMINHO NATIVO (2.4.34) --------------------------
# O proprio Codex CLI sabe se atualizar: `codex update` existe na 0.147 (a da frota) e por
# baixo roda `npm install -g @openai/codex`. Com npm_config_prefix apontando pra um prefixo
# nosso, ele instala LA DENTRO e nao encosta em nada global da VPS.
#
# Regra de ouro: a casa nunca pode ficar sem motor. Por isso a instalacao acontece num
# prefixo de ENCENACAO, a versao nova entra como um IRMAO novo em codex-cli/releases/ e a
# release velha fica intacta no disco ate o fim. Quem decide qual roda e o LEON_CODEX_CLI_VERSION
# que o .env do stage recebe — se qualquer passo aqui falhar, o .env sai com a versao ANTIGA
# e o update do bridge segue inteiro. Best-effort de verdade: nenhum caminho daqui da fatal.
#
# Ecoa a versao nova no stdout quando (e so quando) ela ja esta validada no lugar definitivo.
subir_codex_cli_nativo() {
  local bin_atual="$1" data_dir="$2" minima="$3" tx="$4" node_bin="$5"
  local staging="$data_dir/codex-cli/.upgrade-$tx" nova release_novo bin_novo
  local pkg="$staging/lib/node_modules/@openai/codex"

  rm -rf -- "$staging" 2>/dev/null || true
  mkdir -p -- "$staging" 2>/dev/null || return 1
  chmod 0700 "$staging" 2>/dev/null || true
  # Registra pro cleanup_main: morte por sinal no meio do npm nao deixa lixo no disco.
  CODEX_CLI_STAGING="$staging"

  # O `codex update` herda o PATH pra achar o npm/node. Damos o node dedicado primeiro.
  # Teto de 5 min: sem rede o npm fica pendurado e o /atualiza nao pode parar por causa disso.
  if ! env npm_config_prefix="$staging" \
        npm_config_audit=false npm_config_fund=false npm_config_update_notifier=false \
        PATH="$(dirname "$node_bin"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        timeout 300 "$bin_atual" update >/dev/null 2>&1; then
    rm -rf -- "$staging" 2>/dev/null || true
    return 1
  fi

  # A partir daqui so confio no que o disco mostra: o `codex update` pode sair 0 e ter
  # instalado nada (npm resolveu do cache, prefixo ignorado, pacote parcial).
  [ -d "$pkg" ] || { rm -rf -- "$staging" 2>/dev/null || true; return 1; }
  nova="$("$PYTHON_BIN" - "$pkg/package.json" <<'PY'
import json,re,sys
try: value=str(json.load(open(sys.argv[1],encoding="utf-8"))["version"])
except Exception: raise SystemExit(1)
if not re.fullmatch(r"(?:0|[1-9]\d*)(?:\.(?:0|[1-9]\d*)){2}",value): raise SystemExit(1)
print(value)
PY
)" || { rm -rf -- "$staging" 2>/dev/null || true; return 1; }

  # Nao aceito andar pra tras nem ficar abaixo do que a release pede.
  semver_ge "$nova" "$minima" || { rm -rf -- "$staging" 2>/dev/null || true; return 1; }

  release_novo="$data_dir/codex-cli/releases/$nova"
  bin_novo="$release_novo/bin/codex"
  # Ja tenho essa versao no disco (retomada de um /atualiza anterior): nao mexo, so valido.
  if [ ! -e "$release_novo" ]; then
    # O layout dedicado e bin/codex -> ../lib/node_modules/@openai/codex/bin/codex.js.
    # O npm ja monta lib/node_modules e um bin/codex; normalizo o link pra relativo, que e
    # o que o validate_dedicated_codex_cli exige (realpath tem que cair dentro do release).
    [ -f "$pkg/bin/codex.js" ] || { rm -rf -- "$staging" 2>/dev/null || true; return 1; }
    rm -f -- "$staging/bin/codex" 2>/dev/null || true
    mkdir -p -- "$staging/bin" 2>/dev/null || true
    ln -s ../lib/node_modules/@openai/codex/bin/codex.js "$staging/bin/codex" 2>/dev/null \
      || { rm -rf -- "$staging" 2>/dev/null || true; return 1; }
    chmod 0700 "$pkg/bin/codex.js" 2>/dev/null || true
    chmod -R go-w -- "$staging" 2>/dev/null || true
    mkdir -p -- "$data_dir/codex-cli/releases" 2>/dev/null || true
    # Rename no mesmo filesystem: ou o irmao novo aparece inteiro, ou nao aparece.
    mv -- "$staging" "$release_novo" 2>/dev/null \
      || { rm -rf -- "$staging" 2>/dev/null || true; return 1; }
  else
    rm -rf -- "$staging" 2>/dev/null || true
  fi
  # O prefixo de encenacao acabou (virou release ou foi apagado). Solto do cleanup pra
  # nao deixar um caminho morto apontando pra perto da release nova.
  CODEX_CLI_STAGING=""

  # Prova no lugar definitivo: mesma validacao que o updater faz na versao viva, e o binario
  # tem que responder --version com a versao que promete. Se reprovar, NAO removo o irmao
  # (pode ser uma instalacao boa de outra origem), so devolvo erro e a casa segue na antiga.
  validate_dedicated_codex_cli "$bin_novo" "$data_dir" "$nova" || return 1
  [ "$(PATH="$(dirname "$node_bin"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
      "$bin_novo" --version 2>/dev/null \
      | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+([_-][A-Za-z0-9.-]+)?$/) { print $i; exit } }')" \
    = "$nova" ] || return 1

  printf '%s\n' "$nova"
}

# ---- CLI DO CLAUDE: O IRMAO DO DE CIMA (23/09) -------------------------------
# Caso real de cliente: Claude Code 2.1.246 com claude-opus-5 no .env. Toda fala morria com
# "does not support this model; version 2.1.280 or newer is required" e nada na frota subia o
# CLI do Claude: o instalador so instala quando falta, o atualizador so cuidava do Codex.
# O instalador (root) poe o CLI com o npm DO SISTEMA em /usr. Este atualizador roda como o
# usuario do LEON (sem sudo; a unit tem ProtectSystem=full), entao o MESMO comando
# (`npm install -g --prefix=<prefixo> @anthropic-ai/claude-code@latest`) vai pra um prefixo do
# usuario, no molde do Codex: encenacao, prova de versao, rename atomico pra
# claude-cli/releases/<versao>, e o .env do stage ganha CLAUDE_BIN apontando pro novo.
# O CLI velho fica intacto: qualquer falha deixa a casa no binario de antes. Best-effort de
# verdade: nenhum caminho daqui da fatal. O bridge tem o mesmo passo em segundo plano
# (atualizaClaudeCliEmSegundoPlano), disparado quando o CLI recusa o modelo.
LEON_CLAUDE_CLI_MINIMA="${LEON_CLAUDE_CLI_MINIMA:-2.1.280}"
CLAUDE_CLI_PACOTE="@anthropic-ai/claude-code@latest"

# `|| true` obrigatorio: o script roda com set -Eeuo pipefail. Binario quebrado (node ausente no
# shebang, exit != 0) ou timeout (124) no --version passaria pelo pipefail e derrubaria o /atualiza
# inteiro na atribuicao, justo na casa com CLI estragado que este passo existe pra consertar.
# Versao ilegivel vira string vazia, que o chamador ja trata como "abaixo da minima".
claude_cli_versao() {
  PATH="${2:-/usr/local/bin:/usr/bin:/bin}" timeout 20 "$1" --version 2>/dev/null \
    | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }' \
    || true
}

# Onde o bridge acha o CLI do Claude (mesma ordem de lib-motores/claude.cjs resolveClaudeBin):
# CLAUDE_BIN do .env, prefixos do usuario, depois os do sistema. Ecoa o caminho ou nada.
resolve_claude_cli() {
  local informado="$1" c
  if [ -n "$informado" ] && [ -x "$informado" ]; then printf '%s\n' "$informado"; return 0; fi
  for c in "$HOME"/.leon/node/releases/*/bin/claude "$HOME/.npm-global/bin/claude" "$HOME/.local/bin/claude" \
           /usr/local/bin/claude /usr/bin/claude /snap/bin/claude; do
    [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# Ecoa o caminho do binario novo quando (e so quando) ele ja esta validado no lugar definitivo.
subir_claude_cli() {
  local data_dir="$1" minima="$2" tx="$3" node_bin="$4"
  local raiz="$data_dir/claude-cli" staging nova release_novo bin_novo caminho
  staging="$raiz/.upgrade-$tx"
  caminho="$(dirname "$node_bin"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  rm -rf -- "$staging" 2>/dev/null || true
  mkdir -p -- "$staging" 2>/dev/null || return 1
  chmod 0700 "$raiz" "$staging" 2>/dev/null || true
  CLAUDE_CLI_STAGING="$staging"
  if ! env npm_config_audit=false npm_config_fund=false npm_config_update_notifier=false \
        npm_config_cache="$raiz/.npm-cache" PATH="$caminho" \
        timeout 300 npm install -g --prefix="$staging" "$CLAUDE_CLI_PACOTE" >/dev/null 2>&1; then
    rm -rf -- "$staging" 2>/dev/null || true; CLAUDE_CLI_STAGING=""; return 1
  fi
  nova="$(claude_cli_versao "$staging/bin/claude" "$caminho")"
  if [ -z "$nova" ] || ! semver_ge "$nova" "$minima" 2>/dev/null; then
    rm -rf -- "$staging" 2>/dev/null || true; CLAUDE_CLI_STAGING=""; return 1
  fi
  release_novo="$raiz/releases/$nova"
  if [ ! -e "$release_novo" ]; then
    chmod -R go-w -- "$staging" 2>/dev/null || true
    mkdir -p -- "$raiz/releases" 2>/dev/null || true
    mv -- "$staging" "$release_novo" 2>/dev/null \
      || { rm -rf -- "$staging" 2>/dev/null || true; CLAUDE_CLI_STAGING=""; return 1; }
  else
    rm -rf -- "$staging" 2>/dev/null || true
  fi
  CLAUDE_CLI_STAGING=""
  bin_novo="$release_novo/bin/claude"
  [ "$(claude_cli_versao "$bin_novo" "$caminho")" = "$nova" ] || return 1
  printf '%s\n' "$bin_novo"
}

validate_dedicated_node() {
  "$PYTHON_BIN" - "$1" "$2" "$3" <<'PY'
import os,stat,sys
binary,data_dir,version=sys.argv[1:]
data_dir=os.path.abspath(data_dir); release=os.path.join(data_dir,"node","releases",version)
expected=os.path.join(release,"bin","node")
if os.path.abspath(binary)!=expected or not os.path.isdir(data_dir) or os.path.islink(data_dir): raise SystemExit(1)
cursor=data_dir
for part in ("node","releases",version,"bin"):
 cursor=os.path.join(cursor,part); info=os.lstat(cursor)
 if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode) or info.st_uid!=os.getuid() or stat.S_IMODE(info.st_mode)&0o022: raise SystemExit(1)
leaf=os.lstat(expected)
if not stat.S_ISREG(leaf.st_mode) or leaf.st_nlink!=1 or leaf.st_uid!=os.getuid(): raise SystemExit(1)
if stat.S_IMODE(leaf.st_mode)&0o077 or not os.access(expected,os.X_OK): raise SystemExit(1)
if os.path.commonpath([release,os.path.realpath(expected)])!=release: raise SystemExit(1)
PY
}

validate_service_unit() {
  "$PYTHON_BIN" - "$1" "$2" "$3" "${4:-$(id -un)}" "$TEST_MODE" <<'PY'
import os,stat,sys
path,runtime,node,user,test_mode=sys.argv[1:]
try:
 info=os.lstat(path)
 if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode) or info.st_nlink!=1: raise ValueError()
 expected_uid=os.getuid() if test_mode=="1" else 0
 if info.st_uid!=expected_uid or stat.S_IMODE(info.st_mode)&0o022: raise ValueError()
 fd=os.open(path,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0))
 try: before=os.fstat(fd); raw=os.read(fd,131073); after=os.fstat(fd)
 finally: os.close(fd)
 if len(raw)>131072 or (info.st_dev,info.st_ino)!=(before.st_dev,before.st_ino): raise ValueError()
 if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or (before.st_dev,before.st_ino,before.st_size)!=(after.st_dev,after.st_ino,after.st_size) or after.st_nlink!=1: raise ValueError()
 text=raw.decode("utf-8"); values={}
 for line in text.splitlines():
  if not line or line.lstrip().startswith(("#",";")) or line.startswith("["): continue
  if "=" not in line: raise ValueError()
  key,value=line.split("=",1); values.setdefault(key,[]).append(value)
 for forbidden in ("EnvironmentFile","ExecStartPost","ExecStop","ExecReload"):
  if forbidden in values: raise ValueError()
 def one(key,expected):
  if values.get(key)!=[expected]: raise ValueError()
 one("User",user); one("Group",user); one("WorkingDirectory",runtime)
 one("ExecStartPre",f"{node} --check {runtime}/bridge.cjs")
 one("ExecStart",f"{node} {runtime}/bridge.cjs")
 one("Environment",f'"PATH={os.path.dirname(node)}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"')
 required={
  "KillMode":"control-group","UMask":"0077","PrivateTmp":"true","ProtectSystem":"full",
  "RestrictSUIDSGID":"true","LockPersonality":"true",
  "RestrictRealtime":"true","ProtectKernelTunables":"true","ProtectKernelModules":"true",
  "ProtectControlGroups":"true","PrivateDevices":"true","CapabilityBoundingSet":"",
  "AmbientCapabilities":"","SystemCallArchitectures":"native","TasksMax":"512",
  "MemoryMax":"90%","NoNewPrivileges":"true",
 }
 for key,value in required.items(): one(key,value)
 # contencao de memoria (25/09): a unit antiga (MemoryHigh=80%, sem teto de swap) segue
 # aceita pra casa que ainda nao reinstalou; a nova vem inteira ou nao vale (sem mistura).
 perfil_antigo={"MemoryHigh":["80%"],"MemorySwapMax":None,"OOMPolicy":None}
 perfil_novo={"MemoryHigh":["infinity"],"MemorySwapMax":["1G"],"OOMPolicy":["continue"]}
 if not any(all(values.get(k)==v for k,v in perfil.items()) for perfil in (perfil_antigo,perfil_novo)): raise ValueError()
except Exception: raise SystemExit(1)
PY
}

# BAIXA COM ESPELHO (23/08) aposentada em 23/09: a ordem inverteu (GitHub primeiro, central de
# reserva) e o download passou a conferir sha e tamanho do manifesto antes de aceitar a origem.
# Ver baixa_artefato_verificado, na cabeca do arquivo.

normalize_agent_base() {
  local agent_base="$1" skills_dir="$2"
  [ -f "$agent_base" ] || return 0
  "$PYTHON_BIN" - "$agent_base" "$skills_dir" "$INSTALL_DIR" "$LEON_TMPDIR" "$CODEX_HOME_DIR" \
    "$BRAIN_DIR" "$LEON_WORK_AREA" "$LEON_MISSION_OUTPUT_DIR" <<'PY'
import os, re, sys

path, skills_dir, install_dir, tmp_dir, codex_home, brain_dir, work_area, mission_output_dir = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    text = handle.read()
replacements = {
    "LEON_SKILLS_DIR": skills_dir,
    "LEON_INSTALL_DIR": install_dir,
    "LEON_TMPDIR": tmp_dir,
    "LEON_CODEX_HOME": codex_home,
    "LEON_BRAIN_DIR": brain_dir,
    "LEON_WORK_AREA": work_area,
    "LEON_MISSION_OUTPUT_DIR": mission_output_dir,
}
for key, value in replacements.items():
    if not value or not os.path.isabs(value):
        raise SystemExit(f"invalid runtime path for {key}")
    text = text.replace(f"@@{key}@@", value)
    text = re.sub(rf"\$\{{?{key}\}}?", lambda _match, v=value: v, text)
# So sinaliza TEMPLATE nao-substituido (as chaves de replacements). $LEON_ENV_FILE e uma
# VARIAVEL DE RUNTIME real (o bridge a exporta), citada de proposito na doutrina F4, nao e
# placeholder de build, entao a regex ampla \$LEON_ a barrava por engano e emperrava a base.
if "@@LEON_" in text or re.search(r"\$\{?(?:" + "|".join(replacements) + r")\}?", text):
    raise SystemExit("unresolved LEON placeholder in AGENT-BASE")
marker = "## Skills LEON Codex (diretiva canônica)"
if marker not in text:
    text = text.rstrip() + "\n\n" + marker + "\n"
    text += f"O catálogo canônico é {skills_dir}. Abra o SKILL.md nele. "
    text += "Resolva scripts, assets e outros caminhos relativos a partir da pasta da própria skill.\n"
tmp = path + ".leon-new"
with open(tmp, "w", encoding="utf-8") as handle:
    handle.write(text)
os.chmod(tmp, os.stat(path).st_mode & 0o777)
os.replace(tmp, path)
PY
}

# GUARDA DA DOUTRINA ANTES DE PROMOVER (2.4.35). O bridge morre no turno se sobrar qualquer
# placeholder LEON nao resolvido na doutrina. Ate a 2.4.34 o updater promovia a release e a casa
# so descobria no primeiro turno, muda (caso Delano). Aqui rodamos a MESMA logica da guarda do
# bridge contra a doutrina, a persona e o nucleo empacotados, ANTES do rename de promocao. Se
# sobrar placeholder, NAO promove: a casa fica na versao de antes e o dono e avisado com a causa.
# O bridge resolve (a) os 7 caminhos de runtime, (b) qualquer LEON_X presente no ambiente do
# servico. O que a casa exporta esta no .env, entao o .env entra na conta, junto de LEON_ENV_FILE.
validate_doutrina_sem_placeholder() {
  local stage="$1" persona_dir="$2" env_file="$3" saida
  saida="$("$PYTHON_BIN" - "$stage" "$persona_dir" "$env_file" "$INSTALL_DIR" <<'PY'
import os, re, sys
stage, persona_dir, env_file, install_dir = sys.argv[1:5]
# Nomes que a casa REALMENTE tem na hora do turno: o ambiente do processo, tudo o que o .env
# define, e LEON_ENV_FILE, que o bridge exporta sozinho (bridge.cjs process.env.LEON_ENV_FILE).
conhecidos = {k for k in os.environ if k.startswith("LEON_") and os.environ[k]}
conhecidos.add("LEON_ENV_FILE")
conhecidos.update({
    "LEON_SKILLS_DIR", "LEON_INSTALL_DIR", "LEON_TMPDIR", "LEON_CODEX_HOME",
    "LEON_BRAIN_DIR", "LEON_WORK_AREA", "LEON_MISSION_OUTPUT_DIR",
})
try:
    with open(env_file, encoding="utf-8", errors="replace") as fh:
        for linha in fh:
            m = re.match(r"\s*(?:export\s+)?(LEON_[A-Za-z0-9_]+)\s*=\s*(\S)", linha)
            if m:
                conhecidos.add(m.group(1))
except OSError:
    pass

alvos = []
base = os.path.join(stage, "AGENT-BASE.md")
if os.path.isfile(base):
    alvos.append(base)
for peca in ("NUCLEO-LEON.md", "_MOTOR-CLAUDE.md", "_MOTOR-CODEX.md", "_REGRAS-DURAS.md", "CAMINHOS-CANONICOS.md"):
    for raiz in (persona_dir, stage):
        caminho = os.path.join(raiz, peca)
        if os.path.isfile(caminho):
            alvos.append(caminho)
            break

padrao = re.compile(r"@@(LEON_[A-Z0-9_]+)@@|\$\{(LEON_[A-Z0-9_]+)\}|\$(LEON_[A-Z0-9_]+)")
for caminho in alvos:
    try:
        with open(caminho, encoding="utf-8", errors="replace") as fh:
            texto = fh.read()
    except OSError:
        continue
    for achado in padrao.finditer(texto):
        nome = achado.group(1) or achado.group(2) or achado.group(3)
        # @@NOME@@ e template de build: tinha que ter sido substituido, entao sempre reprova.
        if achado.group(1) or nome not in conhecidos:
            print(f"{nome}|{os.path.basename(caminho)}")
            raise SystemExit(1)
raise SystemExit(0)
PY
)" && return 0
  DOUTRINA_PLACEHOLDER="${saida%%|*}"
  DOUTRINA_PLACEHOLDER_ARQ="${saida##*|}"
  return 1
}

validate_curated_base_manifest() {
  local package_root="$1"
  "$PYTHON_BIN" - "$package_root" <<'PY'
import hashlib, json, os, re, stat, sys
root=os.path.abspath(sys.argv[1])
try:
    raw=open(os.path.join(root,"base-manifest.json"),"rb").read()
    if len(raw)>512_000: raise ValueError("manifest too large")
    manifest=json.loads(raw)
except Exception as exc: raise SystemExit(f"invalid manifest: {exc}")
if manifest.get("schema")!=2 or manifest.get("kind")!="leon-codex-curated-base": raise SystemExit("identity")
if not re.fullmatch(r"[0-9a-f]{40}",str((manifest.get("source") or {}).get("commit",""))): raise SystemExit("commit")
security=manifest.get("security") or {}
for key in ("devices_allowed","external_symlinks_allowed","hardlinks_allowed","private_keys_allowed","setuid_or_setgid_allowed"):
    if security.get(key) is not False: raise SystemExit(f"unsafe {key}")
files,allowlist=manifest.get("files"),manifest.get("allowlist")
if not isinstance(files,list) or not isinstance(allowlist,list) or not files: raise SystemExit("files")
if allowlist!=sorted(allowlist,key=lambda p:p.encode()) or len(set(allowlist))!=len(allowlist): raise SystemExit("allowlist")
entries={}
for item in files:
    if not isinstance(item,dict) or set(item)!={"path","sha256","bytes","mode"}: raise SystemExit("entry")
    rel=item.get("path")
    if not isinstance(rel,str) or not rel or not rel.isascii() or rel.startswith("/") or "\\" in rel: raise SystemExit("path")
    if any(part in ("",".","..") or part.casefold()=="keys" or part==".env" for part in rel.split("/")): raise SystemExit("unsafe path")
    if rel in entries or not re.fullmatch(r"[0-9a-f]{64}",str(item.get("sha256",""))): raise SystemExit("hash")
    if not isinstance(item.get("bytes"),int) or not 0<=item["bytes"]<=536_870_912 or item.get("mode") not in ("0600","0700"): raise SystemExit("metadata")
    entries[rel]=item
if list(entries)!=allowlist: raise SystemExit("order")
actual=[]
for base,dirs,names in os.walk(root,topdown=True,followlinks=False):
    for dirname in dirs:
        if stat.S_ISLNK(os.lstat(os.path.join(base,dirname)).st_mode): raise SystemExit("symlink")
    for name in names:
        rel=os.path.relpath(os.path.join(base,name),root).replace(os.sep,"/")
        if rel!="base-manifest.json": actual.append(rel)
if sorted(actual,key=lambda p:p.encode())!=allowlist: raise SystemExit("tree")
lines=[]
for rel in allowlist:
    full=os.path.join(root,*rel.split("/")); info=os.lstat(full)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1: raise SystemExit("not regular")
    content=open(full,"rb").read(); entry=entries[rel]; digest=hashlib.sha256(content).hexdigest(); mode=f"{stat.S_IMODE(info.st_mode):04o}"
    if len(content)!=entry["bytes"] or digest!=entry["sha256"] or mode!=entry["mode"]: raise SystemExit(f"mismatch {rel}")
    lines.append(f"{digest}\t{len(content)}\t{mode}\t{rel}\n".encode())
fmt="sha256<TAB>bytes<TAB>mode4<TAB>path<LF>; payload files only; path bytewise ascending"
if manifest.get("content_tree_format")!=fmt or hashlib.sha256(b"".join(lines)).hexdigest()!=manifest.get("content_tree_sha256"): raise SystemExit("tree hash")
PY
}

safe_copy_state_file() {
  local source="$1" destination="$2" kind="$3"
  "$PYTHON_BIN" - "$source" "$destination" "$kind" <<'PY'
import json, os, re, stat, sys
source,destination,kind=sys.argv[1:]
limits={"env":256*1024,"sessions":16*1024*1024,"topics":2*1024*1024,"onboarding":64*1024,"meta":64*1024}
if kind not in limits: raise SystemExit(1)
try:
    info=os.lstat(source)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or info.st_size>limits[kind]: raise SystemExit(1)
    fd=os.open(source,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0))
    try: before=os.fstat(fd); raw=os.read(fd,before.st_size+1); after=os.fstat(fd)
    finally: os.close(fd)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or before.st_size>limits[kind]: raise SystemExit(1)
    if info.st_dev!=before.st_dev or info.st_ino!=before.st_ino: raise SystemExit(1)
    if before.st_dev!=after.st_dev or before.st_ino!=after.st_ino or after.st_nlink!=1 or after.st_size!=before.st_size or len(raw)!=before.st_size: raise SystemExit(1)
    if re.search(br"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----",raw): raise SystemExit(1)
    if kind!="env":
        data=json.loads(raw)
        if not isinstance(data,dict) or (kind=="topics" and len(data)>1000) or (kind=="sessions" and len(data)>10000): raise SystemExit(1)
    else:
        text=raw.decode("utf-8")
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077: raise SystemExit(1)
        if "\x00" in text: raise SystemExit(1)
        seen_keys=set()
        for line in text.splitlines():
            if not line.strip() or line.lstrip().startswith("#"): continue
            match=re.fullmatch(r"\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*",line)
            if not match or match.group(1) in seen_keys: raise SystemExit(1)
            seen_keys.add(match.group(1))
except Exception: raise SystemExit(1)
temp=destination+".state-new"; flags=os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,"O_NOFOLLOW",0)
try:
    out=os.open(temp,flags,0o600)
    try: os.write(out,raw); os.fsync(out)
    finally: os.close(out)
    os.replace(temp,destination)
finally:
    try: os.unlink(temp)
    except FileNotFoundError: pass
PY
}

# ---- FAMILIA DO RUNTIME E LEDGER DE SALAS (17/09) --------------------------
# POR QUE ISTO EXISTE: medido hoje, 17/09, o bridge.cjs instalado nas casas de
# CLIENTE tem ZERO ocorrencias de _resolveSessionsFile e le o ledger de salas no
# caminho literal ${WORKDIR}/sessions.json, ou seja INSTALL_DIR/sessions.json. O
# runtime NOVO resolve o ledger por _resolveSessionsFile e le em
# LEON_STATE_DIR/sessions.json (default LEON_DATA_DIR/state). Trocar um pelo
# outro sem copiar o ledger faz a casa acordar com TODAS as salas vazias e log
# verde (na casa do dono seriam 359 salas). A copia validada abaixo e o que
# falta para o cliente receber o agente novo de verdade.
#
# A familia e decidida pelo CODIGO QUE VAI RODAR, nunca por numero de versao,
# sha conhecido ou campo do manifesto: o manifesto assinado nao tem campo de
# familia e verify_release_manifest reprova chave desconhecida. Dois sinais que
# precisam CONCORDAR; qualquer outra combinacao e 'indeterminada' e vira recusa
# nomeada ANTES de mutar (um bridge transicional com os dois literais nao pode
# ser chutado para nenhum lado).
# LEON 2.0 (2.7.0): o bridge.cjs da casa e a PORTA que carrega leon2/leon.cjs (tres linhas, gerada pelo
# gerar-pacote-cliente.sh). A unit, a validacao da unit e o portao do zero seguem iguais; o que muda e
# o que se confere dentro da casa: leon2/ no lugar do bridge antigo.
bridge_e_leon2() {  # bridge_e_leon2 <bridge.cjs>
  [ -f "$1" ] && [ ! -L "$1" ] && [ "$(wc -c < "$1")" -lt 4096 ] \
    && LC_ALL=C grep -q "^require('./leon2/leon.cjs');\$" -- "$1" 2>/dev/null \
    && [ -s "$(dirname "$1")/leon2/leon.cjs" ]
}
# node --check do 2.0 inteiro (porta, leon.cjs e as libs) numa casa ou stage.
leon2_sintaxe_ok() {  # leon2_sintaxe_ok <runtime>
  local f
  "$NODE_BIN" --check "$1/leon2/leon.cjs" >/dev/null 2>&1 || return 1
  for f in "$1"/leon2/lib/*.cjs "$1"/leon2/bin/*; do
    [ -f "$f" ] || return 1
    "$NODE_BIN" --check "$f" >/dev/null 2>&1 || return 1
  done
}

familia_do_bridge() {
  local arquivo="$1" tem_fn=0 tem_uso=0 tem_legado=0
  if [ ! -f "$arquivo" ] || [ -L "$arquivo" ]; then printf 'indeterminada\n'; return 0; fi
  # O 2.0 le as conversas onde a familia nova le (LEON_SESSIONS_FILE, senao LEON_STATE_DIR/sessions.json),
  # entao a porta e da familia nova, nos dois sentidos (2.6 -> 2.0 e a volta 2.0 -> 2.6).
  if bridge_e_leon2 "$arquivo"; then printf 'nova\n'; return 0; fi
  if LC_ALL=C grep -q 'function _resolveSessionsFile(' -- "$arquivo" 2>/dev/null; then tem_fn=1; fi
  if LC_ALL=C grep -Eq 'SESS_FILE[[:space:]]*=[[:space:]]*_resolveSessionsFile\(\)' -- "$arquivo" 2>/dev/null; then tem_uso=1; fi
  if LC_ALL=C grep -Eq 'SESS_FILE[[:space:]]*=[[:space:]]*`\$\{WORKDIR\}/sessions\.json`' -- "$arquivo" 2>/dev/null; then tem_legado=1; fi
  if [ "$tem_fn" = 1 ] && [ "$tem_uso" = 1 ] && [ "$tem_legado" = 0 ]; then printf 'nova\n'; return 0; fi
  if [ "$tem_legado" = 1 ] && [ "$tem_fn" = 0 ] && [ "$tem_uso" = 0 ]; then printf 'legada\n'; return 0; fi
  printf 'indeterminada\n'
}

# Chaves de SALA (nao descartaveis) de um mapa de sessoes, uma por linha.
# Predicado IDENTICO ao sessaoDescartavel do bridge: corta em '#p', separa por
# ':', descarta quando p[0] ou p[1] e 'missao' ou 'promise'. Conferir por
# CONTAGEM TOTAL reprovaria release boa: as duas familias podam no boot as
# entradas de missao/promessa mortas (7 dias, sem rollout no disco). 'SALA NUNCA
# SAI' e o contrato escrito no bridge e e o que a conferencia cobra.
ledger_salas_de() {
  "$PYTHON_BIN" - "$1" <<'PY'
import json,sys
try: data=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: raise SystemExit(1)
if not isinstance(data,dict): raise SystemExit(1)
def descartavel(k):
    p=str(k).split("#p")[0].split(":")
    return p[0] in ("missao","promise") or (len(p)>1 and p[1] in ("missao","promise"))
for k in sorted(data):
    if not descartavel(k): sys.stdout.write(k+"\n")
PY
}

# Prepara o diretorio de estado que o runtime ENTRANTE vai resolver, com as
# MESMAS exigencias do bridge novo (_resolveSessionsFile + _recusaComponenteSimbolico):
# nenhum componente simbolico, diretorio real 0700 sem bits de grupo/outros e
# dono igual a quem roda a unit. O bridge novo recusa o boot com exit 78 quando
# isso nao bate, e recusar aqui acontece com a casa ainda intacta.
# argv[2] = INSTALL_DIR, so para descobrir o dono da casa: o atualizador roda
# como o usuario da unit (o script ja assume isso em validate_service_unit) e a
# unica excecao e a bancada rodando como root, onde ajustamos o dono.
ledger_prepara_destino() {
  "$PYTHON_BIN" - "$1" "$2" <<'PY'
import os,stat,sys
alvo,casa=sys.argv[1:]
if not os.path.isabs(alvo) or os.path.normpath(alvo)!=alvo: raise SystemExit(2)
dono=os.stat(casa).st_uid
atual=os.sep
for parte in alvo.split(os.sep)[1:]:
    atual=os.path.join(atual,parte)
    try: st=os.lstat(atual)
    except FileNotFoundError: continue
    if stat.S_ISLNK(st.st_mode): raise SystemExit(3)
    if atual!=alvo and not stat.S_ISDIR(st.st_mode): raise SystemExit(4)
os.makedirs(alvo,mode=0o700,exist_ok=True)
st=os.lstat(alvo)
if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode): raise SystemExit(5)
if stat.S_IMODE(st.st_mode)&0o022: os.chmod(alvo,stat.S_IMODE(st.st_mode)&~0o022)
if os.geteuid()==0:
    if os.lstat(alvo).st_uid!=dono: os.chown(alvo,dono,-1)
elif os.lstat(alvo).st_uid!=os.getuid() or dono!=os.getuid(): raise SystemExit(6)
if os.stat(alvo).st_mode&0o022: raise SystemExit(7)
PY
}

# A3 (revisao Astra 17/09): o runtime NOVO HONRA LEON_SESSIONS_FILE, mas so quando
# o caminho e absoluto, normalizado e mora DIRETO em LEON_STATE_DIR (bridge.cjs
# _resolveSessionsFile: path.isAbsolute + path.resolve igual + path.dirname ===
# resolve(LEON_STATE_DIR); fora disso o boot morre com exit 78). Entao a presenca da
# chave NUNCA pode abortar o update: se o caminho e honrado, ele vira o DESTINO do
# ledger e a chave fica ativa; se nao e, a chave vira comentario guardado e o destino
# volta ao padrao. Este predicado e a copia fiel do que o bridge cobra.
ledger_sessions_file_honrado() {
  "$PYTHON_BIN" - "$1" "$2" <<'PY'
import os,sys
alvo,raiz=sys.argv[1:]
alvo=alvo.strip()
if not alvo: raise SystemExit(1)
if not os.path.isabs(alvo) or os.path.normpath(alvo)!=alvo: raise SystemExit(2)
if os.path.dirname(alvo)!=os.path.normpath(os.path.abspath(raiz)): raise SystemExit(3)
PY
}

# Pre-voo do arquivo migrado: o mesmo predicado que _resolveSessionsFile aplica
# no boot. Reprovar aqui e fatal ANTES do 'committed', com rollback_inline
# desfazendo os dois renames e sem nenhum restart.
ledger_pre_voo() {
  "$PYTHON_BIN" - "$1" <<'PY'
import os,stat,sys
arquivo=sys.argv[1]; raiz=os.path.dirname(arquivo)
if not os.path.isabs(arquivo) or os.path.normpath(arquivo)!=arquivo: raise SystemExit(2)
d=os.lstat(raiz)
if not stat.S_ISDIR(d.st_mode) or stat.S_ISLNK(d.st_mode) or (d.st_mode&0o022): raise SystemExit(3)
f=os.lstat(arquivo)
if not stat.S_ISREG(f.st_mode) or stat.S_ISLNK(f.st_mode) or f.st_nlink!=1 \
   or stat.S_IMODE(f.st_mode)!=0o600: raise SystemExit(4)
if os.geteuid()!=0 and (d.st_uid!=os.getuid() or f.st_uid!=os.getuid()): raise SystemExit(5)
PY
}

# ---- .ENV DO CLIENTE: O ARQUIVO E DO DONO (23/09, desenho estrutural) --------
# POR QUE MUDOU DE NOVO: tres rodadas de remendo (allowlist na escrita, bloco gerenciado que
# vencia o dono, quarentena #LEON-GUARDADO) reprovaram na mesma classe: /atualiza trocava
# TTS_PROVIDER, VOICE_REPLY, CODEX_REASONING_EFFORT, DRAIN_SEG e as pastas pelo padrao,
# comentava chave de integracao e tirava a integracao do ar. A regra agora e uma so:
#   - toda linha do .env do dono sai BYTE A BYTE (leon_preserva env-acrescenta);
#   - o que falta entra no FIM, com o padrao do produto (ou com o valor que uma versao velha
#     escondeu em #LEON-GUARDADO fora-da-allowlist);
#   - a unica excecao e a lista PRODUTO_ENV do preserva-casa.py, e so com valor invalido
#     provado aqui (CLI abaixo do minimo que este update subiu, binario que nao executa);
#   - .env que o bridge recusaria (linha fora do formato, chave repetida, valor com byte de
#     controle) NAO e consertado por nos: o update para antes de mexer em qualquer coisa e diz
#     a linha. Consertar seria reescrever o arquivo do dono.
rewrite_runtime_env() {
  local env_file="$1" pad trocas rel saida rc codex_model atual
  pad="${env_file}.preserva-padroes"
  trocas="${env_file}.preserva-trocas"
  rel="${env_file}.preserva-relatorio"
  saida="${env_file}.preserva-saida"
  rm -f -- "$pad" "$trocas" "$rel" "$saida"
  if [ "$LEON_ENGINE_CASA" = claude ]; then
    # Lei do dono (23/09 noite): o padrao do Claude e o Opus, nunca o Sonnet (so entra se faltar a chave).
    codex_model="claude-opus-5-5"
  else
    codex_model="${CODEX_MODEL_EFETIVO:-gpt-5.6-sol}"
  fi
  # PADROES: o que a casa recebe SO se nao tiver a chave. Mesmo conteudo do antigo bloco
  # gerenciado; a diferenca e que ele nao vence mais o dono.
  # CODEX_HOME / CLAUDE_CONFIG_DIR (24/09, rodada 3): quando faltam, entra a pasta que o bridge
  # JA usa (homeDoMotor: ~/.codex ou ~/.claude quando tem credencial), nunca a do LEON. Gravar
  # <LEON_DATA_DIR>/codex numa casa que roda no ~/.codex do dono tirava o login, os MCPs, os
  # profiles e os providers dele, e o LEON ficava "sem token".
  (
    umask 077
    cat > "$pad" <<PADROES
ENGINE=$LEON_ENGINE_CASA
ENGINE_DEFAULT=$LEON_ENGINE_CASA
LEON_DATA_DIR=$LEON_DATA_DIR
BRAIN_DIR=$BRAIN_DIR
PERSONA_DIR=$PERSONA_DIR
LEON_SKILLS_DIR=$LEON_SKILLS_DIR
LEON_SKILLS_PESSOAIS_DIR=$(skills_personal_dir)
LEON_TMPDIR=$LEON_TMPDIR
LEON_WORK_AREA=$LEON_WORK_AREA
LEON_STATE_DIR=$LEON_STATE_DIR
LEON_MISSIONS_DIR=$LEON_MISSIONS_DIR
LEON_PROMISES_DIR=$LEON_PROMISES_DIR
LEON_MISSION_OUTPUT_DIR=$LEON_MISSION_OUTPUT_DIR
WORK_DIR=$INSTALL_DIR
VOICE_HANDLER=$INSTALL_DIR/workers/voice-handler.py
VOICE_PY=$LEON_DATA_DIR/whisper-venv/bin/python3
EDGE_TTS_WORKER=$INSTALL_DIR/workers/edge-tts.js
EDGE_TTS_PY=$LEON_DATA_DIR/edgetts-venv/bin/python3
PIPER_WORKER=$INSTALL_DIR/workers/piper.js
PIPER_BIN=$LEON_DATA_DIR/piper-venv/bin/piper
PIPER_MODEL=$LEON_DATA_DIR/voices/piper/pt_BR-faber-medium.onnx
MEMVIVA_FILE=$MEMVIVA_FILE
ASSUNTOS_FILE=$ASSUNTOS_FILE
TTS_PROVIDER=disabled
VOICE_REPLY=mirror
DRAIN_SEG=300
PADROES
    if [ "$LEON_ENGINE_CASA" = codex ]; then
      cat >> "$pad" <<PADROES
LEON_CODEX_ONLY=1
CODEX_APP_SERVER=1
CODEX_HOME=$(leon_preserva home-do-motor "$env_file" codex "$CODEX_HOME_DIR")
CODEX_BIN=$CODEX_BIN_PATH
CODEX_MODEL=$codex_model
CODEX_REASONING_EFFORT=high
LEON_CODEX_CLI_VERSION=$LEON_CODEX_CLI_VERSION
PADROES
    else
      cat >> "$pad" <<PADROES
CLAUDE_CONFIG_DIR=$(leon_preserva home-do-motor "$env_file" claude "$LEON_DATA_DIR/claude")
CODEX_MODEL=$codex_model
CODEX_REASONING_EFFORT=high
PADROES
    fi
    [ -z "${CLAUDE_BIN_NOVO:-}" ] || printf 'CLAUDE_BIN=%s\n' "$CLAUDE_BIN_NOVO" >> "$pad"
    : > "$trocas"
  ) || return 1
  # TROCAS: so chave da lista do produto, e so com o valor atual provado invalido.
  if [ "$LEON_ENGINE_CASA" = codex ]; then
    atual="$(env_get_from "$env_file" CODEX_BIN)"
    if [ "$CODEX_CLI_SUBIU" = 1 ]; then
      # o CLI da casa estava abaixo do minimo da release e este update instalou o novo: a versao
      # velha no .env e invalida, e o binario pinado dela tambem. Binario do DONO (fora de
      # <LEON_DATA_DIR>/codex-cli): nem ele nem a versao trocam (24/09, rodada 5). Quem decide
      # "dentro ou fora" e o env-acrescenta, pelo leitor do bridge; aqui so se pede.
      printf 'LEON_CODEX_CLI_VERSION=%s\n' "$LEON_CODEX_CLI_VERSION" >> "$trocas"
      printf 'CODEX_BIN=%s\n' "$CODEX_BIN_PATH" >> "$trocas"
    elif [ -n "$atual" ] && [ ! -x "$atual" ] && [ "$TEST_MODE" != 1 ]; then
      printf 'CODEX_BIN=%s\n' "$CODEX_BIN_PATH" >> "$trocas"
    fi
  fi
  [ -z "${CLAUDE_BIN_NOVO:-}" ] || printf 'CLAUDE_BIN=%s\n' "$CLAUDE_BIN_NOVO" >> "$trocas"
  rc=0
  leon_preserva env-acrescenta "$env_file" "$pad" "$trocas" "$saida" "$rel" "$LEON_DATA_DIR" || rc=$?
  if [ "$rc" -ne 0 ]; then
    ENV_RECUSA="$(sed -n 's/^recusa //p' "$rel" 2>/dev/null | tr '\n' ' ')"
    rm -f -- "$pad" "$trocas" "$rel" "$saida"
    return "$rc"
  fi
  # NOMES (nunca valor) do que mudou vao pro log da casa.
  if grep -q '^\(nova\|religada\) ' "$rel"; then
    say "   .env: nenhuma linha tua mudou; acrescentei no fim: $(sed -n 's/^\(nova\|religada\) //p' "$rel" | tr '\n' ' ')"
  fi
  if grep -q '^religada ' "$rel"; then
    say "   .env: voltaram a valer (uma versao antiga tinha comentado): $(sed -n 's/^religada //p' "$rel" | tr '\n' ' ')"
  fi
  if grep -q '^trocada ' "$rel"; then
    say "   .env: chaves do produto com valor invalido, corrigidas: $(sed -n 's/^trocada //p' "$rel" | tr '\n' ' ')"
  fi
  if grep -q '^binario-do-dono ' "$rel"; then
    say "   .env: CODEX_BIN aponta pra binario teu, fora da pasta do produto: mantive."
  fi
  chmod 0600 "$saida"
  mv -f -- "$saida" "$env_file"
  rm -f -- "$pad" "$trocas" "$rel"
}

# O vigia (scripts/update-verdict.sh) vem do pacote-base e e trocado a cada update; o
# handoff do /atualiza (bridge sob NoNewPrivileges nao dispara o updater, o cron dispara)
# precisa ser regravado no stage toda vez, senao o proximo /atualiza volta a morrer.
injetar_handoff_update_verdict() {
  local vigia="$1" tmp
  [ -f "$vigia" ] || return 0
  # v2 (24/09, rodada 5): o bloco v1 exportava a linha crua do .env; o leon-base publicado ja traz
  # o v1, entao o v1 e TROCADO pelo v2 (mesma posicao), nao so pulado.
  if grep -q 'LEON-HANDOFF-UPDATE v2' "$vigia"; then
    return 0
  fi
  tmp="$vigia.leon-new"
  python3 - "$vigia" "$tmp" <<'PY' || { rm -f -- "$tmp"; return 1; }
import os, re, sys
src, dst = sys.argv[1:]
text = open(src, encoding="utf-8").read()
bloco = r'''# --- LEON-HANDOFF-UPDATE v2 (gravado pelo instalador e pelo atualizador) ------------------
# O bridge roda numa unit com NoNewPrivileges (setuid/setgid nao valem la
# dentro), entao ele nao dispara o update-pago.sh: grava so o PEDIDO em
# .update-request.json e este vigia, que roda no cron do usuario FORA da
# unit, executa o atualizador por ele. Pedido com mais de 30 minutos vence:
# apaga, anota e nao dispara nada.
PEDIDO_UPDATE="$BRIDGE_DIR/.update-request.json"
if [ -f "$PEDIDO_UPDATE" ]; then
  campo_pedido() {  # le string ou numero do pedido, sem depender de jq
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^,\"}]*\)\"\{0,1\}.*/\1/p" "$PEDIDO_UPDATE" 2>/dev/null | head -1
  }
  anota_pedido() { printf '%s [vigia] %s\n' "$(date '+%F %T')" "$*" >> "$BRIDGE_DIR/upgrade.log" 2>/dev/null || true; }
  IDADE_PEDIDO=$(( $(date +%s) - $(stat -c %Y "$PEDIDO_UPDATE" 2>/dev/null || echo 0) ))
  if [ "$IDADE_PEDIDO" -gt 1800 ]; then
    rm -f "$PEDIDO_UPDATE"
    anota_pedido "pedido de update vencido (${IDADE_PEDIDO}s), descartado sem disparar"
  elif [ ! -f "$BRIDGE_DIR/update-pago.sh" ]; then
    rm -f "$PEDIDO_UPDATE"
    anota_pedido "pedido de update sem update-pago.sh no runtime, descartado"
  elif [ -z "$(pgrep -u "$(id -u)" -f "update-pago.sh" 2>/dev/null)" ]; then
    CHAT_PEDIDO="$(campo_pedido chatId)"
    THREAD_PEDIDO="$(campo_pedido threadId)"
    [ "$THREAD_PEDIDO" = "null" ] && THREAD_PEDIDO=""
    rm -f "$PEDIDO_UPDATE"
    anota_pedido "handoff: disparando update-pago.sh fora da unit (chat ${CHAT_PEDIDO:-?})"
    (
      cd "$BRIDGE_DIR" || exit 0
      # O .env vira ambiente pelo MESMO leitor do bridge (aspas, comentario no fim, espaco,
      # CRLF): o atualizador responde "--preserva env-exporta" com export CHAVE=<valor com aspas
      # de shell>. A linha crua exportada de antes levava aspas e comentario literais. Atualizador
      # sem essa entrada (nao acontece: vigia e atualizador vem da mesma versao) nao recebe nada.
      if grep -q 'LEON-PRESERVA-ENTRADA v1' "$BRIDGE_DIR/update-pago.sh" 2>/dev/null; then
        ENV_DO_DONO="$(bash "$BRIDGE_DIR/update-pago.sh" --preserva env-exporta "$BRIDGE_DIR/.env" 2>/dev/null)" \
          && eval "$ENV_DO_DONO"
      fi
      nohup bash "$BRIDGE_DIR/update-pago.sh" "$CHAT_PEDIDO" "$THREAD_PEDIDO" >/dev/null 2>&1 &
    )
  fi
fi
# --- fim LEON-HANDOFF-UPDATE ------------------------------------------------
'''
velho = re.compile(r'^# --- LEON-HANDOFF-UPDATE v1 .*?^# --- fim LEON-HANDOFF-UPDATE -*\n', re.M | re.S)
anchor = re.compile(r'^\[ -f "\$RECIBO" \] \|\| exit 0.*$', re.M)
m = anchor.search(text)
if velho.search(text):
    text = velho.sub(lambda _m: bloco, text, count=1)
elif m is None:
    # Pacote sem a linha esperada: entra logo depois de RECIBO= (BRIDGE_DIR ja existe ali).
    m2 = re.search(r'^RECIBO="\$BRIDGE_DIR/\.update-pending\.json".*\n', text, re.M)
    if m2 is None:
        raise SystemExit("vigia sem os pontos de ancoragem esperados")
    text = text[:m2.end()] + bloco + text[m2.end():]
else:
    text = text[:m.start()] + bloco + text[m.start():]
fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o700)
with os.fdopen(fd, "w", encoding="utf-8") as out:
    out.write(text)
os.chmod(dst, os.stat(src).st_mode & 0o777)
PY
  if ! bash -n "$tmp" 2>/dev/null; then
    rm -f -- "$tmp"
    return 1
  fi
  mv -f -- "$tmp" "$vigia"
}

write_codex_config_candidate() {
  local destination="$1"
  # Decisão do dono 04/09: mesmo modo do mestre, acesso total. Provado no 99: com
  # default_permissions = "leon" + seções [permissions.leon.*] o Codex mantém o
  # isolamento ligado mesmo sob sandbox_mode = "danger-full-access" (cai em
  # "bwrap: setting up uid map: Permission denied"); o modo só vale quando o perfil
  # NÃO existe. Por isso o perfil e o [sandbox_workspace_write] saíram do config.
  # ESFORÇO POR TAREFA (2.4.31): o config nasce em "medium". O bridge roteia o esforço por
  # fala (low no trivial, high na missão e no pedido de raciocínio), então este valor é só o
  # piso de quem roda o Codex fora da ponte. "high" cravado aqui era raciocínio invisível
  # cobrado em todo turno, e é o que estourava a cota do dono no plano Plus.
  cat > "$destination" <<EOF
model = "${CODEX_MODEL_EFETIVO:-gpt-5.6-sol}"
model_reasoning_effort = "medium"
preferred_auth_method = "chatgpt"
sandbox_mode = "danger-full-access"
approval_policy = "never"
allow_login_shell = false

[projects."$INSTALL_DIR"]
trust_level = "untrusted"

[projects."$LEON_WORK_AREA"]
trust_level = "trusted"

[features]
multi_agent_v2 = true


[shell_environment_policy]
inherit = "core"
ignore_default_excludes = false

[shell_environment_policy.filters]
"*TOKEN*" = "exclude"
"*SECRET*" = "exclude"
"*PASSWORD*" = "exclude"
"*API_KEY*" = "exclude"
"BOT_TOKEN" = "exclude"
EOF
  # Preserva a conexão Meta (meta-connect): se o dono já conectou, o bloco MCP re-entra no
  # candidate. Sem isto, TODO update regenerava o config.toml do template e desconectava o
  # Meta em silêncio (achado da auditoria 26/08). MODO-FILTRO (idêntico ao que
  # lib/meta-connect.js:writeMcpConfig gera): o Codex spawna o filtro local
  # meta-mcp-codex-filter.cjs, que aplica a allowlist de leitura (5 ads_insights_*) e lê o
  # token DIRETO do .meta-token.json — por isso NÃO há bearer_token_env_var nem url-crua. A
  # url-crua expunha os 106 tools da Meta (incl. escrita) e cada /atualiza a regravava, matando
  # o filtro instalado pelo meta-connect (achado Fable 30/08).
  # 24/09 (rodada 3): o token mora onde o bridge grava, tokenPath(WORKDIR) com WORKDIR = WORK_DIR
  # do .env ou o runtime. Procurar so no runtime tirava o meta-ads da casa com WORK_DIR proprio.
  local meta_wd
  meta_wd="$(leon_preserva env-valor "$ENV_READ_SAFE" WORK_DIR 2>/dev/null)" || meta_wd=""
  case "$meta_wd" in /*) ;; '') meta_wd="$INSTALL_DIR" ;; *) meta_wd="$INSTALL_DIR/$meta_wd" ;; esac
  if [ -f "$meta_wd/.meta-token.json" ] || [ -f "$INSTALL_DIR/.meta-token.json" ]; then
    cat >> "$destination" <<METAEOF

[mcp_servers.meta-ads]
command = "node"
args = ["$INSTALL_DIR/lib/meta-mcp-codex-filter.cjs"]
startup_timeout_sec = 20
tool_timeout_sec = 30
METAEOF
  fi
  chmod 0600 "$destination"
  "$PYTHON_BIN" - "$destination" <<'PY'
import sys
# Ubuntu 22.04 vem com Python 3.10, sem tomllib nativo (só 3.11+).
# O instalador garante tomli via pip nesse caso (A9); aqui só usamos o que existir.
try: import tomllib
except ImportError: import tomli as tomllib
data=tomllib.load(open(sys.argv[1],"rb"))
if data.get("approval_policy")!="never": raise SystemExit(1)
# Decisao do dono 04/09: cliente roda EXATAMENTE como o mestre, acesso total. O unico
# sandbox_mode aceito e danger-full-access; qualquer outro valor (ou a ausencia) reprova.
if data.get("sandbox_mode")!="danger-full-access": raise SystemExit(1)
# Provado no 99: perfil de permissoes nomeado mantem o isolamento ligado mesmo sob
# danger-full-access (bwrap uid map denied). Perfil no candidato = candidato reprovado.
if "default_permissions" in data: raise SystemExit(1)
if "permissions" in data: raise SystemExit(1)
if "sandbox_workspace_write" in data: raise SystemExit(1)
PY
}

# CONFIG.TOML DO CODEX (23/09, desenho estrutural). Dois casos, decididos pelo CODEX_HOME que o
# .env do dono declara (e o que o bridge usa):
#   - CODEX_HOME do DONO (fora de <LEON_DATA_DIR>/codex): o produto nao escreve config.toml
#     nenhum. O que o LEON precisa (aprovacao, sandbox, perfil) ja vai por thread nos
#     parametros do app-server (lib-motores/codex-appserver.cjs), nao pelo arquivo.
#   - CODEX_HOME do LEON: leon_preserva toml-funde. O texto do dono e a base; o molde so
#     acrescenta o que falta; a unica excecao e a lista de seguranca do preserva-casa.py.
#     Config ilegivel DE VERDADE (o leitor TOML do python recusa E o Codex pinado tambem
#     recusa): vai o molde e o do dono fica ao lado em config.toml.ilegivel-<tx>. O Codex le e
#     o python nao (BOM, tabela inline em varias linhas do TOML 1.1), python sem leitor TOML,
#     ou seguranca que nao cabe sem reescrever estrutura do dono: o config do dono fica
#     INTACTO e o log diz.
# 24/09 (rodada 2): a mesma fonte do install-leon.sh. Do dono = o .env declara outra pasta, OU
# <LEON_DATA_DIR>/codex e link (ou passa por link) pra fora, OU o config.toml dela e link (o
# LEON segue o config pessoal do dono; trocar o link por arquivo corta esse elo pra sempre).
codex_home_do_dono() {  # sai 0 quando o CODEX_HOME desta casa e do dono
  leon_preserva codex-home-do-dono "$ENV_READ_SAFE" "$LEON_DATA_DIR" >/dev/null 2>&1
}

funde_config_do_dono() {  # funde_config_do_dono <config atual> <molde> <candidato>
  local atual="$1" molde="$2" cand="$3" rel="$3.relatorio" rc
  rc=0
  LEON_PRESERVA_CODEX="${CODEX_BIN_PATH:-}" \
  LEON_PRESERVA_PATH="$(dirname "${NODE_BIN:-/usr/bin/node}"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    leon_preserva toml-funde "$atual" "$molde" "$cand" "$rel" "$INSTALL_DIR" || rc=$?
  case "$rc" in
    0)
      if grep -q '^acrescentada ' "$rel"; then
        say "   config.toml: nada teu mudou; acrescentei do molde: $(sed -n 's/^acrescentada //p' "$rel" | tr '\n' ' ')"
      fi
      if grep -q '^\(seguranca\|removida\) ' "$rel"; then
        say "   config.toml: ajuste de seguranca do produto: $(sed -n 's/^\(seguranca\|removida\) //p' "$rel" | tr '\n' ' ')"
      fi
      ;;
    2)
      cp -p -- "$molde" "$cand"
      printf 'ilegivel\n' > "$TX_DIR/config-ilegivel"
      say "   config.toml atual ilegivel ($(head -1 "$rel")): vai o molde e o teu fica ao lado em config.toml.ilegivel-$TX_ID."
      ;;
    3)
      rm -f -- "$cand"
      say "   config.toml: mantido INTACTO ($(head -1 "$rel")); o LEON segue pelos parametros do app-server."
      ;;
    *) rm -f -- "$rel"; return 1 ;;
  esac
  rm -f -- "$rel"
  return 0
}

tx_read() {
  local tx="$1" name="$2"
  cat "$tx/$name"
}

remove_finalize_cron() {
  local marker="$1" current filtered
  command -v "$CRONTAB_BIN" >/dev/null 2>&1 || return 0
  current="$($CRONTAB_BIN -l 2>/dev/null || true)"
  filtered="$(printf '%s\n' "$current" | grep -vF "$marker" || true)"
  printf '%s\n' "$filtered" | "$CRONTAB_BIN" - >/dev/null 2>&1 || true
}

restore_crontab_from_tx() {
  local tx="$1" had
  [ -f "$tx/had-crontab" ] || return 0
  had="$(tx_read "$tx" had-crontab)"
  if [ "$had" = "1" ] && [ -f "$tx/crontab.backup" ]; then
    "$CRONTAB_BIN" "$tx/crontab.backup" >/dev/null 2>&1
  elif [ "$had" = "0" ]; then
    "$CRONTAB_BIN" -r >/dev/null 2>&1 || true
  else
    return 1
  fi
}

# VOLTA (23/09, desenho estrutural): o config.toml volta BYTE A BYTE do backup, e so quando
# esta transacao o trocou (config-applied). A versao que estava ativa na hora da volta (pode ter
# mudanca do dono feita depois do update) fica ao lado em config.toml.pos-atualiza-<tx>.
restore_config_from_tx() {
  local tx="$1" config_path had_config applied tmp txid
  config_path="$(tx_read "$tx" config-path)"
  had_config="$(tx_read "$tx" had-config)"
  applied="$(cat "$tx/config-applied" 2>/dev/null || echo 1)"
  [ "$applied" = 1 ] || return 0
  txid="$(basename "$tx")"
  mkdir -p -- "$(dirname "$config_path")"
  if [ -f "$config_path" ] && ! { [ -f "$tx/config.backup" ] && cmp -s -- "$config_path" "$tx/config.backup"; }; then
    cp -p -- "$config_path" "${config_path}.pos-atualiza-$txid" 2>/dev/null || true
  fi
  if [ "$had_config" = "1" ] && [ -f "$tx/config.backup" ]; then
    tmp="${config_path}.leon-restore-$$"
    cp -p -- "$tx/config.backup" "$tmp"
    mv -f -- "$tmp" "$config_path"
  elif [ "$had_config" = "0" ]; then
    rm -f -- "$config_path"
  fi
  printf '0\n' > "$tx/config-applied"
}

# VOLTA (23/09): o .env do runtime velho volta BYTE A BYTE (ele viaja dentro do backup, que
# nenhum passo reescreve). O .env que estava ativo no runtime que voltou pra tras fica ao lado,
# com sufixo, pra nada que o dono mudou depois do update se perder. Nada e fundido.
guarda_env_pos_atualiza() {  # guarda_env_pos_atualiza <runtime restaurado> <runtime que saiu> <tx>
  local live="$1" saiu="$2" txid
  txid="$(basename "$3")"
  [ -f "$saiu/.env" ] && [ ! -L "$saiu/.env" ] || return 0
  if [ -f "$live/.env" ] && cmp -s -- "$saiu/.env" "$live/.env"; then return 0; fi
  install -m 0600 -- "$saiu/.env" "$live/.env.pos-atualiza-$txid" 2>/dev/null || true
}

restore_unit_from_tx() {
  local tx="$1" unit_path had_unit unit_applied tmp
  unit_applied="$(tx_read "$tx" unit-applied)"
  [ "$unit_applied" = "1" ] || return 0
  unit_path="$(tx_read "$tx" unit-path)"
  had_unit="$(tx_read "$tx" had-unit)"
  if [ "$TEST_MODE" != "1" ] && [ "$(id -u)" -ne 0 ]; then
    return 1
  fi
  if [ "$had_unit" = "1" ] && [ -f "$tx/unit.backup" ]; then
    tmp="${unit_path}.leon-restore-$$"
    install -m 0644 "$tx/unit.backup" "$tmp"
    mv -f -- "$tmp" "$unit_path"
  elif [ "$had_unit" = "0" ]; then
    rm -f -- "$unit_path"
  fi
  service_read daemon-reload >/dev/null 2>&1 || true
}

restore_service_state() {
  local tx="$1" was_active was_enabled
  was_active="$(tx_read "$tx" was-active)"
  was_enabled="$(tx_read "$tx" was-enabled)"
  if [ "$was_enabled" = "1" ]; then
    service_write enable "$SERVICE" >/dev/null 2>&1 || true
  else
    service_write disable "$SERVICE" >/dev/null 2>&1 || true
  fi
  if [ "$was_active" = "1" ]; then
    service_write start "$SERVICE" >/dev/null 2>&1 || true
  else
    service_write stop "$SERVICE" >/dev/null 2>&1 || true
  fi
}

restore_skills_from_tx() {
  local tx="$1" skills backup failed had_original applied
  skills="$(tx_read "$tx" skills-path 2>/dev/null || true)"
  backup="$(tx_read "$tx" skills-backup-path 2>/dev/null || true)"
  failed="$(tx_read "$tx" skills-failed-path 2>/dev/null || true)"
  had_original="$(tx_read "$tx" skills-had-original 2>/dev/null || true)"
  applied="$(tx_read "$tx" skills-applied 2>/dev/null || true)"
  [ -n "$skills" ] && [ -n "$backup" ] && [ -n "$failed" ] || return 0
  case "$skills" in "$HOME"/*) ;; *) return 1 ;; esac
  case "$backup" in "$HOME"/*) ;; *) return 1 ;; esac
  case "$failed" in "$HOME"/*) ;; *) return 1 ;; esac
  if [ -d "$backup" ] && [ ! -L "$backup" ]; then
    if [ -e "$skills" ]; then
      [ ! -e "$failed" ] || failed="${failed}-$(date -u +%s)"
      mv -- "$skills" "$failed" || return 1
    fi
    mv -- "$backup" "$skills" || return 1
    printf '0\n' > "$tx/skills-applied"
    return 0
  fi
  if [ "$had_original" = "0" ] && [ "$applied" = "1" ] && [ -e "$skills" ]; then
    [ ! -e "$failed" ] || failed="${failed}-$(date -u +%s)"
    mv -- "$skills" "$failed" || return 1
    printf '0\n' > "$tx/skills-applied"
  fi
}

# 0.7 (obra Fase 0) SEPARACAO catalogo do produto x skills do dono.
#
#   <LEON_SKILLS_DIR>              catalogo do PRODUTO. Trocado inteiro por rename a
#                                  cada release, como sempre foi. Nada do dono mora aqui.
#   <LEON_DATA_DIR>/skills-pessoais/  skills do DONO. O updater NUNCA toca: nao renomeia,
#                                  nao apaga, nao valida contra o manifesto assinado.
#
# Antes da separacao o unico catalogo era o do produto, e o rename da release levava junto
# qualquer skill que o dono tivesse posto la. A pasta pessoal e criada (vazia) no proprio
# update, entao a casa que atualiza uma vez ja passa a ter o lugar certo pra guardar.
skills_personal_dir() {
  # a pasta sai do leitor unico (leon_bases_do_dono no topo do atualizador e do finalizador);
  # chamada avulsa (ajudante de bancada) le o .env da casa aqui mesmo
  [ -n "${LEON_SKILLS_PESSOAIS_DIR:-}" ] || leon_bases_do_dono "$INSTALL_DIR/.env" >/dev/null 2>&1 || true
  printf '%s\n' "${LEON_SKILLS_PESSOAIS_DIR:-}"
}

# Cria a pasta pessoal se ainda nao existir, com as mesmas guardas do resto do updater:
# tem que ficar dentro da HOME, ser diretorio real (nao link) e pertencer a quem roda.
ensure_skills_personal_dir() {
  local dir; dir="$(skills_personal_dir)"
  case "$dir" in "$HOME"/*) ;; *) return 1 ;; esac
  if [ -e "$dir" ]; then
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
    return 0
  fi
  mkdir -m 0700 -p -- "$dir" 2>/dev/null || return 1
  return 0
}

# Prontidao: a casa so dispensa a quarentena do catalogo quando a pasta pessoal existe
# como diretorio real dentro da home. Enquanto nao existir, o backup fica.
skills_personal_dir_ready() {
  local dir; dir="$(skills_personal_dir)"
  case "$dir" in "$HOME"/*) ;; *) return 1 ;; esac
  [ -d "$dir" ] && [ ! -L "$dir" ]
}

remove_committed_skills_backup() {
  local skills="$1" backup="$2"
  [ -z "$backup" ] && return 0
  [ ! -e "$backup" ] && return 0
  "$PYTHON_BIN" - "$skills" "$backup" <<'PY'
import os, shutil, stat, sys
skills, backup = map(os.path.abspath, sys.argv[1:])
parent = os.path.dirname(skills)
try:
    if os.path.dirname(backup) != parent or not os.path.basename(backup).startswith(".skills-backup-"):
        raise ValueError()
    parent_info = os.lstat(parent)
    root_info = os.lstat(backup)
    if not stat.S_ISDIR(parent_info.st_mode) or stat.S_ISLNK(parent_info.st_mode):
        raise ValueError()
    if not stat.S_ISDIR(root_info.st_mode) or stat.S_ISLNK(root_info.st_mode):
        raise ValueError()
    if parent_info.st_uid != os.getuid() or root_info.st_uid != os.getuid():
        raise ValueError()
    # O catálogo antigo estava selado em 0500/0400. Abrimos somente diretórios
    # dentro do backup já validado; os.walk não segue links e shutil.rmtree
    # usa a implementação fd-safe disponível no Python desta release.
    for base, dirs, _ in os.walk(backup, topdown=True, followlinks=False):
        seen = os.lstat(base)
        if not stat.S_ISDIR(seen.st_mode) or stat.S_ISLNK(seen.st_mode) or seen.st_uid != os.getuid():
            raise ValueError()
        os.chmod(base, 0o700, follow_symlinks=False)
        for name in dirs:
            child = os.path.join(base, name)
            info = os.lstat(child)
            if stat.S_ISLNK(info.st_mode):
                continue
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
                raise ValueError()
    shutil.rmtree(backup)
    fd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0))
    try: os.fsync(fd)
    finally: os.close(fd)
except Exception:
    raise SystemExit(1)
PY
}

# ENSAIO DAS SKILLS (0.7, obra Fase 0). Mesmo padrao do LEON_TEST_RELEASE_HELPERS_ONLY
# acima: expoe as funcoes REAIS de skills pra prova de bancada, sem rede, sem systemd e
# sem release assinada. O teste chama a mesma funcao que o /atualiza chama; nao existe
# copia do comportamento no teste. Fora deste modo o bloco nao roda.
if [ "${LEON_TEST_SKILLS_HELPERS_ONLY:-0}" = "1" ]; then
  case "${1:-}" in
    personal-dir)       skills_personal_dir ;;
    # 17/09: as duas decisoes novas da migracao do ledger expostas cruas pra
    # bancada provar a MESMA funcao que o /atualiza chama, sem release assinada.
    ledger-familia)     familia_do_bridge "$2" ;;
    ledger-salas)       ledger_salas_de "$2" ;;
    # 17/09 (revisao Astra, A3): o predicado de LEON_SESSIONS_FILE e o guarda-chave
    # expostos crus, pra bancada provar a MESMA funcao que o /atualiza chama.
    ledger-sessoes)     ledger_sessions_file_honrado "$2" "$3" ;;
    personal-ensure)    ensure_skills_personal_dir ;;
    personal-ready)     skills_personal_dir_ready ;;
    backup-remove)      remove_committed_skills_backup "$2" "$3" ;;
    # troca do catalogo do produto: exatamente os dois renames do corpo (:2827).
    catalog-swap)
      _cs_dir="$2"; _cs_stage="$3"; _cs_backup="$4"
      if [ -e "$_cs_dir" ]; then
        { [ -d "$_cs_dir" ] && [ ! -L "$_cs_dir" ]; } || exit 1
        mv -- "$_cs_dir" "$_cs_backup" || exit 1
      fi
      mv -- "$_cs_stage" "$_cs_dir" || exit 1
      ;;
    # rollback do catalogo: o mesmo movimento do restore_skills_from_tx (:1580).
    catalog-rollback)
      _cr_dir="$2"; _cr_backup="$3"; _cr_failed="$4"
      [ -d "$_cr_backup" ] && [ ! -L "$_cr_backup" ] || exit 1
      if [ -e "$_cr_dir" ]; then mv -- "$_cr_dir" "$_cr_failed" || exit 1; fi
      mv -- "$_cr_backup" "$_cr_dir" || exit 1
      ;;
    # 23/09: o ajudante unico de preservacao (.env, config.toml, skills do dono) exposto cru.
    preserva)           shift; leon_preserva "$@" ;;
    *) exit 64 ;;
  esac
  exit $?
fi

rollback_transaction() {
  local tx="$1" live backup failed marker thread chat
  live="$(tx_read "$tx" live-path)"
  backup="$(tx_read "$tx" backup-path)"
  failed="$(tx_read "$tx" failed-path)"
  marker="$(tx_read "$tx" cron-marker)"
  thread="$(tx_read "$tx" thread-id)"
  chat="$(tx_read "$tx" chat-id)"
  service_write stop "$SERVICE" >/dev/null 2>&1 || true
  if [ -d "$backup" ]; then
    if [ -e "$live" ]; then
      [ ! -e "$failed" ] || failed="${failed}-$(date -u +%s)"
      mv -- "$live" "$failed" || return 1
    fi
    mv -- "$backup" "$live" || return 1
    guarda_env_pos_atualiza "$live" "$failed" "$tx"
  fi
  restore_skills_from_tx "$tx" || return 1
  restore_config_from_tx "$tx" || return 1
  restore_unit_from_tx "$tx" || return 1
  restore_crontab_from_tx "$tx" || return 1
  restore_service_state "$tx"
  printf 'rolled-back\n' > "$tx/status"
  remove_finalize_cron "$marker"
  notify_from_runtime "$live" "⚠️ A versão nova não passou no teste depois do reinício. Restaurei a versão anterior e o LEON voltou ao ar." "$thread" "$chat"
}

# Antes do restart o processo antigo ainda esta atendendo. Esse rollback nao
# chama systemctl, pois parar a unit também mataria o próprio atualizador.
rollback_inline() {
  local tx="$1" live backup failed marker
  live="$(tx_read "$tx" live-path)"
  backup="$(tx_read "$tx" backup-path)"
  failed="$(tx_read "$tx" failed-path)"
  marker="$(tx_read "$tx" cron-marker)"
  if [ -d "$backup" ]; then
    if [ -e "$live" ]; then
      [ ! -e "$failed" ] || failed="${failed}-$(date -u +%s)"
      mv -- "$live" "$failed" || return 1
    fi
    mv -- "$backup" "$live" || return 1
    guarda_env_pos_atualiza "$live" "$failed" "$tx"
  fi
  restore_skills_from_tx "$tx" || return 1
  restore_config_from_tx "$tx" || return 1
  restore_unit_from_tx "$tx" || return 1
  restore_crontab_from_tx "$tx" || return 1
  printf 'rolled-back\n' > "$tx/status"
  remove_finalize_cron "$marker"
}

telegram_smoke() {
  local runtime="$1" env_file token bot_id out
  [ "$TEST_MODE" != "1" ] || [ "${LEON_TEST_TELEGRAM_SMOKE:-1}" = "1" ] || return 0
  env_file="$runtime/.env"
  token="$(safe_env_value "$env_file" TELEGRAM_BOT_TOKEN 2>/dev/null)" || return 1
  [ -n "$token" ] || return 1
  bot_id="${token%%:*}"
  out="$(mktemp "${TMPDIR:-/tmp}/leon-getme.XXXXXX")"
  if ! telegram_api_get_file "$token" getMe "$out" 15 \
     || ! "$PYTHON_BIN" - "$out" "$bot_id" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    result = data.get("result", {})
    ok = data.get("ok") is True and str(result.get("id", "")) == sys.argv[2]
except Exception:
    ok = False
raise SystemExit(0 if ok else 1)
PY
  then
    rm -f -- "$out"
    return 1
  fi
  rm -f -- "$out"
}

# Estado transitorio da unit: 'activating' (subindo) ou 'deactivating' (descendo).
# Fail-safe por construcao: se o systemctl nao souber responder (fake de teste,
# systemd velho, saida vazia), respondemos "nao esta em transicao" e o fluxo segue
# igual ao de antes — endurecer nunca pode virar motivo novo de rollback.
service_in_transition() {
  local st
  st="$(service_read show -p ActiveState --value "$SERVICE" 2>/dev/null || true)"
  case "$st" in
    activating|deactivating) return 0 ;;
  esac
  st="$(service_read show -p SubState --value "$SERVICE" 2>/dev/null || true)"
  case "$st" in
    start|start-pre|start-post|stop|stop-sigterm|stop-sigkill|stop-post|final-sigterm|final-sigkill|auto-restart)
      return 0 ;;
  esac
  return 1
}

# Guarda o MOTIVO da reprovacao no proprio tx. Antes disto a central recebia
# so "prova de saude falhou", sem dizer o que falhou, e a casa ficava sem
# diagnostico util: falha calada e o defeito que mais custa tempo na frota.
health_motivo() {
  printf '%s\n' "$2" > "$1/health-reason" 2>/dev/null || true
}

health_smoke() {
  local tx="$1" live expected expected_skills skills_path attempts stable_sleep pid1 pid2 i
  local restart_at alive_wait alive_ok alive_m pid3
  live="$(tx_read "$tx" live-path)"
  expected="$(tx_read "$tx" bridge-sha256)"
  expected_skills="$(tx_read "$tx" skills-expected-digest)"
  skills_path="$(tx_read "$tx" skills-path)"
  attempts="${LEON_HEALTH_ATTEMPTS:-15}"
  stable_sleep="${LEON_HEALTH_STABLE_SLEEP:-3}"
  [ "${LEON_TEST_FAIL_AT:-}" != "health" ] || return 1
  [ -f "$live/bridge.cjs" ] || return 1
  if bridge_e_leon2 "$live/bridge.cjs"; then leon2_sintaxe_ok "$live" || return 1; fi
  [ -s "$live/appserver/adapter.cjs" ] || return 1
  [ -s "$live/lib/onboarding.js" ] || return 1
  [ -s "$live/lib-motores/codex-appserver.cjs" ] || return 1
  [ -s "$live/lib-motores/claude.cjs" ] || return 1
  [ -s "$live/lib-motores/index.cjs" ] || return 1
  [ -s "$live/smoke/appserver-smoke.cjs" ] || return 1
  [ -s "$live/workers/piper.js" ] || return 1
  [ "$(sha256sum "$live/bridge.cjs" | awk '{print $1}')" = "$expected" ] || return 1
  [ "$(installed_skills_digest "$skills_path")" = "$expected_skills" ] || return 1
  "$NODE_BIN" --check "$live/bridge.cjs" >/dev/null 2>&1 || return 1
  "$NODE_BIN" --check "$live/appserver/adapter.cjs" >/dev/null 2>&1 || return 1
  "$NODE_BIN" --check "$live/lib/onboarding.js" >/dev/null 2>&1 || return 1
  "$NODE_BIN" --check "$live/lib-motores/codex-appserver.cjs" >/dev/null 2>&1 || return 1
  "$NODE_BIN" --check "$live/lib-motores/claude.cjs" >/dev/null 2>&1 || return 1
  "$NODE_BIN" --check "$live/lib-motores/index.cjs" >/dev/null 2>&1 || return 1
  "$NODE_BIN" --check "$live/workers/piper.js" >/dev/null 2>&1 || return 1
  # ANTI-CORRIDA (04/09, tx 20260904T135046Z rolled-back a toa): medir o MainPID
  # enquanto a unit ainda esta em 'activating'/'deactivating' pega o pid do ciclo
  # que esta MORRENDO. Tres linhas depois o systemd entrega o pid novo, pid1!=pid2,
  # e uma release BOA era revertida so por azar de relogio com o cron do minuto.
  # Agora esperamos a unit assentar em 'active' ANTES de tirar a primeira medida, e
  # so entao exigimos estabilidade do pid pelo stable_sleep.
  pid1=0
  i=0
  while [ "$i" -lt "$attempts" ]; do
    if service_read is-active "$SERVICE" >/dev/null 2>&1 && ! service_in_transition; then
      pid1="$(service_read show -p MainPID --value "$SERVICE" 2>/dev/null || echo 0)"
      case "$pid1" in ''|*[!0-9]*) pid1=0 ;; esac
      [ "$pid1" -gt 0 ] && break
    fi
    i=$((i + 1))
    sleep 1
  done
  [ "$pid1" -gt 0 ] || { health_motivo "$tx" "unit nao assentou em active com pid valido"; return 1; }
  sleep "$stable_sleep"
  pid2="$(service_read show -p MainPID --value "$SERVICE" 2>/dev/null || echo 0)"
  [ "$pid1" = "$pid2" ] && service_read is-active "$SERVICE" >/dev/null 2>&1 \
    || { health_motivo "$tx" "pid nao ficou estavel ($pid1 -> $pid2) ou unit saiu de active"; return 1; }
  ! service_in_transition || { health_motivo "$tx" "unit voltou a transitar depois do pid estavel"; return 1; }
  # PROVA DE HEARTBEAT (16/09). Ate aqui a prova dizia "servico de pe com pid
  # estavel por 3s", e isso aprova agente que SOBE e nao trabalha: o bridge pode
  # ficar ativo sem nunca voltar a atender. Medido na frota: uma casa passou na
  # prova varias vezes ao dia enquanto reinstalava em loop.
  # O bridge escreve .alive a cada ciclo BEM-SUCEDIDO de leitura do Telegram.
  # Exigimos .alive com mtime POSTERIOR ao marco do restart: prova que o
  # processo novo chegou a trabalhar, nao so a existir.
  # O teto de 90s tem conta: o boot mede menos de 1s na bancada, mas o ciclo do
  # Telegram e long-poll de 30s e um ciclo pendurado leva 45s. Pior caso honesto
  # 78s; 90 da margem e cabe folgado na trava de 600s do finalizador.
  restart_at="$(tx_read "$tx" restart-at 2>/dev/null || true)"
  case "$restart_at" in
    ''|*[!0-9]*)
      # Transacao aberta por atualizador antigo, sem marco: mantem o
      # comportamento de antes em vez de reprovar por falta de dado.
      ;;
    *)
      alive_wait="${LEON_HEALTH_ALIVE_WAIT:-90}"
      alive_ok=0
      i=0
      while [ "$i" -lt "$alive_wait" ]; do
        alive_m="$(stat -c %Y "$live/.alive" 2>/dev/null || echo 0)"
        case "$alive_m" in ''|*[!0-9]*) alive_m=0 ;; esac
        if [ "$alive_m" -gt "$restart_at" ]; then alive_ok=1; break; fi
        pid3="$(service_read show -p MainPID --value "$SERVICE" 2>/dev/null || echo 0)"
        case "$pid3" in ''|*[!0-9]*) pid3=0 ;; esac
        if [ "$pid3" != "$pid1" ]; then
          health_motivo "$tx" "pid trocou esperando heartbeat ($pid1 -> $pid3): o bridge caiu e o systemd subiu outro"
          return 1
        fi
        i=$((i + 1))
        sleep 1
      done
      [ "$alive_ok" = 1 ] \
        || { health_motivo "$tx" "sem heartbeat (.alive) ate ${alive_wait}s depois do restart: unit ativa mas o bridge nao voltou a atender"; return 1; }
      ;;
  esac
  # ---- CONFERENCIA DO LEDGER DE SALAS (17/09) -------------------------------
  # Depois do heartbeat: o runtime NOVO ja esta de pe e ja leu o ledger. Toda
  # chave de SALA registrada no commit tem de existir no arquivo que o runtime
  # ENTRANTE esta lendo. Sala a menos = motivo nomeado + return 1, e o finalizador
  # chama rollback_transaction: o bridge anterior sobe lendo BACKUP/sessions.json
  # e a casa volta inteira.
  # POR QUE ISTO E A REDE: se a copia cair num caminho diferente do que o bridge
  # resolve (unit ganhando Environment, LEON_SESSIONS_FILE vazando), o bridge
  # boota VAZIO com log verde. Conferir por chave de sala, nunca por contagem
  # total: as duas familias podam no boot as entradas de missao/promessa mortas.
  if [ -f "$tx/ledger-salas-esperadas" ]; then
    local ledger_vivo ledger_esperadas ledger_vivas ledger_faltando
    ledger_esperadas="$(wc -l < "$tx/ledger-salas-esperadas" | tr -d ' ')"
    case "$ledger_esperadas" in ''|*[!0-9]*) ledger_esperadas=0 ;; esac
    if [ "$ledger_esperadas" -gt 0 ]; then
      ledger_vivo="$(cat "$tx/ledger-vivo" 2>/dev/null || true)"
      if [ -z "$ledger_vivo" ] || [ ! -f "$ledger_vivo" ]; then
        health_motivo "$tx" "ledger perdeu $ledger_esperadas salas (o arquivo de conversas do runtime novo nao existe)"
        return 1
      fi
      if ! ledger_salas_de "$ledger_vivo" > "$tx/ledger-salas-vivas" 2>/dev/null; then
        health_motivo "$tx" "ledger ilegivel depois do restart (esperadas $ledger_esperadas salas)"
        return 1
      fi
      ledger_vivas="$(wc -l < "$tx/ledger-salas-vivas" | tr -d ' ')"
      ledger_faltando="$(LC_ALL=C comm -23 "$tx/ledger-salas-esperadas" "$tx/ledger-salas-vivas" | wc -l | tr -d ' ')"
      case "$ledger_faltando" in ''|*[!0-9]*) ledger_faltando=0 ;; esac
      if [ "$ledger_faltando" -gt 0 ]; then
        health_motivo "$tx" "ledger perdeu $ledger_faltando salas (esperadas $ledger_esperadas, vivas $ledger_vivas)"
        return 1
      fi
    fi
  fi
  telegram_smoke "$live" || { health_motivo "$tx" "smoke do Telegram falhou"; return 1; }
}

# Report de versao HONESTO: so chamado pelo finalizador, com a versao REAL que ficou
# viva (nova no succeeded, antiga no rollback). Best-effort: falha de rede nao afeta nada.
report_version_from_tx() {
  local tx="$1" which_ver="$2" ver email central
  ver="$(cat "$tx/$which_ver" 2>/dev/null || true)"
  email="$(cat "$tx/report-email" 2>/dev/null || true)"
  central="$(cat "$tx/report-central" 2>/dev/null || true)"
  [ -n "$ver" ] && [ -n "$email" ] && [ -n "$central" ] || return 0
  printf %s "$central" | grep -qE '^https://' || return 0
  # 23/09 (G5): telemetria nunca segura nada. Conexao curta, teto de 10 s e em SEGUNDO PLANO:
  # com a VPS do dono fora, o finalizador segue na hora e o relato morre sozinho.
  ( curl -fsS --connect-timeout 5 --max-time 10 -X POST "$central/versao-report" \
      -H 'Content-Type: application/json' \
      -d "{\"email\":\"$email\",\"versao\":\"$ver\"}" >/dev/null 2>&1 || true ) </dev/null >/dev/null 2>&1 &
  return 0
}

# F1.5: rastro do ciclo da madrugada na central. Best-effort, timeout curto, NUNCA derruba o
# update. So rotulo curto e resultado (ok|erro) + motivo curto — zero segredo, zero conversa.
# Em AUTO mode (sem tty) o /atualiza hoje falha em silencio; agora deixa marca na central.
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/ /g' | tr -d '\r\n' | cut -c1-160; }
report_diagnostico_from_tx() {
  local tx="$1" resultado="$2" motivo="$3" email central machine_id versao evento
  email="$(cat "$tx/report-email" 2>/dev/null || true)"
  central="$(cat "$tx/report-central" 2>/dev/null || true)"
  [ -n "$email" ] && [ -n "$central" ] || return 0
  printf %s "$central" | grep -qE '^https://' || return 0
  machine_id="$(cat "$tx/report-machine-id" 2>/dev/null || true)"
  # versao viva depois do ciclo: nova no ok, antiga no erro (o mesmo criterio do report honesto)
  if [ "$resultado" = "ok" ]; then versao="$(cat "$tx/new-version" 2>/dev/null || true)"
  else versao="$(cat "$tx/prev-version" 2>/dev/null || true)"; fi
  evento="update-auto"; [ -f "$tx/report-auto" ] && [ -z "$(cat "$tx/report-auto" 2>/dev/null)" ] && evento="update"
  # 23/09 (G5): mesmo contrato do report de versao: conexao curta, teto de 10 s, segundo plano.
  ( curl -fsS --connect-timeout 5 --max-time 10 -X POST "$central/diagnostico" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$(json_escape "$email")\",\"machine_id\":\"$(json_escape "$machine_id")\",\"versao\":\"$(json_escape "$versao")\",\"evento\":\"$evento\",\"resultado\":\"$(json_escape "$resultado")\",\"motivo\":\"$(json_escape "$motivo")\",\"em\":$(date +%s)000}" \
    >/dev/null 2>&1 || true ) </dev/null >/dev/null 2>&1 &
  return 0
}

# ---- TRAVA DE COMMIT (04/09) ----------------------------------------------
# O caminho de commit grava status=committed e SO reinicia o servico dezenas de
# linhas depois. O finalizador roda pelo cron a cada minuto: se o tique caisse
# nessa janela, ele media o pid do processo velho, o restart trocava o pid dentro
# do stable_sleep e uma release BOA levava rollback (caso provado: tx
# 20260904T135046Z-323211). O commit agora segura a trava do finalizador ANTES de
# escrever 'committed' e so solta depois do restart com o pid novo estavel.
#
# Regra de ouro: trava presa e PIOR que a corrida (a transacao ficaria eterna em
# 'committed', sem sucesso e sem rollback). Por isso a trava e AUTO-EXPIRAVEL:
# finalize_transaction reivindica qualquer trava mais velha que o teto abaixo.
LEON_FINALIZE_LOCK_TTL="${LEON_FINALIZE_LOCK_TTL:-600}"

# Espera o servico voltar a 'active' com MainPID > 0 e estavel pelo stable_sleep
# (a mesma prova do health_smoke) e so entao libera o finalizador. Nunca falha o
# update: o teto de tentativas garante saida, e o pior caso e o finalizador pegar
# a casa como sempre pegou.
commit_lock_release_after_restart() {
  local attempts stable_sleep pid1 pid2 i
  [ -n "$COMMIT_LOCK" ] || return 0
  attempts="${LEON_HEALTH_ATTEMPTS:-15}"
  stable_sleep="${LEON_HEALTH_STABLE_SLEEP:-3}"
  pid1=0
  i=0
  while [ "$i" -lt "$attempts" ]; do
    if service_read is-active "$SERVICE" >/dev/null 2>&1 && ! service_in_transition; then
      pid1="$(service_read show -p MainPID --value "$SERVICE" 2>/dev/null || echo 0)"
      case "$pid1" in ''|*[!0-9]*) pid1=0 ;; esac
      [ "$pid1" -gt 0 ] && break
    fi
    i=$((i + 1))
    sleep 1
  done
  if [ "$pid1" -gt 0 ]; then
    sleep "$stable_sleep"
    pid2="$(service_read show -p MainPID --value "$SERVICE" 2>/dev/null || echo 0)"
    if [ "$pid1" != "$pid2" ]; then
      # ainda balancando: da mais uma janela antes de entregar ao finalizador
      sleep "$stable_sleep"
    fi
  fi
  finalize_lock_release "$COMMIT_LOCK"
  COMMIT_LOCK=""
}

# ---- A1: A COPIA DO LEDGER TEM DE ACONTECER COM O SERVICO PARADO (17/09) ----
# ACHADO (revisao Astra): a copia do ledger roda logo depois dos dois renames, com o
# bridge LEGADO ainda atendendo, e o servico so reinicia dezenas de linhas depois
# (npm install de ate 120s, modelo de audio de ate 600s, banco, cron). Tudo que o
# cliente conversar nessa janela e gravado pelo bridge legado no caminho literal
# INSTALL_DIR/sessions.json, que ninguem le depois: o runtime novo sobe com a foto
# velha e a conferencia passa, porque a lista esperada tambem veio da foto velha.
# REGRA NOVA: a copia que VALE, e a lista de salas que a saude cobra, sao refeitas
# com o servico PARADO, imediatamente antes de subir o runtime novo. A copia de
# antes do commit continua onde esta (e ela que prova, com a casa intacta, que o
# arquivo passa no pre-voo e que o destino esta limpo); esta segunda e o re-sync.
# NUNCA MOVE: a origem segue intocada e viaja dentro do BACKUP, entao os tres
# caminhos de volta continuam devolvendo a casa com as salas.
#
# POR QUE NEM SEMPRE DA PRA PARAR: quando o /atualiza dispara pelo proprio LEON, este
# script nasce dentro do cgroup da unit (KillMode=control-group), e um 'stop' mataria
# o atualizador ANTES do start, deixando a casa parada. Nesse caso o re-sync sai a
# quente, na ultima linha antes do restart: a janela cai de minutos para o tempo de
# uma copia. Sem /proc legivel respondemos "estamos dentro" (modo quente = o
# comportamento de hoje): endurecer nunca pode virar motivo novo de casa parada.
dentro_do_cgroup_do_servico() {
  [ -r /proc/self/cgroup ] || return 0
  grep -qF "$SERVICE" /proc/self/cgroup 2>/dev/null
}

ledger_espera_parado() {
  local i=0 teto
  teto="${LEON_STOP_ATTEMPTS:-30}"
  while [ "$i" -lt "$teto" ]; do
    if ! service_read is-active "$SERVICE" >/dev/null 2>&1 && ! service_in_transition; then
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  return 1
}

# Grava o que a prova de saude cobra: o caminho vivo, as CHAVES DE SALA esperadas, o
# sha e a contagem. Sempre a partir do arquivo que esta no disco AGORA, para que a
# lista nunca seja mais velha que a copia.
ledger_registra_saude() {
  printf '%s\n' "$LEDGER_DESTINO" > "$TX_DIR/ledger-vivo"
  if [ -f "$LEDGER_DESTINO" ]; then
    ledger_salas_de "$LEDGER_DESTINO" > "$TX_DIR/ledger-salas-esperadas" || return 1
    sha256sum "$LEDGER_DESTINO" | awk '{print $1}' > "$TX_DIR/ledger-sha"
  else
    : > "$TX_DIR/ledger-salas-esperadas"
    : > "$TX_DIR/ledger-sha"
  fi
  wc -l < "$TX_DIR/ledger-salas-esperadas" | tr -d ' ' > "$TX_DIR/ledger-salas"
  if [ "${LEDGER_COPIOU:-0}" = 1 ] && [ -n "${LEDGER_MARCA:-}" ]; then
    printf '%s\n' "$LEDGER_MARCA" > "$TX_DIR/ledger-marca"
    ( umask 077
      printf 'tx=%s\norigem=%s\ndestino=%s\nsalas=%s\n' \
        "$TX_ID" \
        "$(sha256sum "$INSTALL_DIR/sessions.json" | awk '{print $1}')" \
        "$(cat "$TX_DIR/ledger-sha")" \
        "$(cat "$TX_DIR/ledger-salas")" > "$LEDGER_MARCA" ) || return 1
  fi
}

# Re-sync: a MESMA copia validada de antes, refeita sobre o arquivo mais fresco, mais
# o pre-voo e as listas da saude. $1 = parado | quente (so para o rastro no tx).
ledger_resync() {
  local modo="$1"
  [ "${LEDGER_MIGRA:-0}" = 1 ] || return 0
  printf '%s\n' "$modo" > "$TX_DIR/ledger-resync" 2>/dev/null || true
  [ -e "$INSTALL_DIR/sessions.json" ] || return 0
  safe_copy_state_file "$INSTALL_DIR/sessions.json" "$LEDGER_DESTINO" sessions || return 1
  if [ "$(id -u)" = 0 ]; then chown --reference="$INSTALL_DIR" -- "$LEDGER_DESTINO" 2>/dev/null || true; fi
  ledger_pre_voo "$LEDGER_DESTINO" || return 1
  LEDGER_COPIOU=1
  printf 'migrado\n' > "$TX_DIR/ledger-modo"
  ledger_registra_saude || return 1
}

# Poe o runtime novo no ar. 0 = servico de pe; diferente de 0 = quem chama restaura.
subir_runtime_novo() {
  if [ "${LEDGER_MIGRA:-0}" = 1 ] && ! dentro_do_cgroup_do_servico; then
    if service_write stop "$SERVICE" && ledger_espera_parado; then
      say "   serviço parado; levando as conversas para o runtime novo antes de subir."
      ledger_resync parado || return 2
      date +%s > "$TX_DIR/restart-at" 2>/dev/null || true
      service_write start "$SERVICE" || return 1
      return 0
    fi
    say "   não consegui parar o serviço para copiar as conversas; sigo pelo reinício."
  fi
  ledger_resync quente || return 2
  date +%s > "$TX_DIR/restart-at" 2>/dev/null || true
  service_write restart "$SERVICE" || return 1
  return 0
}

finalize_lock_age() {  # idade em segundos do dir de trava (vazio = nao existe)
  local dir="$1" mtime now
  mtime="$(stat -c %Y -- "$dir" 2>/dev/null || true)"
  case "$mtime" in ''|*[!0-9]*) return 1 ;; esac
  now="$(date +%s)"
  printf '%s\n' "$(( now - mtime ))"
}

# Toma a trava. 0 = tomei; 1 = outro dono viva, saia de fininho.
finalize_lock_acquire() {
  local dir="$1" age
  mkdir -- "$dir" 2>/dev/null && return 0
  age="$(finalize_lock_age "$dir" 2>/dev/null || true)"
  case "$age" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$age" -ge "$LEON_FINALIZE_LOCK_TTL" ] || return 1
  # Trava orfa (atualizador morto no restart antes de soltar): reivindica.
  rmdir -- "$dir" 2>/dev/null || true
  mkdir -- "$dir" 2>/dev/null || return 1
  return 0
}

finalize_lock_release() {
  [ -z "${1:-}" ] || rmdir -- "$1" 2>/dev/null || true
}

finalize_transaction() {
  local tx="$1" marker live lock_dir thread chat tx_service skills_backup skills_path ledger_marca
  case "$tx" in /*/update-transactions/*) ;; *) return 1 ;; esac
  [ -d "$tx" ] && [ ! -L "$tx" ] || return 1
  tx_service="$(tx_read "$tx" service-name)"
  printf %s "$tx_service" | grep -qE '^[A-Za-z0-9_.@-]+\.service$' || return 1
  SERVICE="$tx_service"
  marker="$(tx_read "$tx" cron-marker)"
  live="$(tx_read "$tx" live-path)"
  thread="$(tx_read "$tx" thread-id)"
  chat="$(tx_read "$tx" chat-id)"
  case "$(cat "$tx/status" 2>/dev/null || true)" in
    succeeded|rolled-back)
      remove_finalize_cron "$marker"
      return 0 ;;
    committed) ;;
    *) return 0 ;;
  esac
  # o cron nao traz ambiente: as pastas (skills-pessoais, registro do catalogo) saem do .env da
  # casa pelo leitor unico, igual ao corpo do atualizador (24/09, rodada 5)
  leon_bases_do_dono "$live/.env" || return 1
  lock_dir="$tx/.finalize-lock"
  # Trava presente = commit em andamento (ou outro finalizador). Sai em paz: o
  # proximo tique do cron encontra a casa estavel. So reivindica trava expirada.
  finalize_lock_acquire "$lock_dir" || return 0
  trap 'rmdir -- "$lock_dir" 2>/dev/null || true' RETURN
  if health_smoke "$tx"; then
    # O veredito de saúde torna o commit definitivo. A remoção posterior do
    # backup é limpeza de quarentena; nunca tentamos rollback depois de apagá-lo.
    skills_backup="$(tx_read "$tx" skills-backup-path 2>/dev/null || true)"
    skills_path="$(tx_read "$tx" skills-path 2>/dev/null || true)"
    # 0.7 (obra Fase 0): o backup do catalogo NAO e apagado no sucesso enquanto a casa
    # nao tiver a pasta de skills pessoais. Ate a 2.4.48 o catalogo era o unico lugar
    # onde uma skill do proprio dono podia morar, e apagar a quarentena logo apos o
    # smoke tirava a ultima copia dela. Com <LEON_DATA_DIR>/skills-pessoais/ no ar a
    # separacao ja protege o que e do dono, e a limpeza volta a ser segura.
    # SKILLS DO DONO (23/09, desenho estrutural): antes de apagar o backup do catalogo, tudo
    # nele que nao e do produto (nome fora do catalogo novo e fora de todo catalogo que o produto
    # ja publicou) vai pra skills-pessoais. Backup que tem coisa do dono NUNCA e apagado: fica
    # listado em .skills-backups-retidos. Ate a 2.4.48 o catalogo era o unico lugar onde a skill
    # do dono podia morar, e a casa Claude usa ~/.claude/skills, que e dele tambem.
    # Dentro de pasta com nome do produto: arquivo que so o backup tem vai pra
    # skills-pessoais/<nome>.catalogo-antigo-N/; e o backup so e apagado quando e IGUAL ao
    # catalogo que o produto instalou (registro .skills-catalogo-instalado, gravado aqui mesmo
    # depois da saude aprovada). Sem registro (casa que veio de versao velha) ou diferente dele
    # = alguem editou o catalogo: o backup fica.
    local _sk_rc=0 _sk_reg
    _sk_reg="$(dirname "${skills_path:-$LEON_DATA_DIR/skills}")/.skills-catalogo-instalado"
    if [ -n "$skills_backup" ] && [ -d "$skills_backup" ]; then
      ensure_skills_personal_dir || true
      leon_preserva skills-do-dono "$skills_backup" "$skills_path" "$(skills_personal_dir)" "$_sk_reg" \
        >> "$live/upgrade.log" 2>&1 || _sk_rc=$?
    fi
    if [ -n "$skills_path" ] && [ -d "$skills_path" ]; then
      leon_preserva skills-registra "$skills_path" "$_sk_reg" >> "$live/upgrade.log" 2>&1 || true
    fi
    if [ "$_sk_rc" = 0 ] && skills_personal_dir_ready; then
      remove_committed_skills_backup "$skills_path" "$skills_backup" || {
        rmdir -- "$lock_dir" 2>/dev/null || true
        trap - RETURN
        return 1
      }
    else
      printf '%s\n' "$skills_backup" >> "$LEON_DATA_DIR/.skills-backups-retidos" 2>/dev/null || true
      printf '%s [skills] catalogo anterior mantido (%s): tem skill do dono (copiada pra skills-pessoais) ou a casa nao tem skills-pessoais (rc=%s).\n' \
        "$(date '+%F %T')" "$skills_backup" "$_sk_rc" >> "$live/upgrade.log" 2>/dev/null || true
    fi
    # 17/09: a copia em LEON_STATE_DIR virou o ledger VIVO. O marcador sai (ele so
    # autoriza sobrescrever copia NAO promovida). A origem em INSTALL_DIR fica como
    # fossil sem leitor: apagar dado do dono e proibido.
    ledger_marca="$(cat "$tx/ledger-marca" 2>/dev/null || true)"
    [ -z "$ledger_marca" ] || rm -f -- "$ledger_marca" 2>/dev/null || true
    printf '%s [ledger] %s: %s salas em %s (sha %s)\n' "$(date '+%F %T')" \
      "$(cat "$tx/ledger-modo" 2>/dev/null || echo conferido)" \
      "$(cat "$tx/ledger-salas" 2>/dev/null || echo 0)" \
      "$(cat "$tx/ledger-vivo" 2>/dev/null || true)" \
      "$(cat "$tx/ledger-sha" 2>/dev/null || true)" >> "$live/upgrade.log" 2>/dev/null || true
    printf 'succeeded\n' > "$tx/status"
    remove_finalize_cron "$marker"
    rm -f -- "$live/.update-pending.json" 2>/dev/null || true
    # Report HONESTO: a versao NOVA so agora, depois de passar na prova de saude.
    report_version_from_tx "$tx" new-version
    # F1.5: rastro do ciclo bem-sucedido na central (sinal da frota).
    report_diagnostico_from_tx "$tx" ok "atualizou e passou na prova de saude; ledger $(cat "$tx/ledger-modo" 2>/dev/null || echo conferido) $(cat "$tx/ledger-salas" 2>/dev/null || echo 0) salas"
    # SEM msg de sucesso aqui: quem confirma "✅ No ar!" pro dono e o BRIDGE ao subir
    # (bridge.cjs, veioDeUpdate). Emitir aqui TAMBEM gerava mensagem DUPLICADA no Telegram
    # ("Atualizacao concluida" + "No ar!"). A saudacao do bridge e a fonte unica, e ela so
    # dispara quando o processo REALMENTE voltou vivo — prova melhor que "passou nos testes".
    rmdir -- "$lock_dir" 2>/dev/null || true
    trap - RETURN
    return 0
  fi
  rollback_transaction "$tx"
  # Report HONESTO: o update falhou e reverteu; a central precisa saber que a versao
  # viva e a ANTIGA, nao a nova. Sem isso o painel/monitor registrava sucesso falso.
  report_version_from_tx "$tx" prev-version
  # F1.5: rastro do ciclo que reverteu na central (sinal da frota). Sem isso, a madrugada
  # que falhava sumia: a central so via a versao antiga e nao sabia que houve tentativa.
  # O motivo nomeado, quando a prova gravou um: falha calada custa dias de
  # diagnostico numa casa remota.
  report_diagnostico_from_tx "$tx" erro "prova de saude falhou ($(cat "$tx/health-reason" 2>/dev/null || echo 'motivo nao registrado')); reverteu pra versao anterior"
  rmdir -- "$lock_dir" 2>/dev/null || true
  trap - RETURN
  return 1
}

if [ "$FINALIZE_MODE" -eq 1 ]; then
  TX_FINAL="${2:-}"
  [ -n "$TX_FINAL" ] || exit 1
  finalize_transaction "$TX_FINAL"
  exit $?
fi

ENV_FILE="$INSTALL_DIR/.env"
LOG="$INSTALL_DIR/upgrade.log"
CHAT_ARG="${1:-}"
THREAD_ARG="${2:-}"
TX_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
LIVE_PARENT="$(dirname "$INSTALL_DIR")"
LIVE_BASE="$(basename "$INSTALL_DIR")"
STAGE="$LIVE_PARENT/.${LIVE_BASE}.leon-stage-$TX_ID"
BACKUP="$LIVE_PARENT/.${LIVE_BASE}.leon-backup-$TX_ID"
FAILED="$LIVE_PARENT/.${LIVE_BASE}.leon-failed-$TX_ID"
# LEITOR UNICO DAS PASTAS (24/09, rodada 5). Toda pasta sai do .env do dono pelo leitor do
# bridge (leon_bases_do_dono, bloco LEON-PRESERVA), na ordem do bridge: LEON_DATA_DIR do .env;
# dele BRAIN_DIR, MEMVIVA_FILE, ASSUNTOS_FILE, LEON_STATE_DIR, LEON_MISSIONS_DIR,
# LEON_PROMISES_DIR, PERSONA_DIR. O ambiente do processo NAO vale pra casa que tem .env: o vigia
# antigo exportava a linha crua (aspas e comentario literais) e o bridge ignora o ambiente
# nessas chaves. Antes, ${LEON_DATA_DIR:-$HOME/.leon} vinha antes de ler o .env e a casa com
# LEON_DATA_DIR proprio ganhava BRAIN_DIR/PERSONA_DIR/LEON_STATE_DIR de ~/.leon no fim do .env.
leon_bases_do_dono "$ENV_FILE" \
  || { printf 'ERRO: nao consegui ler as pastas do .env desta casa.\n' >&2; exit 1; }
CODEX_HOME_DIR="$LEON_DATA_DIR/codex"
LEON_CODEX_CLI_VERSION=""
LEON_CODEX_CLI_MINIMA=""
CODEX_CLI_ABAIXO_DA_MINIMA=0
CODEX_CLI_SUBIU=0
CODEX_CLI_STAGING=""
CLAUDE_CLI_STAGING=""
CLAUDE_CLI_ABAIXO_DA_MINIMA=0
CLAUDE_CLI_SUBIU=0
CLAUDE_CLI_VERSAO_ATUAL=""
CLAUDE_BIN_NOVO=""
CONFIG_PATH="$CODEX_HOME_DIR/config.toml"
TX_ROOT="$LEON_DATA_DIR/update-transactions"
TX_DIR="$TX_ROOT/$TX_ID"
UNIT_PATH="${LEON_UNIT_PATH:-/etc/systemd/system/$SERVICE}"
TARBALL=""
BASE_HASH_TMP=""
RELEASE_MANIFEST=""
RELEASE_SIGNATURE=""
RELEASE_PUBLIC_KEY=""
RELEASE_METADATA=""
EXTRACT_TMP=""
UPDATE_TMP=""
BUNDLE_TMP=""
BUNDLE_HASH_TMP=""
BUNDLE_EXTRACT=""
SKILLS_TMP=""
SKILLS_EXTRACT=""
ENV_READ_SAFE=""
MUTATION_STARTED=0
COMMIT_LOCK=""
CRON_ARMED=0
RESTARTING=0
FAIL_MESSAGE="A atualização foi interrompida antes de concluir. A versão anterior foi preservada."
DANGEROUS_FLAG="--dangerously-bypass-approvals-and-"'sandbox'

say() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null || true
}

# 22/09: normalize_skills_catalog sela o stage read-only (dirs 0500, arquivos 0400/0500)
# pra congelar o catálogo assinado. `rm -rf` num dir 0500 FALHA (sem +w o kernel não deixa
# remover os filhos), então todo apagamento de stage passa por aqui: devolve +w e só então
# apaga. Usado no trap (os dois ramos) e na faxina de início de rodada.
limpa_stage_selado() {
  local alvo="$1"
  [ -n "$alvo" ] || return 0
  [ -e "$alvo" ] || return 0
  case "$alvo" in "$HOME"/*) ;; *) return 0 ;; esac
  [ ! -L "$alvo" ] || { rm -f -- "$alvo" 2>/dev/null; return 0; }
  chmod -R u+w -- "$alvo" 2>/dev/null
  rm -rf -- "$alvo" 2>/dev/null
}

# 22/09: faxina de INÍCIO de rodada. Restos de rodadas antigas (stage selado e extract)
# nunca são estado recuperável: o catálogo vivo é o LEON_SKILLS_DIR, e o backup da
# transação corrente tem carimbo próprio. Sem isso o cliente acumulava um diretório
# 0500 por /atualiza morto — 5 na casa do Muri — sem nunca ser avisado.
limpa_restos_de_skills() {
  local pai="$1" alvo n=0
  [ -n "$pai" ] && [ -d "$pai" ] || return 0
  for alvo in "$pai"/.skills-stage-* "$pai"/.skills-extract-*; do
    [ -e "$alvo" ] || continue
    limpa_stage_selado "$alvo"
    [ -e "$alvo" ] && continue
    n=$((n + 1))
    say "faxina: removi resto de rodada anterior $alvo"
  done
  [ "$n" -eq 0 ] || say "faxina: $n resto(s) de catálogo removido(s) em $pai"
}

DOUTRINA_PLACEHOLDER=""
DOUTRINA_PLACEHOLDER_ARQ=""
fatal() {
  FAIL_MESSAGE="$1"
  printf 'ERRO: %s\n' "$1" >&2
  exit 1
}

cleanup_main() {
  local status=$?
  set +e
  # A trava do commit NUNCA pode sobreviver ao processo: presa, a transacao ficaria
  # eterna em 'committed' (nem sucesso, nem rollback). Solta em toda saida — sucesso,
  # fatal, rollback e INT/TERM. Morte por SIGKILL ainda e coberta pelo TTL da trava.
  [ -z "$COMMIT_LOCK" ] || { finalize_lock_release "$COMMIT_LOCK"; COMMIT_LOCK=""; }
  [ -z "$TARBALL" ] || rm -f -- "$TARBALL"
  [ -z "$BASE_HASH_TMP" ] || rm -f -- "$BASE_HASH_TMP"
  [ -z "$RELEASE_MANIFEST" ] || rm -f -- "$RELEASE_MANIFEST"
  [ -z "$RELEASE_SIGNATURE" ] || rm -f -- "$RELEASE_SIGNATURE"
  [ -z "$RELEASE_PUBLIC_KEY" ] || rm -f -- "$RELEASE_PUBLIC_KEY"
  [ -z "$RELEASE_METADATA" ] || rm -f -- "$RELEASE_METADATA"
  [ -z "$EXTRACT_TMP" ] || rm -rf -- "$EXTRACT_TMP"
  [ -z "$UPDATE_TMP" ] || rm -f -- "$UPDATE_TMP"
  [ -z "$BUNDLE_TMP" ] || rm -f -- "$BUNDLE_TMP"
  [ -z "$BUNDLE_HASH_TMP" ] || rm -f -- "$BUNDLE_HASH_TMP"
  [ -z "$BUNDLE_EXTRACT" ] || rm -rf -- "$BUNDLE_EXTRACT"
  [ -z "$SKILLS_TMP" ] || rm -f -- "$SKILLS_TMP"
  [ -z "$SKILLS_EXTRACT" ] || rm -rf -- "$SKILLS_EXTRACT"
  [ -z "$ENV_READ_SAFE" ] || rm -f -- "$ENV_READ_SAFE"
  # Prefixo de encenacao da subida do CLI: se formos mortos no meio do npm, nao pode sobrar
  # meia instalacao no disco. A release VIVA nunca esta aqui dentro, entao apagar e sempre seguro.
  [ -z "$CODEX_CLI_STAGING" ] || rm -rf -- "$CODEX_CLI_STAGING"
  [ -z "$CLAUDE_CLI_STAGING" ] || rm -rf -- "$CLAUDE_CLI_STAGING"
  case "${LEON_UPDATE_COPIA:-}" in
    "${TMPDIR:-/tmp}"/leon-update.*) rm -f -- "$LEON_UPDATE_COPIA" ;;
  esac
  if [ "$status" -ne 0 ] && [ "$RESTARTING" -eq 0 ]; then
    if [ "$MUTATION_STARTED" -eq 1 ]; then
      rollback_inline "$TX_DIR" >/dev/null 2>&1 || true
      # Falhas anteriores ao segundo rename ainda deixam o stage candidato
      # fora do runtime. Ele nunca é estado recuperável e deve desaparecer em
      # qualquer rollback; o backup antigo continua preservado pela transação.
      [ ! -e "$STAGE" ] || rm -rf -- "$STAGE"
      # 22/09: esta limpeza do stage SELADO existia só no ramo de baixo. Quando o commit
      # do catálogo falhava (MUTATION_STARTED já era 1), o stage 0500 ficava no disco pra
      # sempre. Na casa do Muri empilharam 5 .skills-stage-* em 21-22/09, um por /atualiza.
      limpa_stage_selado "${SKILLS_STAGE:-}"
    else
      [ ! -e "$STAGE" ] || rm -rf -- "$STAGE"
      limpa_stage_selado "${SKILLS_STAGE:-}"
      if [ "$CRON_ARMED" -eq 1 ]; then
        restore_crontab_from_tx "$TX_DIR" >/dev/null 2>&1 || true
      fi
    fi
    # madrugada (update-auto, sem pedido humano): so log, sem mensagem repetida ao dono (03/09)
    if [ -n "$CHAT_ARG" ] || [ -z "${LEON_UPDATE_AUTO:-}" ]; then
      notify_from_runtime "$INSTALL_DIR" "⚠️ $FAIL_MESSAGE" "$THREAD_ARG" "$CHAT_ARG"
    fi
  fi
  return "$status"
}
trap cleanup_main EXIT
trap 'if [ "$RESTARTING" -eq 1 ]; then exit 0; else exit 130; fi' INT TERM

case "$INSTALL_DIR" in
  /*) ;;
  *) fatal "o diretorio de instalação precisa ser absoluto." ;;
esac
[ "$INSTALL_DIR" != "/" ] || fatal "o diretório raiz não pode ser usado como instalação."
if [ ! -d "$INSTALL_DIR" ] || [ -L "$INSTALL_DIR" ]; then
  fatal "a instalação atual não é um diretório real."
fi
[ -f "$ENV_FILE" ] || fatal "não achei o arquivo de configuração do LEON."
# O caminho do perfil e conferido sempre (e derivado do HOME), mas a EXISTENCIA dele so e
# exigida na casa do motor que o usa. A checagem de caminho fica, porque e barata e vale
# como sanidade do HOME em qualquer motor.
case "$CONFIG_PATH" in "$HOME"/*) ;; *) fatal "o perfil do motor está fora da home esperada." ;; esac

for required in "$CURL_BIN" tar "$PYTHON_BIN" sha256sum cp mv; do
  command -v "$required" >/dev/null 2>&1 || fatal "falta o programa obrigatório: $required."
done
# 02/set: este gate checa o BINÁRIO crontab (command -v). Fable derrubou a ideia de "religar aqui":
# systemctl enable --now cron religa o SERVIÇO, não instala o binário — se o binário sumiu, a unit
# também não existe e o religar falha. E o cenário "VPS com cron parado" nunca foi barrado aqui
# (serviço parado passa; só binário ausente barra). Então mantenho o gate, mas com mensagem HONESTA
# que aponta o conserto real (reinstalar o pacote do agendador via instalador). O caso comum de
# cron parado (binário presente) passa direto; o pós-sucesso (~2320) é quem religa o serviço.
command -v "$CRONTAB_BIN" >/dev/null 2>&1 \
  || fatal "o agendador (cron) não está instalado nesta máquina; rode o instalador de novo pra restaurá-lo — sem ele o /atualiza não consegue concluir com segurança."

ENV_READ_SAFE="$(mktemp "${TMPDIR:-/tmp}/leon-env-read.XXXXXX")"
safe_copy_state_file "$ENV_FILE" "$ENV_READ_SAFE" env \
  || fatal "o .env atual não é um arquivo regular 0600 seguro."

EMAIL="$(env_get_from "$ENV_READ_SAFE" LEON_LICENSE_EMAIL)"
CENTRAL="$(env_get_from "$ENV_READ_SAFE" LEON_LICENSE_CENTRAL)"
if [ -z "$EMAIL" ] || [ -z "$CENTRAL" ]; then
  fatal "faltam os dados da licença na configuração."
fi
# Piso do canal: a release exige NO MINIMO esta versao de CLI. Casa com CLI igual ou mais
# novo sobe normal; quem esta abaixo o updater tenta subir pelo `codex update` nativo.
LEON_CODEX_CLI_MINIMA="0.147.0"
# Default alinhado com o bridge (bridge.cjs codexBin() e lib-motores/codex-appserver.cjs):
# .env sem a variavel = casa da frota antiga, que roda 0.147.0. Cravar 0.153.3 aqui fazia o
# updater procurar um diretorio de release que a casa nunca teve e morrer antes de comecar.
# 17/09 (causa provada na casa de bancada c01): esta linha caia direto no PISO porque
# LEON_CODEX_CLI_VERSION so era lido do AMBIENTE do processo (linha ~2066), nunca do .env da
# casa, ao contrario de todas as outras chaves, que usam env_get_from. A casa declarava
# LEON_CODEX_CLI_VERSION=0.154.0 e tinha a release no disco; o updater assumia 0.147.0, exigia
# um diretorio que nunca existiu e morria com codigo 1, calado, todas as madrugadas.
LEON_CODEX_CLI_VERSION="$(env_get_from "$ENV_READ_SAFE" LEON_CODEX_CLI_VERSION)"
[ -n "$LEON_CODEX_CLI_VERSION" ] || LEON_CODEX_CLI_VERSION="$LEON_CODEX_CLI_MINIMA"
# catalogo do produto: o .env manda (leon_bases_do_dono); sem a chave, o padrao do bridge
[ -n "$LEON_SKILLS_DIR" ] || LEON_SKILLS_DIR="$LEON_DATA_DIR/skills"
# 17/09 (causa provada em casa de bancada Claude): a exigencia do Node dedicado estava 19
# linhas ACIMA do portao por motor, entao valia para a casa Claude tambem. A casa Claude usa o
# Node do sistema (/usr/bin/node), nunca teve o dedicado, e morria aqui com codigo 1 dizendo
# "Rode novamente o instalador Codex". Como o instalador agenda a atualizacao automatica de
# hora em hora no minuto 13, o cliente levava esse erro na primeira hora depois de instalar,
# sem ter digitado nada. O portao sobe para ca e o caminho do Node passa a depender do motor.
LEON_ENGINE_CASA="$(env_get_from "$ENV_READ_SAFE" ENGINE_DEFAULT)"
[ -n "$LEON_ENGINE_CASA" ] || LEON_ENGINE_CASA="$(env_get_from "$ENV_READ_SAFE" ENGINE)"
case "$LEON_ENGINE_CASA" in claude) ;; *) LEON_ENGINE_CASA=codex ;; esac
if [ "$LEON_ENGINE_CASA" = claude ]; then
  EXPECTED_NODE_BIN=/usr/bin/node
else
  EXPECTED_NODE_BIN="$LEON_DATA_DIR/node/releases/$LEON_NODE_VERSION/bin/node"
fi
if [ "$TEST_MODE" = "1" ] && [ -n "$NODE_BIN" ]; then
  : # Fixture explícita; produção nunca aceita override do executável.
else
  NODE_BIN="$EXPECTED_NODE_BIN"
fi
command -v "$NODE_BIN" >/dev/null 2>&1 \
  || fatal "o runtime Node desta casa ($LEON_ENGINE_CASA) não está no lugar esperado ($EXPECTED_NODE_BIN). Rode novamente o instalador desta casa antes do /atualiza."
if [ "$LEON_ENGINE_CASA" = codex ] && { [ "$TEST_MODE" != "1" ] || [ "$NODE_BIN" = "$EXPECTED_NODE_BIN" ]; }; then
  validate_dedicated_node "$NODE_BIN" "$LEON_DATA_DIR" "$LEON_NODE_VERSION" \
    || fatal "o runtime Node dedicado está ausente ou inseguro. Rode novamente o instalador Codex antes do /atualiza."
  [ "$($NODE_BIN --version 2>/dev/null || true)" = "v$LEON_NODE_VERSION" ] \
    || fatal "o runtime Node dedicado é incompatível. Rode novamente o instalador Codex antes do /atualiza."
fi
validate_service_unit "$UNIT_PATH" "$INSTALL_DIR" "$NODE_BIN" "$(id -un)" \
  || fatal "a unit do LEON não usa o runtime esperado nem o perfil endurecido. Rode novamente o instalador desta casa antes do /atualiza."
# 22/09 (causa provada na casa do cliente Muri, 5 /atualiza mortos no mesmo passo):
# o stage nascia SEMPRE em LEON_DATA_DIR, mas o commit renomeia o stage PRA
# LEON_SKILLS_DIR. Quando os dois nao tem o MESMO PAI, esse rename e proibido pelo
# kernel: normalize_skills_catalog sela o stage em 0500, e renomear um DIRETORIO pra
# outro pai exige escrita no proprio diretorio (o kernel precisa reescrever a entrada
# '..'). Renomear DENTRO do mesmo pai nao mexe no '..' e passa com 0500. Como o segundo
# mv vinha DEPOIS do primeiro (catalogo antigo ja guardado no backup), a casa ficava
# sem catalogo e so voltava pelo rollback. O default LEON_DATA_DIR/skills tem o mesmo
# pai e por isso a frota inteira passava; quem declara LEON_SKILLS_DIR em outro lugar
# no .env batia de frente. O stage passa a nascer ao LADO do destino.
SKILLS_PARENT="$(dirname -- "$LEON_SKILLS_DIR")"
SKILLS_STAGE="$SKILLS_PARENT/.skills-stage-$TX_ID"
SKILLS_BACKUP="$SKILLS_PARENT/.skills-backup-$TX_ID"
SKILLS_FAILED="$SKILLS_PARENT/.skills-failed-$TX_ID"
case "$LEON_SKILLS_DIR" in "$HOME"/*) ;; *) fatal "o catálogo de skills precisa ficar dentro da home." ;; esac
# 22/09: o pai do catalogo e conferido ANTES de qualquer mutacao, e o erro diz o motivo
# real. Antes o cliente so via "nao consegui ativar o catalogo Codex assinado" depois da
# casa ja estar sem catalogo, sem pista nenhuma de qual dos tres casos era.
if [ ! -e "$SKILLS_PARENT" ]; then
  fatal "a pasta que guarda o catálogo de skills não existe: $SKILLS_PARENT. Crie-a (ou corrija LEON_SKILLS_DIR no .env) antes do /atualiza; nada foi trocado."
fi
if [ ! -d "$SKILLS_PARENT" ] || [ -L "$SKILLS_PARENT" ]; then
  fatal "a pasta que guarda o catálogo de skills não é um diretório real: $SKILLS_PARENT (link simbólico ou arquivo). Corrija LEON_SKILLS_DIR no .env; nada foi trocado."
fi
if [ ! -w "$SKILLS_PARENT" ]; then
  fatal "sem permissão de escrita na pasta que guarda o catálogo de skills: $SKILLS_PARENT. Corrija o dono/permissão dessa pasta; nada foi trocado."
fi
validate_runtime_roots 0 || fatal "os caminhos de dados são inseguros ou passam por link simbólico; runtime preservado."
# QUAL MOTOR ESTA CASA USA. O runtime, a base e a unit sao os MESMOS nos dois motores,
# entao tudo acima vale igual. O que segue e do CLI do Codex: versao pinada e config.toml.
# Numa casa que roda o outro motor esses arquivos nao existem, e exigi-los travava o
# /atualiza dela sem motivo. Valor ausente ou desconhecido cai no motor historico, que e
# o que toda casa instalada ate aqui usa.
LEON_ENGINE_CASA="$(env_get_from "$ENV_READ_SAFE" ENGINE_DEFAULT)"
[ -n "$LEON_ENGINE_CASA" ] || LEON_ENGINE_CASA="$(env_get_from "$ENV_READ_SAFE" ENGINE)"
case "$LEON_ENGINE_CASA" in claude) ;; *) LEON_ENGINE_CASA=codex ;; esac
if [ "$LEON_ENGINE_CASA" = codex ]; then
  if ! printf %s "$LEON_CODEX_CLI_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([_-][A-Za-z0-9.-]+)?$'; then
    fatal "a versão esperada do Codex CLI é inválida."
  fi
  CODEX_BIN_PATH="$LEON_DATA_DIR/codex-cli/releases/$LEON_CODEX_CLI_VERSION/bin/codex"
  validate_dedicated_codex_cli "$CODEX_BIN_PATH" "$LEON_DATA_DIR" "$LEON_CODEX_CLI_VERSION" \
    || fatal "o Codex CLI dedicado está ausente ou inseguro. Rode novamente o instalador Codex antes do /atualiza."
  INSTALLED_CODEX_VERSION="$(PATH="$(dirname "$NODE_BIN"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "$CODEX_BIN_PATH" --version 2>/dev/null \
    | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+([_-][A-Za-z0-9.-]+)?$/) { print $i; exit } }')"
  if [ "$INSTALLED_CODEX_VERSION" != "$LEON_CODEX_CLI_VERSION" ]; then
    fatal "o Codex CLI está em '${INSTALLED_CODEX_VERSION:-ausente}', mas este runtime exige $LEON_CODEX_CLI_VERSION. Rode novamente o instalador Codex antes do /atualiza."
  fi
fi
if [ "$TEST_MODE" = "1" ]; then
  case "$CENTRAL" in http://*|https://*) ;; *) fatal "endereço da central inválido." ;; esac
else
  case "$CENTRAL" in https://*) ;; *) fatal "a central de licença precisa usar HTTPS." ;; esac
fi

mkdir -p -- "$TX_ROOT" "$CODEX_HOME_DIR" "$LEON_TMPDIR" "$LEON_WORK_AREA" \
  "$BRAIN_DIR" "$PERSONA_DIR" "$LEON_MISSIONS_DIR" "$LEON_PROMISES_DIR" "$LEON_MISSION_OUTPUT_DIR"
# 0.7: a casa do dono ganha o lugar dele. Fora da transacao de proposito: a pasta
# pessoal nao entra em rollback, porque o updater nunca a modifica.
ensure_skills_personal_dir || fatal "nao consegui preparar a pasta de skills pessoais."
chmod 0700 "$LEON_DATA_DIR" "$TX_ROOT" "$CODEX_HOME_DIR" 2>/dev/null || true
validate_runtime_roots 1 || fatal "os caminhos de dados mudaram durante a preparação; runtime preservado."
# 22/09: varre restos de rodadas mortas ANTES de começar. Roda nos dois lugares porque o
# .env pode mandar o catálogo pra fora do LEON_DATA_DIR, e o histórico do cliente tem
# stage velho nos dois. O backup da transação corrente nunca é tocado (carimbo por TX_ID).
limpa_restos_de_skills "$LEON_DATA_DIR"
[ "$SKILLS_PARENT" = "$LEON_DATA_DIR" ] || limpa_restos_de_skills "$SKILLS_PARENT"
[ ! -e "$SKILLS_STAGE" ] && [ ! -e "$SKILLS_BACKUP" ] && [ ! -e "$SKILLS_FAILED" ] \
  || fatal "já existe uma transação de skills com os mesmos caminhos."
mkdir -m 0700 "$TX_DIR"
printf '%s\n' "$INSTALL_DIR" > "$TX_DIR/live-path"
printf '%s\n' "$BACKUP" > "$TX_DIR/backup-path"
printf '%s\n' "$FAILED" > "$TX_DIR/failed-path"
printf '%s\n' "$CONFIG_PATH" > "$TX_DIR/config-path"
printf '%s\n' "$UNIT_PATH" > "$TX_DIR/unit-path"
printf '%s\n' "$SERVICE" > "$TX_DIR/service-name"
printf '%s\n' "LEON_UPDATE_TX_$TX_ID" > "$TX_DIR/cron-marker"
printf '%s\n' "$THREAD_ARG" > "$TX_DIR/thread-id"
printf '%s\n' "$CHAT_ARG" > "$TX_DIR/chat-id"
printf '%s\n' "$LEON_SKILLS_DIR" > "$TX_DIR/skills-path"
printf '%s\n' "$SKILLS_BACKUP" > "$TX_DIR/skills-backup-path"
printf '%s\n' "$SKILLS_FAILED" > "$TX_DIR/skills-failed-path"
# Report de versao HONESTO (fix report-falso): new-version/email/central sao gravados
# ADIANTE, junto do prev-version, DEPOIS que $version existe (. RELEASE_METADATA na ~1801).
# FIX 02/09 (bug que travou a 2.4.17): gravar $version AQUI estourava "version: unbound
# variable" sob set -u — $version so nasce 47 linhas abaixo. O update morria antes de
# trocar o bridge e o vigia via "assinatura igual, sem sinal de conclusao".
printf '0\n' > "$TX_DIR/skills-had-original"
printf '0\n' > "$TX_DIR/skills-applied"

HAD_CONFIG=0
if [ -f "$CONFIG_PATH" ]; then
  cp -p -- "$CONFIG_PATH" "$TX_DIR/config.backup"
  HAD_CONFIG=1
fi
printf '%s\n' "$HAD_CONFIG" > "$TX_DIR/had-config"
printf '0\n' > "$TX_DIR/config-applied"
HAD_UNIT=0
if [ -f "$UNIT_PATH" ]; then
  cp -p -- "$UNIT_PATH" "$TX_DIR/unit.backup" 2>/dev/null || true
  [ -f "$TX_DIR/unit.backup" ] && HAD_UNIT=1
fi
printf '%s\n' "$HAD_UNIT" > "$TX_DIR/had-unit"
WAS_ACTIVE=0
WAS_ENABLED=0
if service_read is-active "$SERVICE" >/dev/null 2>&1; then WAS_ACTIVE=1; fi
if service_read is-enabled "$SERVICE" >/dev/null 2>&1; then WAS_ENABLED=1; fi
printf '%s\n' "$WAS_ACTIVE" > "$TX_DIR/was-active"
printf '%s\n' "$WAS_ENABLED" > "$TX_DIR/was-enabled"
printf '0\n' > "$TX_DIR/unit-applied"
printf 'prepared\n' > "$TX_DIR/status"

EMAIL_ENC="$(printf %s "$EMAIL" | "$PYTHON_BIN" -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip(), safe=""))')"
RELEASE_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/leon-release.XXXXXX.json")"
RELEASE_SIGNATURE="$(mktemp "${TMPDIR:-/tmp}/leon-release.XXXXXX.sig")"
RELEASE_PUBLIC_KEY="$(mktemp "${TMPDIR:-/tmp}/leon-release.XXXXXX.pem")"
RELEASE_METADATA="$(mktemp "${TMPDIR:-/tmp}/leon-release.XXXXXX.env")"
# 02/set: manifesto teimoso (mesma blindagem dos downloads de artefato) — 5xx/429 momentâneo da
# central não pode matar o /atualiza. --retry-all-errors + --retry 4.
# 23/09 (cliente sem VPS): GitHub primeiro, central de reserva (baixa_manifesto_assinado, na
# cabeca). A versao instalada entra pra detectar espelho atrasado. Verificacao igual pras duas.
_INST_PRE="$(read_installed_release_identity "$INSTALL_DIR" 2>/dev/null | cut -f1)" || _INST_PRE=""
if ! baixa_manifesto_assinado "$CENTRAL" release-manifest.json release-manifest.sig \
    "$RELEASE_MANIFEST" "$RELEASE_SIGNATURE" 524288 4 "${_INST_PRE:-0.0.0}"; then
  fatal "nem o espelho no GitHub nem a central entregaram o manifesto assinado; runtime preservado."
fi
say "manifesto assinado baixado; origem=$MANIFESTO_ORIGEM${MANIFESTO_NOTA:+ ($MANIFESTO_NOTA)}"
printf '%s\n' "$MANIFESTO_ORIGEM" > "$TX_DIR/manifesto-origem" 2>/dev/null || true
validate_download_file "$RELEASE_MANIFEST" 524288 \
  && validate_download_file "$RELEASE_SIGNATURE" 64 64 \
  || fatal "manifesto ou assinatura excede o contrato de transporte; runtime preservado."
verify_release_manifest "$RELEASE_MANIFEST" "$RELEASE_SIGNATURE" "$RELEASE_PUBLIC_KEY" "$RELEASE_METADATA" \
  || fatal "assinatura ou contrato da release inválido; runtime preservado."
RELEASE_MANIFEST_SHA256="$(sha256sum "$RELEASE_MANIFEST" | awk '{print $1}')"
# shellcheck disable=SC1090
. "$RELEASE_METADATA"
semver_ge "$version" "$minVersion" || fatal "release abaixo da versão mínima assinada."
# MINIMA, nao exata (2.4.34): a igualdade cravada aqui foi a parede que segurou a frota
# inteira na 2.4.33 — quem estava na 0.147 levava fatal ANTES de trocar qualquer arquivo e
# nao recebia nada da release (liberdade, /effort, entrada duravel), embora o pacote rodasse
# perfeitamente na 0.147. So o Astra depende do CLI novo, e ele ja tem gate proprio em runtime.
# Guardo a minima pedida pra tentar subir o CLI pelo caminho nativo mais adiante, best-effort.
LEON_CODEX_CLI_MINIMA="$codexCliVersion"
if ! semver_ge "$LEON_CODEX_CLI_VERSION" "$LEON_CODEX_CLI_MINIMA"; then
  CODEX_CLI_ABAIXO_DA_MINIMA=1
  say "   o Codex CLI desta casa ($LEON_CODEX_CLI_VERSION) é anterior ao mínimo da release ($LEON_CODEX_CLI_MINIMA); sigo com o update e tento subir o motor no fim."
fi
[ "$nodeVersion" = "$LEON_NODE_VERSION" ] \
  || fatal "a release exige Node $nodeVersion; rode o instalador antes do /atualiza."
# 02/set (blindagem pra escala): o marcador .leon-release.json é escrito pelo PRÓPRIO updater.
# Se corromper (queda de energia no meio de uma escrita, disco cheio), ele NÃO pode cortar o
# canal de conserto — não é perigo de segurança, só um arquivo interno bobo. A assinatura da
# release nova JÁ foi conferida (linha ~1768) e a versão-mínima também (~1773). Marcador ausente
# a própria função já trata como versão legada/vazia; aqui trato o CORROMPIDO igual a "versão
# desconhecida" e sigo — no pior caso o release_identity_acceptable abaixo decide upgrade/downgrade
# com versão vazia (aceita a nova, que é o desejado num marcador ilegível).
if ! INSTALLED_RELEASE_IDENTITY="$(read_installed_release_identity "$INSTALL_DIR")"; then
  # Fable: a sentinela tem que ser 0.0.0 (não vazia). Versão vazia faz semver("") estourar
  # SystemExit e o release_identity_acceptable abaixo cai em fatal com mensagem enganosa de
  # "downgrade" — o conserto seria inócuo. Com 0.0.0 o marcador corrompido se comporta IGUAL ao
  # marcador AUSENTE (read_installed_release_version já usa 0.0.0 nesse caso): new>0.0.0 → aceita
  # a release nova, que é o desejado. TRADE-OFF registrado: marcador corrompido desarma o
  # anti-downgrade (uma release velha, porém assinada e >= minVersion, seria aceita). É risco
  # IDÊNTICO ao já aceito para marcador ausente, exige corrupção local + central servindo release
  # velha, e TLS+assinatura barram MITM. Aceitável.
  say "⚠️ marcador de versão instalada ilegível/corrompido — trato como versão desconhecida (0.0.0) e sigo (a assinatura da release nova já foi validada). O update reescreve o marcador ao final."
  INSTALLED_RELEASE_IDENTITY=$'0.0.0\t'
fi
IFS=$'\t' read -r INSTALLED_RELEASE_VERSION INSTALLED_RELEASE_DIGEST <<< "$INSTALLED_RELEASE_IDENTITY"
# Report de versao HONESTO (movido pra CA no fix 02/09): agora $version, $EMAIL e $CENTRAL
# ja existem (. RELEASE_METADATA rodou acima). new-version = a versao que o finalizador
# reporta no succeeded; prev-version = a antiga que ele reporta no rollback.
printf '%s\n' "$version" > "$TX_DIR/new-version" 2>/dev/null || true
printf '%s\n' "$EMAIL"   > "$TX_DIR/report-email" 2>/dev/null || true
printf '%s\n' "$CENTRAL" > "$TX_DIR/report-central" 2>/dev/null || true
# F1.5 (sinal da frota): o finalizador manda o RESULTADO da madrugada pra central via
# /diagnostico. Guarda no tx o machine_id e se foi ciclo automatico (sem tty), pra o
# rastro dizer se o /atualiza da madrugada deu certo ou o motivo do erro.
printf '%s\n' "$(env_get_from "$ENV_READ_SAFE" LEON_MACHINE_ID)" > "$TX_DIR/report-machine-id" 2>/dev/null || true
printf '%s\n' "${LEON_UPDATE_AUTO:+1}" > "$TX_DIR/report-auto" 2>/dev/null || true
# prev-version pro report honesto no rollback (o TX_DIR ja existe desde a preparacao).
printf '%s\n' "$INSTALLED_RELEASE_VERSION" > "$TX_DIR/prev-version" 2>/dev/null || true
# FREIO DE VERSAO IGUAL (16/09). Antes daqui, versao igual com digest igual era
# ACEITA e o script seguia: baixava o pacote, trocava os arquivos e REINICIAVA o
# agente do dono. Medido na frota: uma casa reinstalou a MESMA release 4x em 50
# segundos, 2x no dia seguinte, e numa madrugada reprovou na prova de saude e
# reverteu. Cada reinstalacao reinicia o agente e mata o trabalho em andamento.
# Nada a fazer e uma resposta legitima, e precisa ser reportada, senao a
# madrugada desaparece do rastro da central.
if [ "${LEON_FORCE:-}" != 1 ] \
  && [ -n "${INSTALLED_RELEASE_DIGEST:-}" ] \
  && [ "$version" = "$INSTALLED_RELEASE_VERSION" ] \
  && [ "$RELEASE_MANIFEST_SHA256" = "$INSTALLED_RELEASE_DIGEST" ]; then
  # 2.6.8 (incidente 23/09): o vigia da casa (leon-base/scripts/update-verdict.sh, outro artefato)
  # so reconhece "ja atual" com grep 'ltima vers' nas 20 ultimas linhas deste log. A frase antiga
  # nao tinha isso e o dono ouvia "A atualizacao nao completou" estando na versao certa. A linha
  # passa a conter a frase que o vigia ja le; status, codigo de saida e relato a central iguais.
  say "ja estava na ultima versao $version com o mesmo digest; nada a trocar (LEON_FORCE=1 reinstala mesmo assim)"
  report_diagnostico_from_tx "$TX_DIR" ok "ja na versao $version; nada a fazer" 2>/dev/null || true
  # Pedido humano merece resposta; ciclo da madrugada fica em silencio, mesma
  # doutrina do resto do script.
  if [ -n "${CHAT_ARG:-}" ] || [ -z "${LEON_UPDATE_AUTO:-}" ]; then
    notify_from_runtime "$INSTALL_DIR" "✅ Já estou na versão $version. Nada pra trocar." "${THREAD_ARG:-}" "${CHAT_ARG:-}" 2>/dev/null || true
  fi
  printf 'skipped\n' > "$TX_DIR/status" 2>/dev/null || true
  exit 0
fi
[ "${LEON_FORCE:-}" != 1 ] || say "LEON_FORCE=1: reinstalando $version por ordem do dono"
release_identity_acceptable "$version" "$RELEASE_MANIFEST_SHA256" "$INSTALLED_RELEASE_VERSION" "${INSTALLED_RELEASE_DIGEST:-}" \
  || fatal "manifesto assinado é downgrade, replay ambíguo ou equivoca a release $INSTALLED_RELEASE_VERSION."

TARBALL="$(mktemp "${TMPDIR:-/tmp}/leon-package.XXXXXX.tar.gz")"
say "baixando pacote para transacao $TX_ID"
# PACOTE-BASE (pago). 23/09 (cliente sem VPS): o sha e o tamanho do manifesto assinado decidem
# se cada fonte vale. Com LEON_LICENCA_ASSINADA=1 e licenca valida conferida OFFLINE (e fora da
# lista de revogacao assinada, buscada no GitHub primeiro): copia guardada desta casa, depois o
# pacote cifrado do espelho, e a central por ultimo. Sem licenca assinada (padrao de hoje): a
# central continua sendo quem libera o pacote (401 a 404 = recusa real, para como antes) e SO
# quando ela nao responde entra a copia guardada, que o proprio /atualiza grava. "Nao responde"
# inclui o 5xx do Cloudflare com a VPS fora (521, 522, 523, 524, 530): ver central_fora_http.
LEON_CACHE_PACOTES="${LEON_CACHE_PACOTES:-$LEON_DATA_DIR/cache/pacotes}"
BASE_ORIGEM=""
LIC_CHAVE_PACOTE="-"
if [ "$(env_get_from "$ENV_READ_SAFE" LEON_LICENCA_ASSINADA 2>/dev/null)" = 1 ]; then
  _LIC_REV="$(mktemp "${TMPDIR:-/tmp}/leon-revogadas.XXXXXX")"
  baixa_revogacao "$CENTRAL" "$_LIC_REV"
  _LIC_RC=0
  _LIC_INFO="$(licenca_confere "$LEON_STATE_DIR/licenca-assinada.json" "$_LIC_REV" "$LEON_STATE_DIR")" || _LIC_RC=$?
  rm -f -- "$_LIC_REV"
  case "$_LIC_RC" in
    0) IFS=$'\t' read -r _LIC_ID _LIC_ATE _LIC_VENC LIC_CHAVE_PACOTE <<< "$_LIC_INFO"
       if [ "$_LIC_VENC" = 1 ]; then
         # vencida: nao abre o pacote cifrado; segue o caminho da central (que renova) e, sem ela,
         # a copia guardada, igual a casa sem licenca assinada.
         say "licenca assinada ${_LIC_ID} VENCIDA em ${_LIC_ATE}; sigo pelo caminho da central"; _LIC_RC=1
       else
         say "licenca assinada conferida offline (${_LIC_ID}, valida ate ${_LIC_ATE})"
       fi ;;
    3) fatal "a licenca desta casa esta na lista de revogacao assinada; nada foi trocado." ;;
    *) say "licenca assinada ausente ou invalida; sigo pelo caminho da central" ;;
  esac
  if [ "$_LIC_RC" = 0 ]; then
    if pacote_do_cache "$base_sha256" "$base_bytes" "$TARBALL"; then BASE_ORIGEM=cache
    elif pacote_cifrado_do_espelho leon-base-curated.tar.gz "$base_sha256" "$base_bytes" "$TARBALL" "$LIC_CHAVE_PACOTE"; then BASE_ORIGEM=espelho-cifrado
    fi
  fi
fi
if [ -z "$BASE_ORIGEM" ]; then
  # 02/set: a central insiste num soluco momentaneo (--retry-all-errors em 5xx/429). Recusa
  # EXPLICITA da licenca (401, 402, 403, 404) para, como antes. 23/09 noite (revisor): a central
  # fica atras do Cloudflare, e com a VPS fora ele RESPONDE (521, 522, 523, 524, 530), nao fica
  # mudo. Por isso "central fora" e qualquer 5xx, o 408, o 429, sem codigo (000) ou transferencia
  # quebrada: a copia guardada do mesmo sha assume; sem copia, para com motivo claro. Com copia
  # guardada boa, uma tentativa so (cada 522 do Cloudflare leva uns 15 s).
  _TENT_BASE=4
  if [ -n "${LEON_CACHE_PACOTES:-}" ] && [ -f "$LEON_CACHE_PACOTES/$base_sha256" ] \
     && confere_sha_tamanho "$LEON_CACHE_PACOTES/$base_sha256" "$base_sha256" "$base_bytes"; then
    _TENT_BASE=1
  fi
  _CURL_RC=0
  HTTP_CODE="$(curl_common -sS --max-filesize "$base_bytes" --retry "$_TENT_BASE" --retry-delay 2 --retry-connrefused $CURL_RETRY_ALL --connect-timeout 10 \
      --max-time 180 -w '%{http_code}' -o "$TARBALL" \
      "$CENTRAL/download-codex?email=$EMAIL_ENC")" || _CURL_RC=$?
  if [ "$HTTP_CODE" = 200 ] && [ "$_CURL_RC" = 0 ]; then
    BASE_ORIGEM=central
  elif central_fora_http "$HTTP_CODE" "$_CURL_RC"; then
    say "   a central nao respondeu de verdade (HTTP ${HTTP_CODE:-000}, curl $_CURL_RC); tento a copia guardada do pacote-base"
    pacote_do_cache "$base_sha256" "$base_bytes" "$TARBALL" \
      || fatal "a central nao respondeu (HTTP ${HTTP_CODE:-000}) e esta casa ainda nao tem copia guardada deste pacote-base; nada foi trocado."
    BASE_ORIGEM=cache
  else
    fatal "a central recusou o download (HTTP $HTTP_CODE); nada foi trocado."
  fi
fi
verify_signed_artifact "$TARBALL" "$base_sha256" "$base_bytes" "pacote-base"
say "   pacote-base: origem=$BASE_ORIGEM"
printf '%s\n' "$BASE_ORIGEM" > "$TX_DIR/origem-base" 2>/dev/null || true
guarda_pacote_no_cache "$TARBALL" "$base_sha256"

if ! "$PYTHON_BIN" - "$TARBALL" <<'PY'
import posixpath, re, sys, tarfile

archive = sys.argv[1]
try:
    source = tarfile.open(archive, "r:gz")
    members = source.getmembers()
except (OSError, tarfile.TarError):
    raise SystemExit(1)
if not members or len(members) > 100000:
    raise SystemExit(1)
total = 0
private_marker = re.compile(br"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----")
for member in members:
    name = member.name
    if not name or any(ord(ch) < 32 for ch in name):
        raise SystemExit(1)
    normalized = posixpath.normpath(name)
    if normalized == ".":
        if name not in (".", "./") or not member.isdir():
            raise SystemExit(1)
        continue
    if name.startswith("/") or normalized in ("", "..") or normalized.startswith("../"):
        raise SystemExit(1)
    parts = normalized.split("/")
    if any(part.casefold() == "keys" for part in parts) or parts[-1] == ".env":
        raise SystemExit(1)
    if member.isdev() or member.isfifo() or member.islnk():
        raise SystemExit(1)
    if member.issym():
        target = member.linkname
        resolved = posixpath.normpath(posixpath.join(posixpath.dirname(normalized), target))
        if not target or target.startswith("/") or resolved == ".." or resolved.startswith("../"):
            raise SystemExit(1)
    if member.isfile():
        total += member.size
        if member.size > 536870912 or total > 2147483648:
            raise SystemExit(1)
        handle = source.extractfile(member)
        if handle is None:
            raise SystemExit(1)
        tail = b""
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            window = tail + chunk
            if private_marker.search(window):
                raise SystemExit(1)
            tail = window[-128:]
raise SystemExit(0)
PY
then
  fatal "o pacote é corrompido ou contém caminhos, links ou tipos inseguros."
fi

EXTRACT_TMP="$(mktemp -d "$LIVE_PARENT/.${LIVE_BASE}.extract-$TX_ID.XXXXXX")"
tar --no-same-owner --no-same-permissions --delay-directory-restore \
  -xzf "$TARBALL" -C "$EXTRACT_TMP"
if ! "$PYTHON_BIN" - "$EXTRACT_TMP" <<'PY'
import os, sys
root = os.path.realpath(sys.argv[1])
for base, dirs, files in os.walk(root, followlinks=False):
    for name in dirs + files:
        path = os.path.join(base, name)
        if os.path.islink(path):
            target = os.path.realpath(path)
            if target != root and not target.startswith(root + os.sep):
                raise SystemExit(1)
raise SystemExit(0)
PY
then
  fatal "o pacote contém um link que escapa da área isolada."
fi

TOP_COUNT="$(find "$EXTRACT_TMP" -mindepth 1 -maxdepth 1 -printf x | wc -c)"
FIRST_TOP="$(find "$EXTRACT_TMP" -mindepth 1 -maxdepth 1 -print -quit)"
if [ "$TOP_COUNT" -eq 1 ] && [ -d "$FIRST_TOP" ]; then
  PACKAGE_ROOT="$FIRST_TOP"
else
  PACKAGE_ROOT="$EXTRACT_TMP"
fi
[ -n "$(find "$PACKAGE_ROOT" -mindepth 1 -print -quit)" ] || fatal "o pacote não contém arquivos."
if find "$PACKAGE_ROOT" -xdev -name keys -print -quit 2>/dev/null | grep -q . \
   || find "$PACKAGE_ROOT" -xdev -name .env -print -quit 2>/dev/null | grep -q . \
   || LC_ALL=C grep -R -l --binary-files=text -E -- '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' "$PACKAGE_ROOT" >/dev/null 2>&1; then
  fatal "o pacote-base contém credencial ou material de chave privada."
fi
if [ "$(basename "$PACKAGE_ROOT")" != "leon-base" ] \
   || ! validate_curated_base_manifest "$PACKAGE_ROOT"; then
  fatal "o manifesto interno do pacote-base curado não confere."
fi

for protected in .env sessions.json topics.json codex-mode.json cursor-mode.json .meta-token.json .meta-connect.json promises missions brain extensoes persona; do
  if [ -e "$PACKAGE_ROOT/$protected" ] || [ -L "$PACKAGE_ROOT/$protected" ]; then
    fatal "o pacote tentou substituir estado do usuário: $protected."
  fi
done
if LC_ALL=C grep -R -l --binary-files=text -- "$DANGEROUS_FLAG" "$PACKAGE_ROOT" >/dev/null 2>&1; then
  fatal "o pacote contém uma opção proibida de contornar a segurança do Codex."
fi
if find "$PACKAGE_ROOT" -xdev -perm /6000 -print -quit | grep -q .; then
  fatal "o pacote contém arquivo com bit privilegiado."
fi

if [ -e "$STAGE" ] || [ -e "$BACKUP" ]; then
  fatal "já existe uma transação com os mesmos caminhos."
fi
mkdir -m 0700 "$STAGE"
cp -a "$PACKAGE_ROOT"/. "$STAGE"/
rm -f -- "$STAGE/base-manifest.json"
normalize_agent_base "$STAGE/AGENT-BASE.md" "$LEON_SKILLS_DIR"
# NUCLEO UNICO (23/08): as pecas da doutrina (nucleo + delta de motor) vem no pacote e
# moram na PERSONA, nao no runtime. O install-leon.sh move na instalacao; o updater
# tem que fazer o mesmo, senao a casa atualizada fica com o nucleo velho na persona e o
# novo parado no stage (bug pego na Babi: NUCLEO-LEON.md no ~/socio-ia, nao na persona).
# So NORMALIZA aqui. A instalacao na persona VIVA fica pra depois da validacao: a persona e
# estado da casa, e escrever nela antes de aprovar deixaria um nucleo invalido grudado mesmo
# com a release recusada (o rename nem chegou a acontecer, mas a persona ja teria mudado).
for _peca in NUCLEO-LEON.md _MOTOR-CLAUDE.md _MOTOR-CODEX.md _REGRAS-DURAS.md CAMINHOS-CANONICOS.md; do
  [ -f "$STAGE/$_peca" ] || continue
  normalize_agent_base "$STAGE/$_peca" "$LEON_SKILLS_DIR" 2>/dev/null || true
done

# A release nova so pode ser promovida se a doutrina dela sobreviver a guarda do bridge. Reprovou:
# nada e trocado (nem o runtime, nem a persona) e a casa segue na versao de antes; o dono recebe a
# causa e a central recebe o diagnostico com motivo=placeholder. Rodar isto DEPOIS da normalizacao
# e de propósito: e o texto final, o mesmo que o bridge veria no primeiro turno.
if ! validate_doutrina_sem_placeholder "$STAGE" "$STAGE" "$INSTALL_DIR/.env"; then
  report_diagnostico_from_tx "$TX_DIR" erro "placeholder ${DOUTRINA_PLACEHOLDER:-LEON_?} em ${DOUTRINA_PLACEHOLDER_ARQ:-AGENT-BASE.md}"
  fatal "a release veio com doutrina inválida (placeholder ${DOUTRINA_PLACEHOLDER:-LEON_?} em ${DOUTRINA_PLACEHOLDER_ARQ:-AGENT-BASE.md}); continuo na versão de antes."
fi

# Aprovada: agora sim as pecas entram na persona viva (mesmo efeito de antes, uma etapa depois).
for _peca in NUCLEO-LEON.md _MOTOR-CLAUDE.md _MOTOR-CODEX.md _REGRAS-DURAS.md CAMINHOS-CANONICOS.md; do
  if [ -f "$STAGE/$_peca" ]; then
    install -m 0600 "$STAGE/$_peca" "$PERSONA_DIR/$_peca" 2>/dev/null || true
    rm -f -- "$STAGE/$_peca"
  fi
done
# Modelo efetivo desta casa: o que o instalador provou no login (gravado no .env),
# senao o default. Vale pro config.toml candidato, pro smoke e pro .env regravado.
CODEX_MODEL_EFETIVO="gpt-5.6-sol"
if _m="$(safe_env_value "$INSTALL_DIR/.env" CODEX_MODEL 2>/dev/null)" \
  && printf '%s' "$_m" | grep -qE '^[A-Za-z0-9._-]+$'; then
  CODEX_MODEL_EFETIVO="$_m"
fi
unset _m
# O config.toml e do CLI do Codex. Numa casa que roda o outro motor ele nao existe e nao
# faz falta: sem candidato gerado, o commit la embaixo simplesmente nao o aplica (o passo
# ja era condicionado ao arquivo existir).
if [ "$LEON_ENGINE_CASA" = codex ]; then
  # o molde vai sempre pro smoke do modelo; o candidato so existe no CODEX_HOME do LEON.
  write_codex_config_candidate "$TX_DIR/config.molde" \
    || fatal "não consegui gerar o perfil Codex root-deny canônico."
  if codex_home_do_dono; then
    say "   config.toml: o CODEX_HOME desta casa é do dono ($(leon_preserva codex-home-do-dono "$ENV_READ_SAFE" "$LEON_DATA_DIR" 2>/dev/null)); não escrevo config.toml nenhum."
  else
    funde_config_do_dono "$CONFIG_PATH" "$TX_DIR/config.molde" "$TX_DIR/config.candidate" \
      || fatal "não consegui juntar o config.toml do dono com o molde; nada foi trocado."
  fi
fi

# O bridge v2 depende do adapter e do shim da mesma versão. Baixamos um bundle
# indivisível, validamos hash, lista exata e sintaxe, e só então sobrepomos o stage.
BUNDLE_TMP="$(mktemp "${TMPDIR:-/tmp}/leon-codex-v2.XXXXXX.tar.gz")"
# GitHub primeiro, central de reserva; so aceita o que bate sha e tamanho do manifesto.
if ! baixa_artefato_verificado "$CENTRAL" "$bundle_url" "$BUNDLE_TMP" "$bundle_bytes" "$bundle_sha256" "$bundle_bytes" 4; then
  fatal "não consegui baixar o runtime Codex v2 completo."
fi
say "   bundle: origem=$ARTEFATO_ORIGEM"
printf '%s\n' "$ARTEFATO_ORIGEM" > "$TX_DIR/origem-bundle" 2>/dev/null || true
verify_signed_artifact "$BUNDLE_TMP" "$bundle_sha256" "$bundle_bytes" "runtime Codex v2"

if ! "$PYTHON_BIN" - "$BUNDLE_TMP" <<'PY'
import posixpath, sys, tarfile

required = {
    "bridge.cjs",
    "capabilities.json",
    "appserver/adapter.cjs",
    "appserver/index.cjs",
    "appserver/package.json",
    "lib/onboarding.js",
    "lib/seletor.cjs",
    "lib/inbound.js",
    "lib/meta-connect.js",
    "lib/meta-mcp-codex-filter.cjs",
    "lib/meta-account-guard.cjs",
    "lib-motores/codex-appserver.cjs",
    "lib-motores/claude.cjs",
    "lib-motores/index.cjs",
    "smoke/appserver-smoke.cjs",
    "workers/piper.js",
}
directories = {"appserver", "lib", "lib-motores", "smoke", "workers",
               "leon2", "leon2/bin", "leon2/lib", "leon2/nucleo", "leon2/nucleo/papeis"}  # LEON 2.0 (2.7.0)
try:
    members = tarfile.open(sys.argv[1], "r:gz").getmembers()
except (OSError, tarfile.TarError):
    raise SystemExit(1)
seen = set()
for member in members:
    name = posixpath.normpath(member.name)
    if name == ".":
        if member.name not in (".", "./") or not member.isdir():
            raise SystemExit(1)
        continue
    if member.name.startswith("/") or name in ("", "..") or name.startswith("../"):
        raise SystemExit(1)
    if member.isdir():
        if name not in directories:
            raise SystemExit(1)
        continue
    if not member.isfile() or member.size > 8_000_000:  # 22/09 (2.6.7): bridge passou de 2 MB
        raise SystemExit(1)
    parent = posixpath.dirname(name)
    if parent:
        if parent not in directories:
            raise SystemExit(1)
    elif name not in required:
        raise SystemExit(1)
    seen.add(name)
raise SystemExit(0 if required <= seen else 1)
PY
then
  fatal "o bundle Codex v2 é incompleto ou contém caminho inseguro."
fi

BUNDLE_EXTRACT="$(mktemp -d "$LIVE_PARENT/.${LIVE_BASE}.bundle-$TX_ID.XXXXXX")"
tar --no-same-owner --no-same-permissions -xzf "$BUNDLE_TMP" -C "$BUNDLE_EXTRACT"
"$PYTHON_BIN" - "$BUNDLE_EXTRACT/capabilities.json" <<'PY' \
  || fatal "a matriz de capacidades do runtime é inválida."
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
if d.get("schema")!=1 or d.get("kind")!="leon-codex-capabilities": raise SystemExit(1)
if d.get("attachments",{}).get("curatedOfficePreconversion") is not False: raise SystemExit(1)
if d.get("optionalNotProvisionedByCore",{}).get("googleWorkspace") is not False: raise SystemExit(1)
PY
for runtime_js in bridge.cjs appserver/adapter.cjs lib/onboarding.js lib/inbound.js lib/meta-connect.js lib/meta-mcp-codex-filter.cjs lib/meta-account-guard.cjs lib-motores/codex-appserver.cjs lib-motores/claude.cjs lib-motores/index.cjs smoke/appserver-smoke.cjs workers/piper.js; do
  "$NODE_BIN" --check "$BUNDLE_EXTRACT/$runtime_js" >/dev/null 2>&1 \
    || fatal "o runtime Codex v2 contém JavaScript inválido: $runtime_js."
done
LEGACY_NAME='open''claw'
if LC_ALL=C grep -Rqi -- "$LEGACY_NAME" "$BUNDLE_EXTRACT" \
   || LC_ALL=C grep -Rq --exclude='claude.cjs' --exclude='motor-claude.cjs' -- 'bypassPermissions' "$BUNDLE_EXTRACT" \
   || LC_ALL=C grep -R -l --binary-files=text -- "$DANGEROUS_FLAG" "$BUNDLE_EXTRACT" >/dev/null 2>&1 \
   || { bridge_e_leon2 "$BUNDLE_EXTRACT/bridge.cjs" && ! leon2_sintaxe_ok "$BUNDLE_EXTRACT"; } \
   || { ! bridge_e_leon2 "$BUNDLE_EXTRACT/bridge.cjs" && ! grep -q 'const LEON_CODEX_ONLY = true' "$BUNDLE_EXTRACT/bridge.cjs"; } \
   || { ! bridge_e_leon2 "$BUNDLE_EXTRACT/bridge.cjs" && ! grep -q 'criaMotor' "$BUNDLE_EXTRACT/bridge.cjs"; } \
   || ! [ -s "$BUNDLE_EXTRACT/lib-motores/index.cjs" ]; then
  fatal "o runtime Codex v2 reprovou a auditoria de identidade ou permissão."
fi
cp -a -- "$BUNDLE_EXTRACT"/. "$STAGE"/
rm -rf -- "$BUNDLE_EXTRACT"
BUNDLE_EXTRACT=""
rm -f -- "$BUNDLE_TMP"
BUNDLE_TMP=""

# Catálogo mínimo Codex: somente o artefato coberto pelo manifesto assinado.
# Não existe clone, overlay nem reaproveitamento de scripts do catálogo antigo.
SKILLS_TMP="$(mktemp "${TMPDIR:-/tmp}/leon-skills.XXXXXX.tar.gz")"
# GitHub primeiro, central de reserva; so aceita o que bate sha e tamanho do manifesto.
if ! baixa_artefato_verificado "$CENTRAL" "$skills_url" "$SKILLS_TMP" "$skills_bytes" "$skills_sha256" "$skills_bytes" 4; then
  fatal "não consegui baixar o catálogo Codex assinado."
fi
say "   skills: origem=$ARTEFATO_ORIGEM"
printf '%s\n' "$ARTEFATO_ORIGEM" > "$TX_DIR/origem-skills" 2>/dev/null || true
verify_signed_artifact "$SKILLS_TMP" "$skills_sha256" "$skills_bytes" "catálogo de skills"
audit_skills_archive "$SKILLS_TMP" \
  || fatal "o catálogo de skills contém membros inseguros ou incompletos."
# 22/09: o extract nasce no mesmo pai do destino, junto do stage. O `mv` logo abaixo
# (SKILLS_ROOT -> SKILLS_STAGE) sai de dentro do extract, entao os dois precisam estar
# no mesmo filesystem; e o stage, selado adiante, precisa ser vizinho do destino.
SKILLS_EXTRACT="$(mktemp -d "$SKILLS_PARENT/.skills-extract-$TX_ID.XXXXXX")"
tar --no-same-owner --no-same-permissions --delay-directory-restore \
  -xzf "$SKILLS_TMP" -C "$SKILLS_EXTRACT"
SKILLS_ROOT="$SKILLS_EXTRACT/leon-skills"
if [ ! -d "$SKILLS_ROOT" ] || [ -L "$SKILLS_ROOT" ] \
   || [ "$(find "$SKILLS_EXTRACT" -mindepth 1 -maxdepth 1 -printf x | wc -c)" -ne 1 ] \
   || ! validate_skills_manifest "$SKILLS_ROOT"; then
  fatal "o manifesto interno do catálogo de skills não confere."
fi
find -P "$SKILLS_ROOT" -type d -exec chmod 0700 -- {} + \
  || fatal "não consegui abrir o stage privado do catálogo para normalização."
mv -- "$SKILLS_ROOT" "$SKILLS_STAGE"
rmdir -- "$SKILLS_EXTRACT"
SKILLS_EXTRACT=""
normalize_skills_catalog "$SKILLS_STAGE" "$LEON_SKILLS_DIR" "$LEON_WORK_AREA" \
  || fatal "não consegui normalizar e selar o catálogo de skills."
SKILLS_EXPECTED_DIGEST="$(installed_skills_digest "$SKILLS_STAGE")" \
  || fatal "o catálogo de skills preparado perdeu sua integridade."
printf '%s\n' "$SKILLS_EXPECTED_DIGEST" > "$TX_DIR/skills-expected-digest"
rm -f -- "$SKILLS_TMP"
SKILLS_TMP=""

UPDATE_TMP="$(mktemp "${TMPDIR:-/tmp}/leon-updater.XXXXXX.sh")"
# GitHub primeiro, central de reserva; so aceita o que bate sha e tamanho do manifesto.
if ! baixa_artefato_verificado "$CENTRAL" "$updater_url" "$UPDATE_TMP" "$updater_bytes" "$updater_sha256" "$updater_bytes" 4; then
  fatal "não consegui baixar o atualizador candidato assinado."
fi
say "   updater: origem=$ARTEFATO_ORIGEM"
printf '%s\n' "$ARTEFATO_ORIGEM" > "$TX_DIR/origem-updater" 2>/dev/null || true
verify_signed_artifact "$UPDATE_TMP" "$updater_sha256" "$updater_bytes" "atualizador candidato"
if [ ! -s "$UPDATE_TMP" ] \
   || LC_ALL=C grep -q -- "$DANGEROUS_FLAG" "$UPDATE_TMP" \
   || ! grep -q 'verify_release_manifest' "$UPDATE_TMP" \
   || ! bash -n "$UPDATE_TMP"; then
  fatal "o atualizador candidato não passou nas validações."
fi
cp -f -- "$UPDATE_TMP" "$STAGE/update-pago.sh"
printf '%s\n' "$version" > "$STAGE/.leon-release-version"
chmod 0600 "$STAGE/.leon-release-version"
write_release_identity "$STAGE/.leon-release.json" "$version" "$RELEASE_MANIFEST_SHA256"
write_runtime_files_manifest "$STAGE"
chmod 0700 "$STAGE/update-pago.sh"
chmod u+x "$STAGE"/*.sh "$STAGE"/scripts/*.sh "$STAGE"/leon2/bin/* 2>/dev/null || true
find "$STAGE" -xdev -type d -exec chmod go-rwx {} +
find "$STAGE" -xdev -type f -exec chmod go-rwx {} +
"$NODE_BIN" --check "$STAGE/bridge.cjs" >/dev/null 2>&1 \
  || fatal "o motor preparado falhou no último teste de sintaxe."
[ -s "$STAGE/appserver/adapter.cjs" ] \
  && [ -s "$STAGE/lib/onboarding.js" ] \
  && [ -s "$STAGE/lib-motores/codex-appserver.cjs" ] \
  && [ -s "$STAGE/lib-motores/claude.cjs" ] \
  && [ -s "$STAGE/lib-motores/index.cjs" ] \
  && [ -s "$STAGE/smoke/appserver-smoke.cjs" ] \
  && [ -s "$STAGE/workers/piper.js" ] \
  && [ -s "$STAGE/capabilities.json" ] \
  || fatal "o stage perdeu uma peça obrigatória do runtime app-server."
"$NODE_BIN" --check "$STAGE/workers/piper.js" >/dev/null 2>&1 \
  || fatal "o worker Piper preparado falhou no último teste de sintaxe."
if bridge_e_leon2 "$STAGE/bridge.cjs"; then
  leon2_sintaxe_ok "$STAGE" || fatal "o LEON 2.0 preparado falhou no último teste de sintaxe."
else
  grep -q 'const LEON_CODEX_ONLY = true' "$STAGE/bridge.cjs" \
    || fatal "o stage não é Codex-only."
fi
bash -n "$STAGE/update-pago.sh" || fatal "o atualizador preparado falhou no último teste de sintaxe."
BRIDGE_SHA="$(sha256sum "$STAGE/bridge.cjs" | awk '{print $1}')"
printf '%s\n' "$BRIDGE_SHA" > "$TX_DIR/bridge-sha256"
# 17/09: familia do runtime ENTRANTE. Aqui e o primeiro ponto seguro: o stage ja
# passou por node --check e pelo BRIDGE_SHA acima (codigo assinado, extraido e
# conferido) e nada da casa viva foi mutado ainda. O sinal e o codigo, nao a
# versao: os bundles publicados hoje sao todos da familia LEGADA.
LEDGER_FAMILIA_ENTRANTE="$(familia_do_bridge "$STAGE/bridge.cjs")"
printf '%s\n' "$LEDGER_FAMILIA_ENTRANTE" > "$TX_DIR/ledger-familia-entrante"

# A copia que o cron executa fica fora do runtime que sera trocado.
cp -- "$SCRIPT_PATH" "$TX_DIR/finalize.sh"
chmod 0700 "$TX_DIR/finalize.sh"
CRON_MARKER="$(cat "$TX_DIR/cron-marker")"
if [ "$TEST_MODE" != "1" ] || [ "${LEON_TEST_ARM_CRON:-0}" = "1" ]; then
  if "$CRONTAB_BIN" -l > "$TX_DIR/crontab.backup" 2>/dev/null; then
    printf '1\n' > "$TX_DIR/had-crontab"
  else
    : > "$TX_DIR/crontab.backup"
    printf '0\n' > "$TX_DIR/had-crontab"
  fi
  CURRENT_CRON="$(cat "$TX_DIR/crontab.backup")"
  CRON_COMMAND="* * * * * /usr/bin/env bash $(printf '%q' "$TX_DIR/finalize.sh") --finalize $(printf '%q' "$TX_DIR") >/dev/null 2>&1 # $CRON_MARKER"
  { [ -z "$CURRENT_CRON" ] || printf '%s\n' "$CURRENT_CRON"; printf '%s\n' "$CRON_COMMAND"; } \
    | "$CRONTAB_BIN" -
  CRON_ARMED=1
fi

# Copia mais uma vez somente o estado mutavel. O bridge continua atendendo ate
# os dois renames, reduzindo a janela sem escrita a poucos milissegundos.
safe_copy_state_file "$INSTALL_DIR/.env" "$STAGE/.env" env \
  || fatal "o .env atual não é um arquivo regular seguro; runtime preservado."
[ ! -e "$INSTALL_DIR/sessions.json" ] || safe_copy_state_file "$INSTALL_DIR/sessions.json" "$STAGE/sessions.json" sessions \
  || fatal "sessions.json atual reprovou a migração segura."
[ ! -e "$INSTALL_DIR/topics.json" ] || safe_copy_state_file "$INSTALL_DIR/topics.json" "$STAGE/topics.json" topics \
  || fatal "topics.json atual reprovou a migração segura."
# META CONNECT (28/08): o token e o estado da conexão Meta moram em .meta-token.json /
# .meta-connect.json no WORKDIR (0600). ANTES desta linha o update os deixava no backup e o
# WORKDIR novo nascia sem token → getToken(WORKDIR) no boot retornava null, META_MCP_TOKEN
# ficava vazio, e o agente dizia "a conexão do Meta não chegou até mim" mesmo com o Meta
# conectado (bug de campo no Leon 99, e em toda a frota que conectou Meta e deu /atualiza).
# O bloco [mcp_servers.meta-ads] já re-entra no config (write_codex_config_candidate); aqui
# migramos o TOKEN físico pra ele não órfãozar.
[ ! -e "$INSTALL_DIR/.meta-token.json" ] || safe_copy_state_file "$INSTALL_DIR/.meta-token.json" "$STAGE/.meta-token.json" meta \
  || fatal ".meta-token.json atual reprovou a migração segura."
[ ! -e "$INSTALL_DIR/.meta-connect.json" ] || safe_copy_state_file "$INSTALL_DIR/.meta-connect.json" "$STAGE/.meta-connect.json" meta \
  || fatal ".meta-connect.json atual reprovou a migração segura."

# ONBOARDING · guarda de instalação existente. Quem chega por AQUI já é cliente: o
# update roda sobre uma casa que já existe. Sem esta semente, ligar a jornada de
# boas-vindas faria o dono de meses ser tratado como dono novo no primeiro turno
# depois do update, levando apresentação e sendo perguntado o nome. Semeamos o estado
# como jornada FECHADA. Instalação nova nasce sem este arquivo (o instalador não
# semeia nada) e é a única que roda a jornada. Estado já existente é preservado como
# está, inclusive um /reonboarding pedido pelo dono antes do update.
#
# A `etapa` semeada fica ACIMA do número de perguntas de propósito. Ela valia 3 quando
# a jornada tinha 3 perguntas, e virou um número mágico casado com o código: a Onda A
# acrescentou as 2 de alçada e um 3 literal passaria a jogar o cliente de meses dentro
# das perguntas novas, que é exatamente o que esta semente existe pra impedir. O
# módulo grampeia a etapa no total de perguntas ao ler, então um valor folgado fecha a
# jornada hoje e continua fechando se ela crescer de novo.
#
# E a semente ANTIGA, a que já está no disco do cliente que atualizou na 2.0.7/2.0.8,
# é NORMALIZADA aqui. Sem isto o `elif` abaixo nunca a alcança (ele só escreve quando
# o arquivo não existe), o `3` sobrevive ao update, e o dono de meses cai dentro das
# perguntas de alçada com a primeira mensagem ociosa dele virando lei permanente.
# Estado com `apresentado: true` e `dono` vazio é semente por definição: ninguém
# termina a jornada de verdade sem deixar ao menos o nome gravado.
if [ -e "$INSTALL_DIR/.onboarding-state.json" ]; then
  safe_copy_state_file "$INSTALL_DIR/.onboarding-state.json" "$STAGE/.onboarding-state.json" onboarding \
    || fatal ".onboarding-state.json atual reprovou a migração segura."
  "$PYTHON_BIN" - "$STAGE/.onboarding-state.json" <<'PY' || fatal "não consegui normalizar a semente do onboarding."
import json, os, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    raise SystemExit(0)          # estado ilegível: o módulo já cai em estado vazio sozinho
if not isinstance(data, dict):
    raise SystemExit(0)
dono = data.get("dono")
dono = dono if isinstance(dono, dict) else {}
# semente de qualquer versão: jornada marcada como aberta, sem nenhum dado do dono.
if data.get("apresentado") is True and data.get("forcado") is not True and not dono:
    if not isinstance(data.get("etapa"), int) or data["etapa"] < 99:
        data["etapa"] = 99
        tmp = path + ".migra-new"
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
PY
elif [ ! -e "$STAGE/.onboarding-state.json" ]; then
  printf '{\n  "versao": 1,\n  "etapa": 99,\n  "dono": {},\n  "apresentado": true,\n  "pendente": false,\n  "forcado": false,\n  "concluidoEm": null,\n  "grupoExplicado": true\n}\n' \
    > "$STAGE/.onboarding-state.json"
  chmod 0600 "$STAGE/.onboarding-state.json"
fi

injetar_handoff_update_verdict "$STAGE/scripts/update-verdict.sh" \
  || fatal "não consegui gravar o handoff do /atualiza no vigia do stage; runtime preservado."

# ---- MOTOR: tenta subir o CLI antes de gravar o .env do stage (2.4.34) -----
# Aqui e o unico lugar certo: o .env logo abaixo carrega o LEON_CODEX_CLI_VERSION que o bridge
# vai usar (bridge.cjs codexBin() deriva o caminho dessa variavel), e nada da casa viva foi
# mutado ainda (MUTATION_STARTED so liga depois). Se a subida falhar, o .env sai com a versao
# antiga e o update do bridge continua inteiro: a casa nunca fica sem motor.
if [ "$CODEX_CLI_ABAIXO_DA_MINIMA" = "1" ] && [ "$TEST_MODE" != "1" -o "${LEON_TEST_CLI_NATIVO:-0}" = "1" ]; then
  say "   subindo o motor Codex pelo caminho nativo (best-effort, teto de 5 min)..."
  if CODEX_CLI_NOVA="$(subir_codex_cli_nativo "$CODEX_BIN_PATH" "$LEON_DATA_DIR" \
      "$LEON_CODEX_CLI_MINIMA" "$TX_ID" "$NODE_BIN")" && [ -n "$CODEX_CLI_NOVA" ]; then
    LEON_CODEX_CLI_VERSION="$CODEX_CLI_NOVA"
    CODEX_BIN_PATH="$LEON_DATA_DIR/codex-cli/releases/$LEON_CODEX_CLI_VERSION/bin/codex"
    CODEX_CLI_SUBIU=1
    say "   motor Codex agora na $LEON_CODEX_CLI_VERSION."
  else
    say "   o motor Codex não subiu agora; sigo com a $LEON_CODEX_CLI_VERSION e tento de novo no próximo /atualiza."
  fi
fi
# ---- MOTOR CLAUDE: o irmao do passo de cima (23/09) --------------------------
# Casa Claude, ou casa que tem o CLI do Claude instalado (multimotor): garante a versao minima.
# Mesmo lugar e mesma regra do Codex: antes de gravar o .env do stage, nada vivo mutado ainda,
# falha nunca derruba o update.
CLAUDE_BIN_ATUAL="$(resolve_claude_cli "$(env_get_from "$ENV_READ_SAFE" CLAUDE_BIN)" || true)"
if { [ "$LEON_ENGINE_CASA" = claude ] || [ -n "$CLAUDE_BIN_ATUAL" ]; } \
   && [ "$TEST_MODE" != "1" -o "${LEON_TEST_CLI_NATIVO:-0}" = "1" ]; then
  [ -z "$CLAUDE_BIN_ATUAL" ] || CLAUDE_CLI_VERSAO_ATUAL="$(claude_cli_versao "$CLAUDE_BIN_ATUAL" "$(dirname "$NODE_BIN"):/usr/local/bin:/usr/bin:/bin" || true)"
  if [ -z "$CLAUDE_CLI_VERSAO_ATUAL" ] || ! semver_ge "$CLAUDE_CLI_VERSAO_ATUAL" "$LEON_CLAUDE_CLI_MINIMA" 2>/dev/null; then
    CLAUDE_CLI_ABAIXO_DA_MINIMA=1
    say "   o programa do Claude desta casa está em '${CLAUDE_CLI_VERSAO_ATUAL:-ausente}', abaixo do mínimo $LEON_CLAUDE_CLI_MINIMA; atualizando (best-effort, teto de 5 min)..."
    if CLAUDE_BIN_NOVO="$(subir_claude_cli "$LEON_DATA_DIR" "$LEON_CLAUDE_CLI_MINIMA" "$TX_ID" "$NODE_BIN")" && [ -n "$CLAUDE_BIN_NOVO" ]; then
      CLAUDE_CLI_SUBIU=1
      say "   programa do Claude agora na $(claude_cli_versao "$CLAUDE_BIN_NOVO" "$(dirname "$NODE_BIN"):/usr/local/bin:/usr/bin:/bin") ($CLAUDE_BIN_NOVO)."
    else
      CLAUDE_BIN_NOVO=""
      say "   não consegui atualizar o programa do Claude agora; a casa segue no de antes e o bridge tenta de novo em segundo plano quando o modelo for recusado."
    fi
  fi
fi

ENV_RECUSA=""
rewrite_runtime_env "$STAGE/.env" \
  || fatal "o teu .env tem linha que a versão nova recusaria (${ENV_RECUSA:-motivo não registrado}). Não mexi em nada: corrija essa linha e rode /atualiza de novo."

# ---- LEDGER DE SALAS: FAMILIA INSTALADA E PRE-CHECAGENS (17/09) ------------
# POR QUE EXATAMENTE AQUI: e o ultimo ponto com a casa INTACTA (MUTATION_STARTED
# liga logo abaixo). Toda recusa daqui preserva o runtime, sem rollback e sem
# restart. O bridge INSTALADO tem de ser lido agora porque depois dos renames ele
# passa a morar em $BACKUP/bridge.cjs.
# FATO MEDIDO 17/09: o bridge.cjs das casas de cliente tem ZERO ocorrencias de
# _resolveSessionsFile e le as salas em INSTALL_DIR/sessions.json; o runtime novo
# le em LEON_STATE_DIR/sessions.json. Sem a copia abaixo, a casa acorda com todas
# as salas vazias.
# REGRA DE OURO: COPIA, nunca move. INSTALL_DIR/sessions.json nunca e escrito,
# movido nem apagado por este script; ele viaja dentro do BACKUP pelo rename que
# ja existe, e por isso rollback_inline, rollback_transaction e cleanup_main
# devolvem a casa com as salas sem uma linha de codigo nova. Nao existe desfazer.
LEDGER_FAMILIA_INSTALADA="$(familia_do_bridge "$INSTALL_DIR/bridge.cjs")"
printf '%s\n' "$LEDGER_FAMILIA_INSTALADA" > "$TX_DIR/ledger-familia-instalada"
LEDGER_MIGRA=0
LEDGER_STATE_DIR=""
LEDGER_DESTINO=""
LEDGER_MARCA=""
LEDGER_COPIOU=0
LEDGER_SESSOES_DECLARADO=""
if [ "$LEDGER_FAMILIA_INSTALADA" = indeterminada ] || [ "$LEDGER_FAMILIA_ENTRANTE" = indeterminada ]; then
  report_diagnostico_from_tx "$TX_DIR" erro \
    "familia do runtime indeterminada (instalada=$LEDGER_FAMILIA_INSTALADA, entrante=$LEDGER_FAMILIA_ENTRANTE); nada trocado" || true
  fatal "não consegui identificar com segurança onde cada runtime guarda as conversas (instalada=$LEDGER_FAMILIA_INSTALADA, entrante=$LEDGER_FAMILIA_ENTRANTE); runtime preservado."
fi
# Onde o runtime ENTRANTE vai LER o ledger depois do commit.
if [ "$LEDGER_FAMILIA_ENTRANTE" = nova ]; then
  # Destino LIDO do .env do stage, NUNCA recalculado: e exatamente a variavel que
  # o bridge novo resolve: o .env do stage e o do dono (as linhas dele intactas) mais o que
  # faltava, e a unit nao tem EnvironmentFile. Sem override de operador: na casa do cliente nao ha
  # operador pra corrigir um palpite errado.
  LEDGER_STATE_DIR="$(safe_env_value "$STAGE/.env" LEON_STATE_DIR 2>/dev/null || true)"
  case "$LEDGER_STATE_DIR" in
    /*) ;;
    *) fatal "a configuração preparada não declara um caminho absoluto de estado (LEON_STATE_DIR); runtime preservado." ;;
  esac
  # A3 (revisao Astra 17/09): LEON_SESSIONS_FILE esta no NUCLEO da lib, entao a chave
  # do cliente SOBREVIVE ao filtro e chegava aqui, onde a simples presenca abortava.
  # Resultado: a casa que declarou o caminho (ate o proprio padrao) nunca mais
  # atualizava, de hora em hora, para sempre. Nao existe operador nessa casa pra
  # desfazer o palpite, entao a regra e: LER o valor, nunca abortar por presenca.
  LEDGER_SESSOES_DECLARADO="$(safe_env_value "$STAGE/.env" LEON_SESSIONS_FILE 2>/dev/null || true)"
  if [ -n "$LEDGER_SESSOES_DECLARADO" ]; then
    if ledger_sessions_file_honrado "$LEDGER_SESSOES_DECLARADO" "$LEDGER_STATE_DIR"; then
      # O runtime novo honra este caminho: ele VIRA o destino do ledger e a chave
      # continua ativa no .env do cliente.
      LEDGER_DESTINO="$LEDGER_SESSOES_DECLARADO"
      say "   conversas: o runtime novo vai ler o arquivo que o teu .env declara ($LEDGER_DESTINO)."
    else
      # O runtime novo recusaria este caminho no boot (exit 78) e a casa nao subiria. A linha
      # e do dono (23/09): comentar ou trocar seria mexer no .env dele. Paro ANTES de mutar
      # qualquer coisa e digo o que mudar; a casa segue na versao de hoje, inteira.
      report_diagnostico_from_tx "$TX_DIR" erro "LEON_SESSIONS_FILE do dono fora de LEON_STATE_DIR; nada trocado" || true
      fatal "o teu .env manda as conversas para $LEDGER_SESSOES_DECLARADO, e a versão nova só lê conversas dentro de $LEDGER_STATE_DIR. Não mexi no teu .env nem em nada: ajuste LEON_SESSIONS_FILE (ou apague a linha) e rode /atualiza de novo."
    fi
  else
    LEDGER_DESTINO="$LEDGER_STATE_DIR/sessions.json"
  fi
else
  LEDGER_DESTINO="$INSTALL_DIR/sessions.json"
fi
# Migra SO no unico sentido que perde sala: legado (le no INSTALL_DIR) -> novo
# (le no LEON_STATE_DIR). Casa que ja e da familia nova nunca tem o destino
# sobrescrito, nem com LEON_FORCE.
if [ "$LEDGER_FAMILIA_INSTALADA" = legada ] && [ "$LEDGER_FAMILIA_ENTRANTE" = nova ]; then
  LEDGER_MIGRA=1
fi
if [ "$LEDGER_MIGRA" = 1 ]; then
  LEDGER_MARCA="$LEDGER_STATE_DIR/.sessions.json.migrado"
  ledger_prepara_destino "$LEDGER_STATE_DIR" "$INSTALL_DIR" \
    || fatal "a pasta de estado do runtime novo não passou na checagem de segurança; runtime preservado."
  if [ -e "$INSTALL_DIR/sessions.json" ]; then
    safe_copy_state_file "$INSTALL_DIR/sessions.json" "$TX_DIR/ledger-origem-previa.json" sessions \
      || fatal "o arquivo de conversas atual não passou na validação; não troquei nada."
    ledger_salas_de "$TX_DIR/ledger-origem-previa.json" > "$TX_DIR/ledger-origem-salas" \
      || fatal "não consegui ler as conversas do arquivo atual; não troquei nada."
  else
    # Casa que nunca conversou: migracao vazia, e correto e boot vazio.
    : > "$TX_DIR/ledger-origem-salas"
  fi
  # Destino JA EXISTENTE: so pode ser orfao de uma tentativa que voltou atras,
  # porque o bridge legado instalado nao le esse caminho. O orfao e resolvido na
  # tentativa SEGUINTE, nunca na volta.
  if [ -e "$LEDGER_DESTINO" ]; then
    { [ -f "$LEDGER_DESTINO" ] && [ ! -L "$LEDGER_DESTINO" ]; } \
      || fatal "existe algo no lugar do arquivo de conversas do runtime novo e não é um arquivo comum; não troquei nada."
    LEDGER_DEST_SHA="$(sha256sum "$LEDGER_DESTINO" | awk '{print $1}')"
    LEDGER_MARCA_SHA="$(sed -n 's/^destino=//p' "$LEDGER_MARCA" 2>/dev/null | tail -1 || true)"
    if [ -n "$LEDGER_MARCA_SHA" ] && [ "$LEDGER_MARCA_SHA" = "$LEDGER_DEST_SHA" ]; then
      # Copia NOSSA, nao promovida: ninguem a leu (o bridge instalado e legado).
      # Sobrescreve a partir da origem fresca, guardando o anterior no tx.
      :
    else
      safe_copy_state_file "$LEDGER_DESTINO" "$TX_DIR/ledger-destino-previa.json" sessions \
        || fatal "já existe um arquivo de conversas no lugar do runtime novo e ele não é legível com segurança; não troquei nada."
      ledger_salas_de "$TX_DIR/ledger-destino-previa.json" > "$TX_DIR/ledger-destino-salas" \
        || fatal "já existe um arquivo de conversas no lugar do runtime novo e não consegui lê-lo; não troquei nada."
      if [ -n "$(LC_ALL=C comm -23 "$TX_DIR/ledger-destino-salas" "$TX_DIR/ledger-origem-salas")" ]; then
        # Mesclar inventaria conteudo; recusar nao perde nada e aparece na central.
        report_diagnostico_from_tx "$TX_DIR" erro "ledger duplo com sala so no destino; nada trocado" || true
        fatal "encontrei dois arquivos de conversas e o do runtime novo tem conversa que o atual não tem; não troquei nada."
      fi
    fi
    cp -p -- "$LEDGER_DESTINO" "$TX_DIR/ledger-destino-anterior.json" 2>/dev/null || true
  fi
fi

# 22/09: ULTIMA conferencia com a casa ainda INTACTA. O commit do catalogo e um rename
# de diretorio selado (0500), que so e permitido DENTRO do mesmo pai e do mesmo
# filesystem. Falhar aqui custa nada; falhar 4 linhas abaixo custa o catalogo do cliente,
# que foi exatamente o que aconteceu 5 vezes na casa do Muri em 21-22/09.
SKILLS_STAGE_DEV="$(stat -c %d -- "$SKILLS_STAGE" 2>/dev/null || true)"
SKILLS_PARENT_DEV="$(stat -c %d -- "$SKILLS_PARENT" 2>/dev/null || true)"
if [ -z "$SKILLS_STAGE_DEV" ] || [ -z "$SKILLS_PARENT_DEV" ]; then
  fatal "não consegui conferir onde o catálogo de skills vai ser ativado ($SKILLS_PARENT); nada foi trocado."
fi
if [ "$SKILLS_STAGE_DEV" != "$SKILLS_PARENT_DEV" ]; then
  fatal "o catálogo preparado ($SKILLS_STAGE) está num sistema de arquivos diferente do destino ($SKILLS_PARENT); a troca atômica é impossível e nada foi trocado."
fi
MUTATION_STARTED=1
if [ -e "$LEON_SKILLS_DIR" ]; then
  if [ ! -d "$LEON_SKILLS_DIR" ] || [ -L "$LEON_SKILLS_DIR" ]; then
    fatal "o catálogo anterior não é um diretório real; runtime preservado."
  fi
  printf '1\n' > "$TX_DIR/skills-had-original"
  mv -- "$LEON_SKILLS_DIR" "$SKILLS_BACKUP" \
    || fatal "não consegui reservar o backup do catálogo anterior."
fi
# Registra a intenção antes do segundo rename. Assim o rollback também cobre
# uma interrupção entre a retirada do catálogo antigo e a ativação do novo.
printf '1\n' > "$TX_DIR/skills-applied"
mv -- "$SKILLS_STAGE" "$LEON_SKILLS_DIR" \
  || fatal "não consegui ativar o catálogo Codex assinado em $LEON_SKILLS_DIR (a troca vem de $SKILLS_STAGE); o catálogo anterior foi devolvido pelo rollback."
[ "$(installed_skills_digest "$LEON_SKILLS_DIR")" = "$SKILLS_EXPECTED_DIGEST" ] \
  || fatal "o catálogo Codex mudou durante o commit."
if [ "${LEON_TEST_FAIL_AT:-}" = "after_skills" ]; then
  fatal "falha injetada depois da troca de skills."
fi
if [ -f "$TX_DIR/config.candidate" ]; then
  # Marca ANTES de trocar: a volta so restaura o config.toml que ESTA transacao trocou.
  printf '1\n' > "$TX_DIR/config-applied"
  if [ -f "$TX_DIR/config-ilegivel" ] && [ -f "$CONFIG_PATH" ]; then
    cp -p -- "$CONFIG_PATH" "${CONFIG_PATH}.ilegivel-$TX_ID"
  fi
  install -m 0600 "$TX_DIR/config.candidate" "${CONFIG_PATH}.leon-new-$TX_ID"
  mv -f -- "${CONFIG_PATH}.leon-new-$TX_ID" "$CONFIG_PATH"
fi
if [ "${LEON_TEST_FAIL_AT:-}" = "after_config" ]; then
  fatal "falha injetada depois do perfil candidato."
fi
if [ -f "$TX_DIR/leon-agente-candidate.service" ]; then
  install -m 0644 "$TX_DIR/leon-agente-candidate.service" "${UNIT_PATH}.leon-new-$TX_ID"
  mv -f -- "${UNIT_PATH}.leon-new-$TX_ID" "$UNIT_PATH"
  printf '1\n' > "$TX_DIR/unit-applied"
  service_read daemon-reload
fi
if [ "${LEON_TEST_FAIL_AT:-}" = "after_unit" ]; then
  fatal "falha injetada depois da unit candidata."
fi

mv -- "$INSTALL_DIR" "$BACKUP"
if [ "${LEON_TEST_FAIL_AT:-}" = "between_renames" ]; then
  fatal "falha injetada entre os renames."
fi
mv -- "$STAGE" "$INSTALL_DIR"

# ---- LEDGER DE SALAS: A COPIA (17/09) --------------------------------------
# POSICAO: DEPOIS do segundo rename e ANTES do 'committed'. A fonte e o
# $INSTALL_DIR/sessions.json JA renomeado, o arquivo mais FRESCO que existe: o
# bridge legado continua vivo e grava pelo caminho literal, que depois do rename
# aponta pra copia que veio do stage; BACKUP/sessions.json congelou no primeiro
# rename. Falha em qualquer linha daqui e fatal -> cleanup_main -> rollback_inline
# desfaz os dois renames; nenhum restart aconteceu e a casa volta byte a byte.
# NAO EXISTE DESFAZER: a origem nunca e tocada e viaja dentro do BACKUP, entao os
# tres caminhos de volta ja devolvem as salas. Desfazer no meio da restauracao foi
# o furo pego em 16/09 (casa restaurada SEM ledger e com log verde), e aqui so
# adicionaria escrita em tres caminhos de rollback sem proteger nada.
if [ "$LEDGER_MIGRA" = 1 ] && [ -e "$INSTALL_DIR/sessions.json" ]; then
  safe_copy_state_file "$INSTALL_DIR/sessions.json" "$LEDGER_DESTINO" sessions \
    || fatal "não consegui levar as conversas para onde o runtime novo lê; runtime preservado."
  # Bancada rodando como root: o arquivo nasce do euid do processo, e o bridge
  # (que sobe como o usuario da unit) recusaria com exit 78. Na casa de cliente o
  # atualizador ja roda como o dono e isto nao faz nada.
  if [ "$(id -u)" = 0 ]; then chown --reference="$INSTALL_DIR" -- "$LEDGER_DESTINO" 2>/dev/null || true; fi
  ledger_pre_voo "$LEDGER_DESTINO" \
    || fatal "as conversas copiadas não passaram na checagem que o runtime novo faz ao subir; runtime preservado."
  LEDGER_COPIOU=1
fi
# A conferencia vale pra TODA atualizacao, inclusive quando nada foi copiado
# (legado->legado, novo->novo). Assim ela se prova na bancada hoje, antes do
# primeiro bundle da familia nova existir.
# O marcador da migracao fica FORA do backup selado e SEM poder de desfazer coisa
# alguma: ele so autoriza SOBRESCREVER, numa tentativa seguinte, uma copia nossa que
# nunca foi promovida, e so em casa cujo bridge instalado e legado (onde o destino nao
# tem leitor). Esta amarrado ao sha do proprio arquivo, entao forja-lo so consegue
# sobrescrever um arquivo que ninguem le, e o anterior fica guardado no tx.
# As listas gravadas aqui sao PROVISORIAS quando ha migracao: o re-sync com o servico
# parado (subir_runtime_novo) as regrava a partir da copia final, e e essa que a prova
# de saude cobra. Sem migracao, esta e a unica e a definitiva.
ledger_registra_saude \
  || fatal "não consegui listar as conversas que o runtime novo precisa enxergar; runtime preservado."
if [ "$LEDGER_COPIOU" = 1 ]; then printf 'migrado\n' > "$TX_DIR/ledger-modo"
else printf 'conferido\n' > "$TX_DIR/ledger-modo"; fi
if [ "${LEON_TEST_FAIL_AT:-}" = "after_ledger" ]; then
  fatal "falha injetada depois da migração do ledger."
fi
# TRAVA ANTES DO 'committed': o cron do finalizador dispara a cada minuto e, sem
# isso, media a saude no meio do nosso proprio restart (pid velho x pid novo) e
# revertia release boa. Segura ate o servico assentar; COMMIT_LOCK != "" faz o
# cleanup_main soltar em qualquer saida, e a trava expira sozinha se formos mortos.
COMMIT_LOCK="$TX_DIR/.finalize-lock"
finalize_lock_acquire "$COMMIT_LOCK" || COMMIT_LOCK=""
printf 'committed\n' > "$TX_DIR/status"
printf '{"ts":%s,"backup":"%s","transaction":"%s"}\n' \
  "$(date +%s)" "$BACKUP" "$TX_ID" > "$INSTALL_DIR/.pos-update.json"
if [ "${LEON_TEST_FAIL_AT:-}" = "after_commit" ]; then
  fatal "falha injetada depois do commit do runtime."
fi

# ---- HABILIDADES COMPLETAS NA CASA (24/08, lei do dono) --------------------
# 2) BACKUP AGENDADO: casa auditada tinha ZERO backup (nunca foi agendado).
_cron_add(){ local linha="$1" chave="$2" cur; command -v crontab >/dev/null 2>&1 || return 0
  # a chave de dedup vem EXPLICITA (caminho do script): extrair por campo ja errou duas
  # vezes (ultimo token = "2>&1" casava sempre; campo 6 da linha de node = /usr/bin/node).
  [ -n "$chave" ] || return 0
  cur="$(crontab -l 2>/dev/null || true)"
  printf %s "$cur" | grep -qF "$chave " >/dev/null 2>&1 && return 0
  printf %s "$cur" | grep -qF "${chave}\"" >/dev/null 2>&1 && return 0
  printf %s "$cur" | grep -qE "$(printf %s "$chave" | sed 's/[].[^$*\\/]/\\&/g')( |$|>)" && return 0
  { [ -n "$cur" ] && printf '%s\n' "$cur"; printf '%s\n' "$linha"; } | crontab - 2>/dev/null || true; }
[ -f "$INSTALL_DIR/scripts/backup-diario.sh" ] && _cron_add "40 3 * * * $INSTALL_DIR/scripts/backup-diario.sh >/dev/null 2>&1" "$INSTALL_DIR/scripts/backup-diario.sh"
# 2b) AUTO-UPDATE (31/08, achado do raio-x da frota): casa instalada antes de
# agendar_rede existir (install.sh de 17/08) nunca ganhou os 4 cron do
# atualizador — fica CONGELADA pra sempre, porque so o proprio cron chama
# update-pago.sh de novo. Sem isto aqui, nao ha segunda chance: o updater que
# ligaria o cron so roda DENTRO do cron que falta. Autocura idempotente.
[ -f "$INSTALL_DIR/scripts/update-guard.sh" ]   && _cron_add "*/5 * * * * $INSTALL_DIR/scripts/update-guard.sh >/dev/null 2>&1"   "$INSTALL_DIR/scripts/update-guard.sh"
[ -f "$INSTALL_DIR/scripts/update-verdict.sh" ] && _cron_add "* * * * * $INSTALL_DIR/scripts/update-verdict.sh >/dev/null 2>&1" "$INSTALL_DIR/scripts/update-verdict.sh"
[ -f "$INSTALL_DIR/scripts/update-auto.sh" ]    && _cron_add "13 * * * * $INSTALL_DIR/scripts/update-auto.sh >/dev/null 2>&1"   "$INSTALL_DIR/scripts/update-auto.sh"
[ -f "$INSTALL_DIR/scripts/aviso-manha.sh" ]    && _cron_add "21 * * * * $INSTALL_DIR/scripts/aviso-manha.sh >/dev/null 2>&1"   "$INSTALL_DIR/scripts/aviso-manha.sh"
# 2c) CRON VIVO + MOTOR RESERVA (fix bug-de-nascenca 01/09): as entradas acima so
# valem com o daemon cron de pe. O updater roda com o usuario do LEON; o sudoers NOVO
# (instalador consertado) permite religar o cron e o motor reserva sem senha. Tento
# religar; se nao der (casa antiga sem o sudoers novo), deixo rastro pro /status e
# um aviso — nunca fatal, sempre best-effort. O motor reserva (leon-vigia.timer) e o
# que garante o /atualiza mesmo com o cron morto.
if ! pgrep -x cron >/dev/null 2>&1 && ! pgrep -x crond >/dev/null 2>&1; then
  sudo -n /bin/systemctl unmask cron >/dev/null 2>&1 || true
  sudo -n /bin/systemctl enable --now cron >/dev/null 2>&1 || true
  sleep 1
fi
sudo -n /bin/systemctl enable --now leon-vigia.timer >/dev/null 2>&1 || true
if ! pgrep -x cron >/dev/null 2>&1 && ! pgrep -x crond >/dev/null 2>&1 \
   && ! sudo -n /bin/systemctl is-active leon-vigia.timer >/dev/null 2>&1; then
  printf '{"visto_em":%s}\n' "$(date +%s)" > "$INSTALL_DIR/.cron-morto.json" 2>/dev/null || true
  notify_from_runtime "$INSTALL_DIR" "⚠️ Me atualizei, mas o agendador da tua VPS (o cron) esta parado e nao consegui religar sozinho — sem ele o backup diario e a rede de seguranca nao rodam. Me chama que eu te passo como destravar (e 1 comando)." "$THREAD_ARG" "$CHAT_ARG" || true
else
  rm -f "$INSTALL_DIR/.cron-morto.json" 2>/dev/null || true
fi
# 3z) AVISO DO MOTOR QUE NAO SUBIU (2.4.34): o update do bridge foi inteiro, mas o CLI ficou
# na versao antiga (sem rede, npm fora do ar, pacote parcial). Nada quebrou — so o Astra segue
# indisponivel, e o gate do /modelo em runtime ja explica isso se o dono pedir. Aviso UMA vez,
# sem susto, dizendo que a proxima tentativa e automatica. Se subiu, apago o rastro.
if [ "$CODEX_CLI_ABAIXO_DA_MINIMA" = "1" ] && [ "$CODEX_CLI_SUBIU" = "0" ]; then
  printf '{"visto_em":%s,"instalada":"%s","minima":"%s"}\n' \
    "$(date +%s)" "$LEON_CODEX_CLI_VERSION" "$LEON_CODEX_CLI_MINIMA" \
    > "$INSTALL_DIR/.motor-antigo.json" 2>/dev/null || true
  notify_from_runtime "$INSTALL_DIR" "✅ Atualizado! Tudo o que veio nesta versão já está no ar. Um detalhe só: o motor novo não subiu agora (deve ter sido rede). O Astra fica pra quando ele subir — eu tento de novo sozinho no próximo /atualiza, e você não precisa fazer nada." "$THREAD_ARG" "$CHAT_ARG" || true
else
  rm -f "$INSTALL_DIR/.motor-antigo.json" 2>/dev/null || true
fi
# 3z-claude) (23/09) O programa do Claude ficou abaixo do minimo: o update do bridge foi inteiro,
# o dono so precisa saber que o Opus pode ser recusado e que a casa segue no Sonnet sozinha.
# Nao promete o proximo /atualiza: numa casa ja na ultima release este script sai cedo ("Nada pra
# trocar") antes deste passo. Quem tenta de novo e o bridge (atualizaClaudeCliEmSegundoPlano, e o
# /atualiza do dono via claudeCliNoAtualiza, que roda antes deste script).
if [ "$CLAUDE_CLI_ABAIXO_DA_MINIMA" = "1" ] && [ "$CLAUDE_CLI_SUBIU" = "0" ] && [ "$LEON_ENGINE_CASA" = claude ]; then
  notify_from_runtime "$INSTALL_DIR" "✅ Atualizado! Um detalhe: o programa do Claude desta casa (${CLAUDE_CLI_VERSAO_ATUAL:-versão desconhecida}) é mais velho que o mínimo ($LEON_CLAUDE_CLI_MINIMA) e não consegui atualizar agora (deve ter sido rede). Se o Opus for recusado eu sigo no Sonnet sozinho e tento atualizar o programa em segundo plano; se não der, eu te aviso." "$THREAD_ARG" "$CHAT_ARG" || true
fi
# 3a) (27/09) o teste do modelo com copia do login saiu do /atualiza: o Codex podia renovar o token
# na copia e deixar o login do dono com um token ja gasto. Login vencido o proprio agente avisa na
# primeira resposta. A marca velha de login vencido sai.
rm -f "$INSTALL_DIR/.login-modelo-vencido.json" 2>/dev/null || true
# 3b) MODELO DE AUDIO NATIVO (25/08, caso Leticia): casa instalada antes do fix
# nao tem o modelo whisper — o 1o audio do cliente dispara download de 464MB DENTRO
# do bridge rodando (pico ~580MB de RAM = perfil de OOM em VPS pequena). Baixa AGORA,
# fora do bridge, com teto de tempo. Idempotente: cache pronto = sai na hora.
if [ -x "$LEON_DATA_DIR/whisper-venv/bin/python3" ]; then
  timeout 600 "$LEON_DATA_DIR/whisper-venv/bin/python3" - <<'PYMODEL' >/dev/null 2>&1 && say "   modelo de audio pronto (transcricao nativa)." || true
from faster_whisper import WhisperModel
WhisperModel("small", device="cpu", compute_type="int8")
PYMODEL
fi
# 3) BANCO POSTGRES (mesma estrutura do dono; espelho, nunca dependencia):
[ -x "$INSTALL_DIR/scripts/garante-banco.sh" ] && bash "$INSTALL_DIR/scripts/garante-banco.sh" 2>/dev/null | sed "s/^/  /" || true
[ -f "$INSTALL_DIR/workers/importa-estado-pro-banco.cjs" ] && _cron_add "50 3 * * * /usr/bin/node $INSTALL_DIR/workers/importa-estado-pro-banco.cjs >/dev/null 2>&1" "$INSTALL_DIR/workers/importa-estado-pro-banco.cjs"
# modulo pg pro importador (best-effort, uma vez)
# node resolve modulo subindo da pasta do SCRIPT (workers/): pg mora na RAIZ da casa (bancada pegou)
if [ ! -d "$INSTALL_DIR/node_modules/pg" ]; then
  ( cd "$INSTALL_DIR" && timeout 120 npm install -q --no-save pg >/dev/null 2>&1 ) || true
fi

# 4) REPORT DE VERSAO: NAO reportamos a versao nova aqui (fix report-falso). Reportar
# antes do restart+prova de saude fazia a central registrar sucesso mesmo quando o
# finalizador revertia — painel/monitor mentiam. Agora quem reporta e o finalizador,
# com a versao REAL que ficou viva (nova no succeeded, antiga no rollback). Ver
# report_version_from_tx() + os call sites em finalize_transaction().

say "commit atomico concluido; reiniciando $SERVICE"
# Marco do instante do restart. A prova de saude precisa saber que o heartbeat
# que ela le e do processo NOVO: sem marco, um .alive escrito pelo processo
# antigo passaria por prova. O tx e o canal certo porque o restart mata este
# script junto, e quem confere depois e o finalizador no cron.
if [ "$TEST_MODE" = "1" ]; then
  if ! subir_runtime_novo; then
    finalize_lock_release "$COMMIT_LOCK"; COMMIT_LOCK=""
    rollback_transaction "$TX_DIR" || true
    fatal "o serviço não voltou com o runtime novo; a versão anterior foi restaurada."
  fi
  MUTATION_STARTED=0
  # Solta a trava so DEPOIS do restart: o finalizador daqui roda inline, mas o cron
  # do minuto tambem pode estar batendo na porta.
  commit_lock_release_after_restart
  if finalize_transaction "$TX_DIR"; then
    exit 0
  fi
  exit 1
fi

# O restart normalmente encerra este processo junto com o cgroup antigo. O
# finalizador ja esta no cron e assume a prova de estabilidade ou o rollback.
RESTARTING=1
set +e
subir_runtime_novo
RESTART_STATUS=$?
set -e
if [ "$RESTART_STATUS" -ne 0 ]; then
  RESTARTING=0
  finalize_lock_release "$COMMIT_LOCK"; COMMIT_LOCK=""
  rollback_transaction "$TX_DIR" || true
  if [ "$RESTART_STATUS" -eq 2 ]; then
    fatal "não consegui levar as conversas para o runtime novo na hora de subir; a versão anterior foi restaurada."
  fi
  fatal "o serviço recusou o reinício; a versão anterior foi restaurada."
fi
# O restart deu certo. Se este processo sobreviveu a ele, espera o pid novo assentar
# e SO ENTAO libera o finalizador. Se o restart nos matou junto com o cgroup antigo,
# a trava fica orfa e o TTL a reivindica no tique seguinte — o cron nunca trava.
commit_lock_release_after_restart

# Algumas units encerram somente o processo principal e deixam o atualizador
# terminar. Nesse caso concluimos agora; o cron percebe o veredito e se remove.
RESTARTING=0
MUTATION_STARTED=0
finalize_transaction "$TX_DIR"
