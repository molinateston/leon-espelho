#!/usr/bin/env bash
# Projeto LEON · Socio IA 24x7 — instalador env-driven (v2)
# Uso oficial (tudo por env var, ZERO paste travando no Browser Terminal):
#
#   curl -fsSL https://licenca.leonardomolina.com.br/install-leon.sh \
#     | EMAIL='cliente@exemplo.com' \
#       NOME='LEON' \
#       GENDER='male' \
#       BOT_TOKEN='123456789:ABCdef...' \
#       bash
#
# Env vars OPCIONAIS pra teste E2E:
#   MOCK_MODE=1        → bancada SECA: pula rede/interativo E nao mexe na maquina
#                        (nao cria usuario, nao cria unit systemd, nao instala apt,
#                        NAO baixa nem VERIFICA o motor). O resumo final lista na
#                        cara o que rodou e o que ficou de fora. NAO valida a
#                        instalacao real — pra isso, rode sem MOCK numa VPS descartavel.
#   LEON_ENGINE=claude|codex → motor (a pagina de instalacao passa; sem terminal, default claude)
#   LEON_USER=<nome>   → override do usuario nao-root (default: leon)
#   LEON_DIR=<path>    → override do diretorio de instalacao (default: ~/socio-ia)
#   LEON_CENTRAL=<url> → override do central (default: https://licenca.leonardomolina.com.br)
#
# Este script tem 2 fases:
#   ROOT: instala pre-reqs, cria user nao-root, pivota pra ele preservando env vars.
#   USER: baixa motor, valida licenca, captura chat_id via Telegram getUpdates, sobe systemd.
set -euo pipefail

# ============================================================
# 0. VALIDA ENV VARS OBRIGATORIAS (falha ANTES de instalar nada)
# ============================================================
usage() {
  cat >&2 <<'USAGE'

ERRO: falta variavel de ambiente obrigatoria.

Uso oficial:

  curl -fsSL https://licenca.leonardomolina.com.br/install-leon.sh \
    | EMAIL='cliente@exemplo.com' \
      NOME='LEON' \
      GENDER='male' \
      BOT_TOKEN='123456789:ABCdef...' \
      bash

Gere o comando pronto em:
  https://licenca.leonardomolina.com.br/instalacao-v2

USAGE
  exit 1
}

: "${EMAIL:=}"
: "${NOME:=}"
: "${GENDER:=}"
: "${BOT_TOKEN:=}"
: "${MOCK_MODE:=}"
: "${LEON_ENGINE:=}"
: "${LEON_TOKEN_STDIN:=}"

# ============================================================
# 0.MOTOR — Claude ou Codex? (unificacao 2.0.5)
# O produto e UM: mesmo agente, mesma instalacao; muda so a LLM que ele usa.
# A pagina de instalacao passa LEON_ENGINE=claude|codex; se rodarem a mao sem a
# variavel e houver terminal, pergunta. Default claude (o motor historico).
# ============================================================
if [ -z "$LEON_ENGINE" ] && [ "$MOCK_MODE" != "1" ] && [ -t 0 ]; then
  echo ""
  echo "Qual motor de IA este LEON vai usar?"
  echo "  1) Claude (conta Anthropic)"
  echo "  2) Codex  (conta ChatGPT/OpenAI)"
  read -r -p "Escolha [1/2]: " _leon_motor < /dev/tty
  case "$_leon_motor" in
    2|codex|Codex|CODEX) LEON_ENGINE=codex ;;
    *) LEON_ENGINE=claude ;;
  esac
fi
[ -z "$LEON_ENGINE" ] && LEON_ENGINE=claude
if [ "$LEON_ENGINE" != "claude" ] && [ "$LEON_ENGINE" != "codex" ]; then
  echo "ERRO: LEON_ENGINE invalido (recebi '$LEON_ENGINE'); use 'claude' ou 'codex'." >&2
  exit 1
fi
echo ">> motor escolhido: $LEON_ENGINE"

# ============================================================
# 0.MOTOR-VARS · dirs, modelo, versoes pinadas e confianca de release
# So o Codex usa runtime dedicado (Node + Codex CLI pinados dentro de
# $LEON_DATA_DIR) e release assinada; as vars nascem aqui pra que TODA fase
# (root e user) enxergue os mesmos caminhos. Skills: o Codex le de
# $LEON_DATA_DIR/skills (o updater Codex so renomeia o stage dentro desse pai);
# o Claude le de ~/.claude/skills (casa nativa do Claude Code).
# ============================================================
LEON_DATA_DIR="${LEON_DATA_DIR:-$HOME/.leon}"
LEON_CODEX_HOME="${LEON_CODEX_HOME:-$LEON_DATA_DIR/codex}"
if [ "$LEON_ENGINE" = codex ]; then
  LEON_SKILLS_DIR="${LEON_SKILLS_DIR:-$LEON_DATA_DIR/skills}"
PERSONA_DIR_LOCAL="${PERSONA_DIR_LOCAL:-$LEON_DATA_DIR/persona}"
else
  LEON_SKILLS_DIR="${LEON_SKILLS_DIR:-$HOME/.claude/skills}"
fi
LEON_TMPDIR="${LEON_TMPDIR:-$LEON_DATA_DIR/tmp}"
LEON_WORK_AREA="${LEON_WORK_AREA:-$HOME/trabalho}"
LEON_STATE_DIR="${LEON_STATE_DIR:-$LEON_DATA_DIR/state}"
LEON_MISSIONS_DIR="${LEON_MISSIONS_DIR:-$LEON_STATE_DIR/missions}"
LEON_PROMISES_DIR="${LEON_PROMISES_DIR:-$LEON_STATE_DIR/promises}"
LEON_MISSION_OUTPUT_DIR="${LEON_MISSION_OUTPUT_DIR:-$LEON_DATA_DIR/mission-output}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-sol}"
LEON_RELEASE_TRUST_FINGERPRINT='eb70521f5e4dd9bb1cd11e6ceb0b2bddd65596558322908a2d04fd3dec5cbe08'

# Versoes homologadas do runtime dedicado do Codex: as mesmas que o
# release-manifest declara e que o update-pago-codex.sh valida.
: "${LEON_NODE_VERSION:=22.22.0}"
: "${LEON_CODEX_CLI_VERSION:=0.147.0}"
: "${LEON_NODE_ROOT:=}"
: "${LEON_CODEX_CLI_ROOT:=}"
: "${LEON_NODE_BIN_RESOLVED:=}"
: "${LEON_CODEX_BIN_RESOLVED:=}"
# Ganchos de bancada (fixtures offline dos testes). Producao nunca os define.
: "${LEON_TEST_NODE_ONLY:=}"
: "${LEON_TEST_NODE_ARCH:=}"
: "${LEON_TEST_NODE_TGZ:=}"
: "${LEON_TEST_NODE_SHA256:=}"
: "${LEON_TEST_CODEX_CLI_ONLY:=}"
: "${LEON_TEST_CODEX_ARCH:=}"
: "${LEON_TEST_CODEX_MAIN_TGZ:=}"
: "${LEON_TEST_CODEX_PLATFORM_TGZ:=}"
: "${LEON_TEST_CODEX_MAIN_SHA512:=}"
: "${LEON_TEST_CODEX_PLATFORM_SHA512:=}"
: "${LEON_TEST_UNIT_ONLY:=}"
: "${LEON_TEST_HANDOFF_ONLY:=}"
if ! printf %s "$LEON_CODEX_CLI_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([_-][A-Za-z0-9.-]+)?$'; then
  echo "ERRO: LEON_CODEX_CLI_VERSION invalida." >&2
  exit 1
fi

# PATH limpo do sistema. Tudo que e binario de sistema (npm, python3, o Node e o
# Codex pinados) roda com ele, nunca com o PATH herdado do shell de quem chamou:
# um root com nvm de outra IA enganou a checagem de Node e deixou o usuario do
# LEON sem node nenhum (instalacao ao vivo de 22/08).
SYS_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Chave publica Ed25519 que assina o release-manifest do motor Codex. Gravada em
# arquivo e conferida pelo fingerprint antes de qualquer verificacao de assinatura.
write_release_public_key() {
  local output="$1"
  cat > "$output" <<'PEM'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAzLQi1On9pdcj/g7Z8WxHxPeTijp0t3yhGnfoZfDzpXI=
-----END PUBLIC KEY-----
PEM
  [ "$(sha256sum "$output" | awk '{print $1}')" = "$LEON_RELEASE_TRUST_FINGERPRINT" ]
}

# Confere que um artefato baixado bate EXATAMENTE o hash e o tamanho declarados no
# manifesto assinado (defesa contra swap/truncamento). Le com O_NOFOLLOW e valida
# inode/nlink/size antes, durante e depois da leitura.
verify_signed_artifact() {
  local artifact="$1" expected_hash="$2" expected_bytes="$3" label="$4"
  python3 - "$artifact" "$expected_hash" "$expected_bytes" <<'PY' \
    || { echo "ERRO: $label difere do artefato assinado." >&2; return 1; }
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

# Chama a Bot API do Telegram por url-em-config (o token nunca vai pro argv, so pro
# stdin do curl). Aceita so os endpoints que o instalador usa: getMe, getUpdates e
# getUpdates?offset=N (com N numerico). Substitui os curl crus de getUpdates.
telegram_api_get_file() {
  local token="$1" endpoint="$2" output="$3" timeout="${4:-15}"
  printf %s "$token" | grep -qE '^[0-9]+:[A-Za-z0-9_-]{20,}$' || return 2
  case "$endpoint" in
    getMe|getUpdates) ;;
    getUpdates\?offset=*) printf %s "${endpoint#getUpdates?offset=}" | grep -qE '^[0-9]+$' || return 2 ;;
    *) return 2 ;;
  esac
  printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$token" "$endpoint" \
    | curl -fsS --max-time "$timeout" --config - --output "$output" 2>/dev/null
}

# ============================================================
# 0.RUNTIME-DEDICADO · Node e Codex CLI pinados (portado do install-codex.sh)
# So o ramo Codex usa. Node $LEON_NODE_VERSION vem do tarball oficial do
# nodejs.org com sha256 cravado; o Codex CLI $LEON_CODEX_CLI_VERSION vem dos
# dois tgz do registry npm com sha512 cravado. Tudo mora em prefixo privado
# (0700, dono = usuario do LEON) dentro de $LEON_DATA_DIR, nunca em pacote
# global da VPS: e o unico caminho que o bridge aceita em CODEX_BIN e que o
# update-pago-codex.sh valida (validate_dedicated_node/codex_cli sao os mesmos
# checks, aqui parametrizados pelo uid esperado).
# ============================================================
codex_cli_version() {
  local binary="${1:-}"
  [ -n "$binary" ] && [ -x "$binary" ] || return 1
  if [ -n "$LEON_NODE_BIN_RESOLVED" ] && [ -x "$LEON_NODE_BIN_RESOLVED" ]; then
    PATH="$(dirname "$LEON_NODE_BIN_RESOLVED"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
      "$binary" --version 2>/dev/null
  else
    "$binary" --version 2>/dev/null
  fi \
    | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+([_-][A-Za-z0-9.-]+)?$/) { print $i; exit } }'
}

node_runtime_version() {
  local binary="${1:-}"
  [ -n "$binary" ] && [ -x "$binary" ] || return 1
  "$binary" --version 2>/dev/null \
    | awk 'NR == 1 && $0 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ { sub(/^v/, ""); print; exit }'
}

repair_managed_prefix_dirs() {
  local target_home="$1" target_root="$2" target_user="$3" target_uid target_gid
  [ "$(id -u)" -eq 0 ] || return 0
  [ "$target_user" != root ] || return 0
  target_uid="$(id -u "$target_user")" || return 1
  target_gid="$(id -g "$target_user")" || return 1
  python3 - "$target_home" "$target_root" "$target_uid" "$target_gid" <<'PY'
import os,stat,sys
home,target=os.path.abspath(sys.argv[1]),os.path.abspath(sys.argv[2])
uid,gid=map(int,sys.argv[3:])
try:
    hi=os.lstat(home)
    if not stat.S_ISDIR(hi.st_mode) or stat.S_ISLNK(hi.st_mode) or os.path.realpath(home)!=home or hi.st_uid!=uid:
        raise ValueError("home do usuário não é um diretório real com o dono esperado")
    rel=os.path.relpath(target,home)
    if rel.startswith("../") or rel in (".",".."):
        raise ValueError("prefixo gerenciado escapa da home")
    cursor=home
    for part in rel.split(os.sep):
        cursor=os.path.join(cursor,part)
        try: info=os.lstat(cursor)
        except FileNotFoundError: break
        if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
            raise ValueError(f"{cursor} não é diretório real")
        if info.st_uid not in (0,uid):
            raise ValueError(f"{cursor} pertence a outro usuário")
        # Uma tentativa root antiga pode ter criado somente o contêiner com
        # dono root. Corrigimos o contêiner, nunca conteúdo/release existente.
        if info.st_uid==0:
            os.chown(cursor,uid,gid,follow_symlinks=False)
        os.chmod(cursor,0o700,follow_symlinks=False)
except Exception as exc:
    print(f"ERRO: prefixo gerenciado não pôde ser reparado: {exc}",file=sys.stderr)
    raise SystemExit(1)
PY
}

validate_dedicated_node() {
  local binary="$1" data_dir="$2" version="$3" expected_uid="${4:-$(id -u)}"
  python3 - "$binary" "$data_dir" "$version" "$expected_uid" <<'PY'
import os,stat,sys
binary,data_dir,version=sys.argv[1:4]; expected_uid=int(sys.argv[4])
data_dir=os.path.abspath(data_dir); release=os.path.join(data_dir,"node","releases",version)
expected=os.path.join(release,"bin","node")
if os.path.abspath(binary)!=expected or not os.path.isdir(data_dir) or os.path.islink(data_dir): raise SystemExit(1)
cursor=data_dir
for part in ("node","releases",version,"bin"):
    cursor=os.path.join(cursor,part); info=os.lstat(cursor)
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode) or info.st_uid!=expected_uid or stat.S_IMODE(info.st_mode)&0o022: raise SystemExit(1)
leaf=os.lstat(expected)
if not stat.S_ISREG(leaf.st_mode) or leaf.st_nlink!=1 or leaf.st_uid!=expected_uid: raise SystemExit(1)
if stat.S_IMODE(leaf.st_mode)&0o077 or not os.access(expected,os.X_OK): raise SystemExit(1)
if os.path.commonpath([release,os.path.realpath(expected)])!=release: raise SystemExit(1)
PY
}

extract_pinned_node_binary() {
  local archive="$1" expected_sha="$2" member="$3" output="$4"
  python3 - "$archive" "$expected_sha" "$member" "$output" <<'PY'
import hashlib,os,posixpath,stat,sys,tarfile
archive,expected,selected,output=sys.argv[1:]
try:
    seen=os.lstat(archive)
    if not stat.S_ISREG(seen.st_mode) or seen.st_nlink!=1 or seen.st_size>100_663_296: raise ValueError()
    fd=os.open(archive,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0))
    try:
        before=os.fstat(fd); digest=hashlib.sha256()
        while True:
            block=os.read(fd,1024*1024)
            if not block: break
            digest.update(block)
        after=os.fstat(fd)
        if (seen.st_dev,seen.st_ino)!=(before.st_dev,before.st_ino): raise ValueError()
        if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or before.st_size>100_663_296: raise ValueError()
        if (before.st_dev,before.st_ino,before.st_size)!=(after.st_dev,after.st_ino,after.st_size) or after.st_nlink!=1: raise ValueError()
        if digest.hexdigest()!=expected: raise ValueError()
        os.lseek(fd,0,os.SEEK_SET)
        with os.fdopen(os.dup(fd),"rb") as stream, tarfile.open(fileobj=stream,mode="r:gz") as tf:
            members=tf.getmembers()
            if not members or len(members)>10_000: raise ValueError()
            names=set(); target=None; root=selected.split("/",1)[0]
            for item in members:
                name=posixpath.normpath(item.name)
                if item.name.startswith("/") or "\\" in item.name or name in ("",".","..") or name.startswith("../"): raise ValueError()
                if name in names or not (name==root or name.startswith(root+"/")): raise ValueError()
                names.add(name)
                if item.isdev() or item.isfifo(): raise ValueError()
                if name==selected:
                    if target is not None or not item.isfile() or item.size<1 or item.size>209_715_200: raise ValueError()
                    target=item
            if target is None: raise ValueError()
            source=tf.extractfile(target)
            if source is None: raise ValueError()
            out=os.open(output,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,"O_NOFOLLOW",0),0o700)
            try:
                remaining=target.size
                while remaining:
                    block=source.read(min(1024*1024,remaining))
                    if not block: raise ValueError()
                    os.write(out,block); remaining-=len(block)
                if source.read(1): raise ValueError()
                os.fsync(out)
            finally: os.close(out)
    finally: os.close(fd)
except Exception:
    try: os.unlink(output)
    except FileNotFoundError: pass
    raise SystemExit(1)
PY
}

ensure_node_runtime() {
  local target_user="${1:-$(id -un)}" target_home="${2:-$HOME}"
  local node_root release_dir stage_dir node_bin target_uid arch archive member expected_sha installed archive_name
  node_root="${LEON_NODE_ROOT:-$LEON_DATA_DIR/node}"
  release_dir="$node_root/releases/$LEON_NODE_VERSION"
  node_bin="$release_dir/bin/node"
  case "$node_root" in "$target_home"/*) ;; *)
    echo "ERRO: o prefixo dedicado do Node precisa ficar dentro da home do usuário LEON." >&2; return 1 ;;
  esac
  target_uid="$(id -u "$target_user")" || return 1
  repair_managed_prefix_dirs "$target_home" "$node_root" "$target_user" || return 1
  python3 - "$target_home" "$node_root" "$target_uid" <<'PY' || {
import os,stat,sys
home,target,uid=os.path.abspath(sys.argv[1]),os.path.abspath(sys.argv[2]),int(sys.argv[3])
hi=os.lstat(home)
if not stat.S_ISDIR(hi.st_mode) or stat.S_ISLNK(hi.st_mode) or os.path.realpath(home)!=home or hi.st_uid!=uid: raise SystemExit(1)
cursor=home
for part in os.path.relpath(target,home).split(os.sep):
    cursor=os.path.join(cursor,part)
    try: info=os.lstat(cursor)
    except FileNotFoundError: break
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode) or info.st_uid!=uid or stat.S_IMODE(info.st_mode)&0o022: raise SystemExit(1)
PY
    echo "ERRO: o prefixo dedicado do Node passa por diretório inseguro." >&2; return 1
  }
  installed="$(node_runtime_version "$node_bin" || true)"
  if [ "$installed" = "$LEON_NODE_VERSION" ]; then
    validate_dedicated_node "$node_bin" "$(dirname "$node_root")" "$LEON_NODE_VERSION" "$target_uid" \
      || { echo "ERRO: o release dedicado do Node existe, mas é inseguro." >&2; return 1; }
    LEON_NODE_BIN_RESOLVED="$node_bin"; export LEON_NODE_BIN_RESOLVED
    echo "   node $installed (prefixo dedicado validado)"
    return 0
  fi
  [ ! -e "$release_dir" ] || { echo "ERRO: o release dedicado $release_dir está inconsistente." >&2; return 1; }
  if [ "$(id -u)" -eq 0 ] && [ "$target_user" != root ]; then
    install -d -m 0700 -o "$target_user" -g "$target_user" "$node_root" "$node_root/releases"
  else
    mkdir -p -- "$node_root/releases"; chmod 0700 "$node_root" "$node_root/releases"
  fi
  arch="${LEON_TEST_NODE_ARCH:-$(uname -m)}"
  case "$arch" in
    x86_64|amd64)
      archive_name="node-v${LEON_NODE_VERSION}-linux-x64.tar.gz"
      member="node-v${LEON_NODE_VERSION}-linux-x64/bin/node"
      expected_sha=c33c39ed9c80deddde77c960d00119918b9e352426fd604ba41638d6526a4744 ;;
    aarch64|arm64)
      archive_name="node-v${LEON_NODE_VERSION}-linux-arm64.tar.gz"
      member="node-v${LEON_NODE_VERSION}-linux-arm64/bin/node"
      expected_sha=25ba95dfb96871fa2ef977f11f95ea90818c8fa15c0f2110771db08d4ba423be ;;
    *) echo "ERRO: arquitetura sem runtime Node homologado: $arch." >&2; return 1 ;;
  esac
  [ -z "$LEON_TEST_NODE_SHA256" ] || expected_sha="$LEON_TEST_NODE_SHA256"
  stage_dir="$node_root/.stage-$LEON_NODE_VERSION-$$"
  [ ! -e "$stage_dir" ] || { echo "ERRO: colisão no stage do Node dedicado." >&2; return 1; }
  mkdir -m 0700 "$stage_dir" "$stage_dir/bin"
  archive="$(mktemp)"
  trap 'rm -f -- "$archive"; rm -rf -- "$stage_dir"' RETURN
  if [ -n "$LEON_TEST_NODE_TGZ" ]; then
    cp -- "$LEON_TEST_NODE_TGZ" "$archive"
  else
    curl --proto '=https' --tlsv1.2 -fsSL --max-filesize 100663296 --retry 3 \
      "https://nodejs.org/dist/v${LEON_NODE_VERSION}/$archive_name" -o "$archive" || return 1
  fi
  extract_pinned_node_binary "$archive" "$expected_sha" "$member" "$stage_dir/bin/node" \
    || { echo "ERRO: runtime Node diverge do artefato oficial homologado." >&2; return 1; }
  if [ "$(id -u)" -eq 0 ] && [ "$target_user" != root ]; then chown -R "$target_user:$target_user" "$stage_dir"; fi
  chmod -R go-rwx "$stage_dir"
  [ "$(node_runtime_version "$stage_dir/bin/node" || true)" = "$LEON_NODE_VERSION" ] \
    || { echo "ERRO: runtime Node preparado não executa a versão homologada." >&2; return 1; }
  mv -- "$stage_dir" "$release_dir"
  validate_dedicated_node "$node_bin" "$(dirname "$node_root")" "$LEON_NODE_VERSION" "$target_uid" \
    && [ "$(node_runtime_version "$node_bin" || true)" = "$LEON_NODE_VERSION" ] || {
      rm -rf -- "$release_dir"; echo "ERRO: runtime Node falhou depois do commit do release." >&2; return 1;
    }
  LEON_NODE_BIN_RESOLVED="$node_bin"; export LEON_NODE_BIN_RESOLVED
  rm -f -- "$archive"; trap - RETURN
  echo "   node $LEON_NODE_VERSION (prefixo dedicado validado)"
}

ensure_codex_cli() {
  local target_user="${1:-$(id -un)}" target_home="${2:-$HOME}"
  local cli_root release_dir stage_dir cli_bin installed resolved target_uid arch platform_alias target_triple
  local main_url platform_url main_sha512 platform_sha512 main_tgz platform_tgz main_extract platform_extract
  cli_root="${LEON_CODEX_CLI_ROOT:-$LEON_DATA_DIR/codex-cli}"
  release_dir="$cli_root/releases/$LEON_CODEX_CLI_VERSION"
  cli_bin="$release_dir/bin/codex"
  case "$cli_root" in "$target_home"/*) ;; *)
    echo "ERRO: o prefixo dedicado do Codex precisa ficar dentro da home do usuário LEON." >&2
    return 1 ;;
  esac
  target_uid="$(id -u "$target_user")" || return 1
  repair_managed_prefix_dirs "$target_home" "$cli_root" "$target_user" || return 1
  python3 - "$target_home" "$cli_root" "$target_uid" <<'PY' || {
import os,stat,sys
home,target,uid=os.path.abspath(sys.argv[1]),os.path.abspath(sys.argv[2]),int(sys.argv[3])
hi=os.lstat(home)
if not stat.S_ISDIR(hi.st_mode) or stat.S_ISLNK(hi.st_mode) or os.path.realpath(home)!=home or hi.st_uid!=uid: raise SystemExit(1)
cursor=home
for part in os.path.relpath(target,home).split(os.sep):
 cursor=os.path.join(cursor,part)
 try: info=os.lstat(cursor)
 except FileNotFoundError: break
 if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode) or info.st_uid!=uid or stat.S_IMODE(info.st_mode)&0o022: raise SystemExit(1)
PY
    echo "ERRO: o prefixo dedicado do Codex passa por diretório inseguro." >&2
    return 1
  }
  installed="$(codex_cli_version "$cli_bin" || true)"
  if [ "$installed" = "$LEON_CODEX_CLI_VERSION" ]; then
    validate_dedicated_codex_cli "$cli_bin" "$(dirname "$cli_root")" "$LEON_CODEX_CLI_VERSION" "$target_uid" \
      || { echo "ERRO: o release dedicado do Codex existe, mas é inseguro." >&2; return 1; }
    LEON_CODEX_BIN_RESOLVED="$cli_bin"
    export LEON_CODEX_BIN_RESOLVED
    echo "   codex-cli $installed (prefixo dedicado validado)"
    return 0
  fi
  if [ -e "$release_dir" ]; then
    echo "ERRO: o release dedicado $release_dir existe, mas não contém o Codex CLI esperado." >&2
    return 1
  fi
  if [ "$(id -u)" -eq 0 ] && [ "$target_user" != root ]; then
    install -d -m 0700 -o "$target_user" -g "$target_user" "$cli_root" "$cli_root/releases"
  else
    mkdir -p -- "$cli_root/releases"
    chmod 0700 "$cli_root" "$cli_root/releases"
  fi
  stage_dir="$cli_root/.stage-$LEON_CODEX_CLI_VERSION-$$"
  [ ! -e "$stage_dir" ] || { echo "ERRO: colisão no stage do Codex CLI dedicado." >&2; return 1; }
  arch="${LEON_TEST_CODEX_ARCH:-$(uname -m)}"
  case "$arch" in
    x86_64|amd64)
      platform_alias=codex-linux-x64; target_triple=x86_64-unknown-linux-musl
      platform_sha512=d16f4c0713e9596d1c4a436aad30cdda347baf3cd3ee834c850639e38ea54f62f0e5ccf9ca10d3724e156bdae3910126f87945ccffdd98431265b5df26c20d9b ;;
    aarch64|arm64)
      platform_alias=codex-linux-arm64; target_triple=aarch64-unknown-linux-musl
      platform_sha512=48b0b5257c364d87ebfdcdc786b26e6f2c8b7a5abbbd338b5959a24e1140fb3d3e5a0cc23e66ac789fe4cc30f71a07bf4ceedf0a79e3ed470f982d1dd9cf1702 ;;
    *) echo "ERRO: arquitetura sem pacote Codex homologado: $arch." >&2; return 1 ;;
  esac
  main_sha512=1102c45de7001b6a6dc48ed4a41328d9347f81ae79f7afdcfceb1817fd0ba140e1e4900d67b2281aa97304459bb84550efa25e3c86ed4d6fe2842929d5aed9df
  main_url="https://registry.npmjs.org/@openai/codex/-/codex-${LEON_CODEX_CLI_VERSION}.tgz"
  platform_url="https://registry.npmjs.org/@openai/codex/-/codex-${LEON_CODEX_CLI_VERSION}-linux-${platform_alias##*-}.tgz"
  if [ "$LEON_TEST_CODEX_CLI_ONLY" = 1 ] && [ -n "$LEON_TEST_CODEX_MAIN_SHA512" ]; then
    main_sha512="$LEON_TEST_CODEX_MAIN_SHA512"
    platform_sha512="$LEON_TEST_CODEX_PLATFORM_SHA512"
  fi
  main_tgz="$(mktemp)"; platform_tgz="$(mktemp)"
  main_extract="$(mktemp -d)"; platform_extract="$(mktemp -d)"
  trap 'rm -f -- "$main_tgz" "$platform_tgz"; rm -rf -- "$main_extract" "$platform_extract" "$stage_dir"' RETURN
  echo ">> preparando Codex CLI $LEON_CODEX_CLI_VERSION em prefixo dedicado..."
  if [ "$LEON_TEST_CODEX_CLI_ONLY" = 1 ] && [ -n "$LEON_TEST_CODEX_MAIN_TGZ" ]; then
    cp -- "$LEON_TEST_CODEX_MAIN_TGZ" "$main_tgz"
    cp -- "$LEON_TEST_CODEX_PLATFORM_TGZ" "$platform_tgz"
  else
    curl --proto '=https' --tlsv1.2 -fsSL --max-filesize 1048576 --retry 3 \
      "$main_url" -o "$main_tgz" || return 1
    curl --proto '=https' --tlsv1.2 -fsSL --max-filesize 167772160 --retry 3 \
      "$platform_url" -o "$platform_tgz" || return 1
  fi
  verify_codex_package_archive "$main_tgz" "$main_sha512" main "$LEON_CODEX_CLI_VERSION" "$target_triple" \
    || { echo "ERRO: pacote principal do Codex diverge do hash homologado." >&2; return 1; }
  verify_codex_package_archive "$platform_tgz" "$platform_sha512" platform "$LEON_CODEX_CLI_VERSION" "$target_triple" \
    || { echo "ERRO: pacote nativo do Codex diverge do hash homologado." >&2; return 1; }
  tar --no-same-owner --no-same-permissions -xzf "$main_tgz" -C "$main_extract"
  tar --no-same-owner --no-same-permissions -xzf "$platform_tgz" -C "$platform_extract"
  mkdir -p "$stage_dir/lib/node_modules/@openai" "$stage_dir/bin"
  mv -- "$main_extract/package" "$stage_dir/lib/node_modules/@openai/codex"
  mv -- "$platform_extract/package" "$stage_dir/lib/node_modules/@openai/$platform_alias"
  ln -s ../lib/node_modules/@openai/codex/bin/codex.js "$stage_dir/bin/codex"
  chmod 0700 "$stage_dir/lib/node_modules/@openai/codex/bin/codex.js"
  if [ "$(id -u)" -eq 0 ] && [ "$target_user" != root ]; then chown -R "$target_user:$target_user" "$stage_dir"; fi
  cli_bin="$stage_dir/bin/codex"
  resolved="$(readlink -f -- "$cli_bin" 2>/dev/null || true)"
  case "$resolved" in "$stage_dir"/*) ;; *)
    rm -rf -- "$stage_dir"
    echo "ERRO: o executável Codex preparado escapa do prefixo dedicado." >&2
    return 1 ;;
  esac
  installed="$(codex_cli_version "$cli_bin" || true)"
  if [ "$installed" != "$LEON_CODEX_CLI_VERSION" ]; then
    rm -rf -- "$stage_dir"
    echo "ERRO: Codex CLI ficou em '${installed:-ausente}', esperado $LEON_CODEX_CLI_VERSION." >&2
    return 1
  fi
  chmod -R go-rwx "$stage_dir"
  mv -- "$stage_dir" "$release_dir"
  cli_bin="$release_dir/bin/codex"
  [ "$(codex_cli_version "$cli_bin" || true)" = "$LEON_CODEX_CLI_VERSION" ] || {
    rm -rf -- "$release_dir"
    echo "ERRO: Codex CLI dedicado falhou depois do commit do release." >&2
    return 1
  }
  validate_dedicated_codex_cli "$cli_bin" "$(dirname "$cli_root")" "$LEON_CODEX_CLI_VERSION" "$target_uid" || {
    rm -rf -- "$release_dir"
    echo "ERRO: o release dedicado do Codex falhou na validação de propriedade." >&2
    return 1
  }
  LEON_CODEX_BIN_RESOLVED="$cli_bin"
  export LEON_CODEX_BIN_RESOLVED
  rm -f -- "$main_tgz" "$platform_tgz"; rm -rf -- "$main_extract" "$platform_extract"
  trap - RETURN
  echo "   codex-cli $installed (prefixo dedicado validado)"
}

verify_codex_package_archive() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import hashlib,json,posixpath,re,stat,sys,tarfile,os
archive,expected,kind,version,triple=sys.argv[1:]
try:
 info=os.lstat(archive)
 if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1: raise ValueError()
 raw=open(archive,"rb").read()
 if hashlib.sha512(raw).hexdigest()!=expected: raise ValueError()
 tf=tarfile.open(archive,"r:gz"); members=tf.getmembers()
 if not members or len(members)>64: raise ValueError()
 total=0
 for m in members:
  name=posixpath.normpath(m.name)
  if m.name.startswith("/") or name in ("",".","..") or name.startswith("../"): raise ValueError()
  if name=="package":
   if not m.isdir(): raise ValueError()
   continue
  if not name.startswith("package/"): raise ValueError()
  if not (m.isdir() or m.isfile()) or m.islnk() or m.issym() or m.isdev() or m.isfifo(): raise ValueError()
  if m.isfile(): total+=m.size
 if total>(1_048_576 if kind=="main" else 400_000_000): raise ValueError()
 pj=tf.extractfile("package/package.json")
 if pj is None: raise ValueError()
 data=json.load(pj)
 if data.get("name")!="@openai/codex": raise ValueError()
 expected_version=version if kind=="main" else f"{version}-linux-{'x64' if triple.startswith('x86_64') else 'arm64'}"
 if data.get("version")!=expected_version: raise ValueError()
 if kind=="main":
  if data.get("bin")!={"codex":"bin/codex.js"}: raise ValueError()
  required={"package/package.json","package/bin/codex.js","package/README.md"}
  if {m.name.rstrip("/") for m in members if m.isfile()}!=required: raise ValueError()
 else:
  required=f"package/vendor/{triple}/bin/codex"
  if not any(m.name==required and m.isfile() for m in members): raise ValueError()
except Exception: raise SystemExit(1)
PY
}

validate_dedicated_codex_cli() {
  local binary="$1" data_dir="$2" version="$3" expected_uid="${4:-$(id -u)}"
  python3 - "$binary" "$data_dir" "$version" "$expected_uid" <<'PY'
import os,stat,sys
binary,data_dir,version=sys.argv[1:4]; expected_uid=int(sys.argv[4])
data_dir=os.path.abspath(data_dir)
release=os.path.join(data_dir,"codex-cli","releases",version)
expected=os.path.join(release,"bin","codex")
if os.path.abspath(binary)!=expected or not os.path.isdir(data_dir) or os.path.islink(data_dir): raise SystemExit(1)
cursor=data_dir
for part in ("codex-cli","releases",version,"bin"):
    cursor=os.path.join(cursor,part)
    info=os.lstat(cursor)
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode) or info.st_uid!=expected_uid or stat.S_IMODE(info.st_mode)&0o022: raise SystemExit(1)
leaf=os.lstat(expected)
if leaf.st_uid!=expected_uid or leaf.st_nlink!=1 or not (stat.S_ISREG(leaf.st_mode) or stat.S_ISLNK(leaf.st_mode)): raise SystemExit(1)
resolved=os.path.realpath(expected)
if os.path.commonpath([release,resolved])!=release: raise SystemExit(1)
target=os.stat(expected)
if not stat.S_ISREG(target.st_mode) or target.st_uid!=expected_uid or stat.S_IMODE(target.st_mode)&0o022 or not os.access(expected,os.X_OK): raise SystemExit(1)
PY
}

# Roda o Codex PINADO em env limpo: so HOME/USER/PATH/locale/TERM + CODEX_HOME
# dedicado, com o Node dedicado na frente do PATH (o bin/codex e um .js com
# shebang "env node"). Nada do shell de quem chamou vaza pro motor, e a
# credencial nasce em $LEON_CODEX_HOME. Login, prova do modelo e status usam isto.
# Manifesto de integridade do runtime (verbatim do install-codex.sh / updater):
# o bridge confere no boot cada arquivo contra este sha256. Sem regravar aqui,
# uma reexecucao do instalador numa casa ja atualizada deixaria o manifesto
# velho do updater e o bridge acusaria "runtime alterado" sem motivo.
write_runtime_files_manifest() {
  # `local a="$1" b="$a/x"` NAO enxerga o $a da mesma linha: o b sai como "/x" e o
  # manifesto ia parar na raiz do disco. Duas linhas, de proposito.
  local stage="$1"
  local destination="$stage/.leon-runtime-files.sha256"
  local rel
  : > "$destination"
  for rel in bridge.cjs capabilities.json \
    appserver/adapter.cjs appserver/index.cjs \
    lib-motores/codex-appserver.cjs lib/onboarding.js lib/meta-connect.js lib/license.js \
    workers/piper.js workers/edge-tts.js workers/hostinger-health.cjs; do
    [ -f "$stage/$rel" ] && [ ! -L "$stage/$rel" ] || continue
    printf '%s  %s\n' "$(sha256sum "$stage/$rel" | awk '{print $1}')" "$rel" >> "$destination"
  done
  chmod 0600 "$destination"
}

# Uso: codex_env_limpo [--timeout SEG] <args do codex>. O timeout entra DENTRO
# do env -i (timeout nao executa funcao de shell) e por caminho absoluto.
codex_env_limpo() {
  local _u _node_dir _timeout=()
  if [ "${1:-}" = --timeout ]; then _timeout=(/usr/bin/timeout "$2"); shift 2; fi
  _u="$(id -un)"
  _node_dir="$(dirname "$LEON_NODE_BIN_RESOLVED")"
  env -i HOME="$HOME" USER="$_u" LOGNAME="$_u" \
    PATH="$_node_dir:$SYS_PATH" CODEX_HOME="$LEON_CODEX_HOME" \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM="${TERM:-dumb}" \
    ${_timeout[@]+"${_timeout[@]}"} "$LEON_CODEX_BIN_RESOLVED" "$@"
}

# Login do Codex por codigo de dispositivo, no binario pinado (nunca o do PATH).
# A URL/codigo aparece no proprio terminal (SEM </dev/tty: o --device-auth nao
# le do stdin, mostra o codigo e espera a autorizacao pela web), e confirma com
# 'login status' que a sessao ficou valida antes de seguir.
codex_login_unificado() {
  [ -x "$LEON_CODEX_BIN_RESOLVED" ] && [ -x "$LEON_NODE_BIN_RESOLVED" ] \
    || { echo "ERRO: runtime dedicado do Codex ausente na hora do login." >&2; return 1; }
  if codex_env_limpo login status >/dev/null 2>&1; then
    echo ">> Codex ja esta autenticado nesta VPS."
    return 0
  fi
  echo ""
  echo "========================================"
  echo "  LOGIN DO CODEX"
  echo "========================================"
  echo "O terminal vai mostrar uma URL e um codigo de uso unico."
  echo "Abra a URL no navegador, entre na sua conta do ChatGPT e informe o codigo."
  echo "Nao feche este terminal: a instalacao continua sozinha depois do login."
  echo ""
  if ! codex_env_limpo login --device-auth; then
    echo "ERRO: o login Codex nao foi concluido." >&2
    return 1
  fi
  if ! codex_env_limpo login status >/dev/null 2>&1; then
    echo "ERRO: o Codex encerrou o login sem uma sessao valida." >&2
    return 1
  fi
  echo ">> Login Codex confirmado. Continuando a mesma instalacao."
}

# Prova do modelo depois do login: a conta ChatGPT do cliente pode nao ter o
# modelo default (o "sol"). Pede um "OK" ao modelo escolhido; se a API devolve
# 400 "not supported", desce a escada gpt-5.6 > gpt-5.5 > gpt-5.3-codex e grava
# em CODEX_MODEL o primeiro que respondeu (vai pro .env e pro config.toml).
# Nenhum respondeu = ERRO com suporte; o servico nunca sobe mudo.
provar_modelo_codex() {
  local candidatos="$CODEX_MODEL gpt-5.6 gpt-5.5 gpt-5.3-codex" m vistos=" " saida ultima rc
  mkdir -p "$LEON_WORK_AREA"
  echo ">> provando acesso ao modelo (a conta precisa responder um OK)..."
  for m in $candidatos; do
    case "$vistos" in *" $m "*) continue ;; esac
    vistos="$vistos$m "
    saida=$(mktemp); ultima="$saida.ultima"
    rc=0
    codex_env_limpo --timeout 90 exec --skip-git-repo-check --ephemeral -C "$LEON_WORK_AREA" \
      -m "$m" -o "$ultima" "responda apenas OK" >"$saida" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ] && [ -s "$ultima" ]; then
      rm -f -- "$saida" "$ultima"
      CODEX_MODEL="$m"
      echo "   modelo $m respondeu."
      return 0
    fi
    if grep -qiE 'not supported|"status":[[:space:]]*400' "$saida"; then
      echo "   modelo $m nao esta disponivel nesta conta; tentando o proximo."
      rm -f -- "$saida" "$ultima"
      continue
    fi
    echo "ERRO: o modelo $m nao respondeu (codigo $rc)." >&2
    tail -n 5 "$saida" >&2 || true
    rm -f -- "$saida" "$ultima"
    echo "abortando: sem modelo respondendo o LEON subiria mudo. suporte: https://wa.me/5511961562217" >&2
    return 1
  done
  echo "ERRO: nenhum modelo (${candidatos}) esta disponivel nesta conta ChatGPT." >&2
  echo "abortando. suporte: https://wa.me/5511961562217" >&2
  return 1
}

# Unit systemd do servico. Ramo Codex = template endurecido do install-codex.sh,
# linha por linha (e o perfil que o update-pago-codex.sh valida em
# validate_service_unit), rodando no Node dedicado. NoNewPrivileges fica: com
# ele setuid/setgid morrem dentro da unit, por isso o /atualiza pedido pelo bot
# nao roda la dentro, vira um pedido em .update-request.json que o vigia do
# cron (fora da unit) executa (ver injetar_handoff_update_verdict).
# Ramo Claude = unit simples historica, no Node do sistema.
write_service_unit() {
  local output="$1" user="$2" install_dir="$3" node_bin="$4" engine="$5"
  if [ "$engine" = codex ]; then
    cat > "$output" <<EOF
[Unit]
Description=Projeto LEON · Socio IA 24x7
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=120
StartLimitBurst=8

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=$install_dir
ExecStartPre=$node_bin --check $install_dir/bridge.cjs
ExecStart=$node_bin $install_dir/bridge.cjs
Environment="PATH=$(dirname "$node_bin"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Restart=on-failure
RestartSec=5
TimeoutStopSec=100
KillMode=control-group
UMask=0077
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictRealtime=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
PrivateDevices=true
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallArchitectures=native
TasksMax=512
MemoryHigh=80%
MemoryMax=90%

[Install]
WantedBy=multi-user.target
EOF
  else
    cat > "$output" <<EOF
[Unit]
Description=Projeto LEON · Socio IA 24x7
After=network.target

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=$install_dir
ExecStart=$node_bin $install_dir/bridge.cjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  fi
  chmod 0644 "$output"
}

# HANDOFF do /atualiza (A11). O bridge roda numa unit com NoNewPrivileges, onde
# setuid/setgid nao valem: um update-pago.sh disparado la de dentro nao arma o
# cron nem reinicia o servico, e a atualizacao "morre antes de concluir". Entao
# o bridge so grava o PEDIDO ($INSTALL_DIR/.update-request.json, com chatId,
# threadId e pedidoEm) e o vigia scripts/update-verdict.sh, que o cron do usuario
# roda de minuto em minuto FORA da unit, executa o atualizador por ele. O vigia
# vem dentro do pacote-base (os dois motores usam o mesmo script); aqui o bloco
# entra no topo dele, antes do "[ -f \$RECIBO ] || exit 0", uma vez so (marcador).
injetar_handoff_update_verdict() {
  local vigia="$1" tmp
  [ -f "$vigia" ] || { echo "   (aviso) pacote sem scripts/update-verdict.sh; handoff do /atualiza nao instalado."; return 0; }
  if grep -q 'LEON-HANDOFF-UPDATE v1' "$vigia"; then
    echo "   handoff do /atualiza ja presente no vigia."
    return 0
  fi
  tmp="$vigia.leon-new"
  python3 - "$vigia" "$tmp" <<'PY' || { rm -f -- "$tmp"; echo "ERRO: nao consegui gravar o handoff do /atualiza no vigia. suporte: https://wa.me/5511961562217" >&2; return 1; }
import os, re, sys
src, dst = sys.argv[1:]
text = open(src, encoding="utf-8").read()
bloco = r'''# --- LEON-HANDOFF-UPDATE v1 (gravado pelo instalador) ------------------
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
      # Mesmo efeito de "set -a; . .env; set +a", sem executar valor mal formado:
      # so linhas CHAVE=valor viram ambiente.
      while IFS= read -r _linha || [ -n "$_linha" ]; do
        case "$_linha" in [A-Za-z_]*=*) export "$_linha" 2>/dev/null || true ;; esac
      done < "$BRIDGE_DIR/.env"
      nohup bash "$BRIDGE_DIR/update-pago.sh" "$CHAT_PEDIDO" "$THREAD_PEDIDO" >/dev/null 2>&1 &
    )
  fi
fi
# --- fim LEON-HANDOFF-UPDATE ------------------------------------------------
'''
anchor = re.compile(r'^\[ -f "\$RECIBO" \] \|\| exit 0.*$', re.M)
m = anchor.search(text)
if m is None:
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
    echo "ERRO: o vigia com o handoff nao compila; original preservado. suporte: https://wa.me/5511961562217" >&2
    return 1
  fi
  mv -f -- "$tmp" "$vigia"
  echo "   handoff do /atualiza gravado no vigia (scripts/update-verdict.sh)."
}

# Ganchos de bancada: rodam UMA funcao e saem, sem EMAIL/NOME/token (os testes
# offline exercitam o pin do Node, o pin do Codex CLI, a unit e o handoff).
if [ "$LEON_TEST_NODE_ONLY" = "1" ]; then
  ensure_node_runtime
  exit $?
fi
if [ "$LEON_TEST_CODEX_CLI_ONLY" = "1" ]; then
  ensure_codex_cli
  exit $?
fi
if [ "$LEON_TEST_UNIT_ONLY" = "1" ]; then
  # args: <arquivo de saida> <install_dir> <node_bin>; motor = LEON_ENGINE
  write_service_unit "${1:?saida}" "$(id -un)" "${2:?install_dir}" "${3:?node_bin}" "$LEON_ENGINE"
  exit $?
fi
if [ "$LEON_TEST_HANDOFF_ONLY" = "1" ]; then
  injetar_handoff_update_verdict "${1:?vigia}"
  exit $?
fi

# TOKEN POR STDIN (portado do monólito 18/08): a página Codex manda o BOT_TOKEN pelo canal
# privado do stdin (LEON_TOKEN_STDIN=1), pra o segredo nunca entrar em argv/env/histórico.
# Sem este bloco o unificado morria em "BOT_TOKEN vazio" — toda instalação Codex quebrava.
if [ "$LEON_TOKEN_STDIN" = "1" ]; then
  IFS= read -r BOT_TOKEN \
    || { echo "ERRO: não recebi o token no canal privado da instalação." >&2; exit 1; }
  [ -n "$BOT_TOKEN" ] \
    || { echo "ERRO: token vazio no canal privado da instalação." >&2; exit 1; }
fi

[ -z "$EMAIL" ]     && { echo "ERRO: EMAIL vazio." >&2; usage; }
[ -z "$NOME" ]      && { echo "ERRO: NOME vazio." >&2; usage; }
[ -z "$GENDER" ]    && { echo "ERRO: GENDER vazio (use 'male' ou 'female')." >&2; usage; }
[ -z "$BOT_TOKEN" ] && { echo "ERRO: BOT_TOKEN vazio." >&2; usage; }

if [ "$GENDER" != "male" ] && [ "$GENDER" != "female" ]; then
  echo "ERRO: GENDER precisa ser 'male' ou 'female' (recebi '$GENDER')." >&2
  exit 1
fi

if ! printf %s "$BOT_TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]{20,}$'; then
  echo "ERRO: BOT_TOKEN nao bate o formato esperado (ex: 123456789:ABCdef...)." >&2
  echo "Pegue o token conversando com @BotFather no Telegram." >&2
  exit 1
fi

if ! printf %s "$EMAIL" | grep -qE '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; then
  echo "ERRO: EMAIL nao parece valido: '$EMAIL'." >&2
  exit 1
fi

CENTRAL="${LEON_CENTRAL:-https://licenca.leonardomolina.com.br}"
LEON_USER="${LEON_USER:-leon}"

echo ""
echo "========================================"
echo "  PROJETO LEON · Socio IA 24x7"
echo "  instalador oficial"
echo "========================================"
echo "  email:  $EMAIL"
echo "  nome:   $NOME"
echo "  voz:    $([ "$GENDER" = "male" ] && echo "Antonio (masc)" || echo "Francisca (fem)")"
echo "========================================"
echo ""

# ============================================================
# 1. FASE ROOT: pre-reqs + cria user nao-root + pivota
# MOCK nunca entra aqui: a bancada de 19/08 mostrou que o mock criava usuario,
# unit systemd e sudoers DE VERDADE (efeito colateral silencioso num terminal de
# trabalho, revertido na mao). Em mock a fase root e pulada inteira e a fase user
# roda como quem chamou, escrevendo so no INSTALL_DIR da bancada.
# ============================================================
if [ "$(id -u)" = "0" ] && [ "$MOCK_MODE" != "1" ]; then
  echo ">> voce esta como root. vou criar '$LEON_USER' e reinstalar como ele."
  echo ""
  # runuser (util-linux) no lugar de sudo -u: sudoers alheio na VPS do cliente
  # travou o pulo root>leon (22/08). runuser nao consulta sudoers.
  command -v runuser >/dev/null 2>&1 \
    || { echo "ERRO: 'runuser' (util-linux) nao existe nesta VPS. suporte: https://wa.me/5511961562217" >&2; exit 1; }

  # Para servico antigo (instalacao anterior). Tem que parar ANTES da captura do
  # Telegram: dois consumidores de getUpdates no mesmo bot se derrubam.
  if systemctl is-active leon-agente.service >/dev/null 2>&1; then
    echo ">> parando leon-agente.service antigo..."
    # So para: a unit fica no lugar ate a nova ser gravada, pra fase do usuario
    # conseguir religar o servico antigo se abortar no meio (sudoers permite start).
    systemctl stop leon-agente.service >/dev/null 2>&1 || true
    LEON_SERVICO_PARADO_PELO_INSTALADOR=1; export LEON_SERVICO_PARADO_PELO_INSTALADOR
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  # apt 100% mudo: sem a tela roxa do needrestart (travou o cliente leigo em
  # 22/08) e sem pergunta de conffile (quem ja tem config local fica com a dela).
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
  APT_INSTALL=(apt-get install -y -qq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

  # Um repositorio alheio quebrado nao pode derrubar a instalacao inteira: o
  # update avisa e segue com o indice que existe; o install e que decide.
  apt-get update -qq >/dev/null 2>/tmp/apt-update.err \
    || echo "   (aviso) apt-get update reclamou de algum repositorio; sigo com o indice que existe."
  # cron: o agente instala sozinho as rotinas de backup, saude, a rede de
  # seguranca do update e o vigia do /atualiza. Sem cron, nada disso existe.
  # python3-venv/pip e ffmpeg: voz e transcricao sao obrigatorias (A3).
  echo ">> instalando pacotes do sistema (git, curl, python3, ffmpeg, cron...)..."
  "${APT_INSTALL[@]}" \
    git curl ca-certificates tar cron \
    python3 python3-venv python3-pip ffmpeg \
    dbus-user-session locales sudo >/dev/null 2>/tmp/apt-base.err \
    || { echo "ERRO: pacotes base do sistema nao instalaram." >&2
         [ -s /tmp/apt-base.err ] && echo "detalhe apt: $(tail -n 3 /tmp/apt-base.err)" >&2
         echo "abortando. suporte: https://wa.me/5511961562217" >&2; exit 1; }
  systemctl enable --now cron >/dev/null 2>&1 || true
  locale-gen C.UTF-8 2>/dev/null || true

  # POSTGRES (24/08, lei do dono: "o cliente precisa ter o meu LEON com todas as
  # habilidades"): o LEON do dono espelha o estado num banco `leon` e algumas skills
  # consultam banco. A casa do cliente nasce com o mesmo. BEST-EFFORT declarado:
  # se o apt do postgres falhar, a instalacao SEGUE (o agente e 100% funcional por
  # arquivos; o banco e espelho, nunca dependencia). O updater roda SEM root e nao
  # instala postgres: casa sem banco liga depois com um sudo apt do dono.
  echo ">> instalando o banco de dados (Postgres)..."
  if "${APT_INSTALL[@]}" postgresql postgresql-contrib >/dev/null 2>/tmp/apt-pg.err; then
    systemctl enable --now postgresql >/dev/null 2>&1 || true
    # extensao de embedding: opcional (nem todo Ubuntu tem o pacote; sem ela o banco vive igual)
    "${APT_INSTALL[@]}" postgresql-16-pgvector >/dev/null 2>&1 || true
  else
    echo "   (aviso) postgres nao instalou agora; o agente funciona igual. Pra ligar o banco depois: sudo apt install postgresql (o proximo update completa)."
  fi
  # papel + banco do usuario de servico (idempotente; falha nao derruba nada)
  if command -v psql >/dev/null 2>&1; then
    sudo -u postgres psql -tAc "select 1 from pg_roles where rolname='$LEON_USER'" 2>/dev/null | grep -q 1       || sudo -u postgres createuser "$LEON_USER" 2>/dev/null || true
    sudo -u postgres psql -lqt 2>/dev/null | cut -d"|" -f1 | grep -qw leon       || sudo -u postgres createdb -O "$LEON_USER" leon 2>/dev/null || true
  fi

  # Node do sistema: decidido por /usr/bin/node, NUNCA por "command -v node".
  # O root com nvm de outra IA tinha node no PATH dele, a checagem passava, e o
  # usuario leon ficava sem node nenhum. Abaixo de 20 (ou ausente): NodeSource 22.
  sys_node_major() {
    local v
    v="$(/usr/bin/node -v 2>/dev/null || true)"; v="${v#v}"; v="${v%%.*}"
    printf %s "$v" | grep -qE '^[0-9]+$' && printf %s "$v" || printf 0
  }
  if [ "$(sys_node_major)" -lt 20 ]; then
    echo ">> instalando Node 22 (NodeSource) no sistema..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>/tmp/nodesource.err || true
    "${APT_INSTALL[@]}" nodejs >/dev/null 2>/tmp/apt-nodejs.err || true
  fi
  if [ "$(sys_node_major)" -lt 20 ]; then
    echo "ERRO: Node 22 nao instalou em /usr/bin/node nesta VPS." >&2
    [ -s /tmp/nodesource.err ] && echo "detalhe NodeSource: $(tail -n 3 /tmp/nodesource.err)" >&2
    [ -s /tmp/apt-nodejs.err ] && echo "detalhe apt: $(tail -n 3 /tmp/apt-nodejs.err)" >&2
    echo "abortando. suporte: https://wa.me/5511961562217" >&2
    exit 1
  fi
  echo "   node do sistema $(/usr/bin/node -v) em /usr/bin/node"

  # CLI do motor. Codex: nada global; o CLI pinado nasce no prefixo dedicado do
  # usuario leon, na fase user (A4). Claude: Claude Code pelo npm DO SISTEMA
  # (/usr/bin/node + /usr/bin/npm, prefixo /usr), pra cair em /usr/bin/claude
  # e nao no prefixo do nvm de quem chamou.
  if [ "$LEON_ENGINE" = codex ]; then
    echo "   Codex CLI $LEON_CODEX_CLI_VERSION: vai pro prefixo dedicado de '$LEON_USER' (sem npm global)."
  else
    claude_cli_ok() { PATH="$SYS_PATH" claude --version >/dev/null 2>&1; }
    if ! claude_cli_ok; then
      echo ">> instalando Claude Code CLI (npm do sistema)..."
      PATH="$SYS_PATH" /usr/bin/node /usr/bin/npm install -g --prefix=/usr @anthropic-ai/claude-code \
        >/dev/null 2>/tmp/npm-claude.err || true
    fi
    if ! claude_cli_ok; then
      echo "ERRO: Claude CLI nao instalou nesta VPS." >&2
      [ -s /tmp/npm-claude.err ] && echo "detalhe npm: $(tail -n 3 /tmp/npm-claude.err)" >&2
      echo "abortando. suporte: https://wa.me/5511961562217" >&2
      exit 1
    fi
    echo "   claude $(PATH="$SYS_PATH" claude --version 2>/dev/null)"
  fi

  # Cria usuario '$LEON_USER' (sem sudo, blast radius pequeno)
  if ! id "$LEON_USER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$LEON_USER" >/dev/null
  fi

  loginctl enable-linger "$LEON_USER" >/dev/null 2>&1 || true

  LEON_HOME_TMP=$(getent passwd "$LEON_USER" | cut -d: -f6)
  if [ -z "$LEON_HOME_TMP" ] || [ ! -d "$LEON_HOME_TMP" ]; then
    echo "ERRO: home do usuario '$LEON_USER' nao encontrada ('$LEON_HOME_TMP')." >&2
    exit 1
  fi
  INSTALL_DIR_TMP="${LEON_DIR:-$LEON_HOME_TMP/socio-ia}"

  # Cria service systemd de SISTEMA (dispensa DBus user, evita "no medium found").
  # Aponta pra ~$LEON_USER/socio-ia, dir que a fase user vai popular. No Codex o
  # ExecStart e o Node DEDICADO (caminho deterministico dentro da home do leon;
  # a fase user o instala antes de subir o servico).
  if [ "$LEON_ENGINE" = codex ]; then
    NODE_BIN_UNIT="$LEON_HOME_TMP/.leon/node/releases/$LEON_NODE_VERSION/bin/node"
  else
    NODE_BIN_UNIT=/usr/bin/node
  fi
  write_service_unit /etc/systemd/system/leon-agente.service "$LEON_USER" "$INSTALL_DIR_TMP" "$NODE_BIN_UNIT" "$LEON_ENGINE"
  systemctl daemon-reload

  # Libera $LEON_USER a controlar SOMENTE o proprio service (sudo estreito, sem senha).
  # journalctl SEM coringa no fim e SEMPRE com --no-pager: com coringa, o agente podia pedir
  # uma saida que abre o "less" como root, e o less tem um comando (!) que abre terminal — ai
  # o acesso "estreito" virava root de verdade. Duas linhas fixas (com e sem -f) cobrem o uso
  # real (ver log recente, acompanhar ao vivo) sem deixar escolher flag nenhuma.
  cat > /etc/sudoers.d/leon-agente <<EOF
$LEON_USER ALL=(root) NOPASSWD: /bin/systemctl start leon-agente.service, /bin/systemctl stop leon-agente.service, /bin/systemctl restart leon-agente.service, /bin/systemctl enable leon-agente.service, /bin/systemctl disable leon-agente.service, /bin/systemctl status leon-agente.service, /bin/systemctl is-active leon-agente.service, /bin/systemctl enable --now leon-agente.service, /usr/bin/journalctl -u leon-agente.service -n 200 --no-pager, /usr/bin/journalctl -u leon-agente.service -n 200 --no-pager -f
EOF
  chmod 0440 /etc/sudoers.d/leon-agente
  visudo -c -f /etc/sudoers.d/leon-agente >/dev/null

  # Roda um comando como o usuario do LEON, em env limpo (HOME dele, PATH do
  # sistema). O heredoc de quem chama vira o stdin do bash -s la dentro.
  como_leon() {
    runuser -u "$LEON_USER" -- env -i HOME="$LEON_HOME_TMP" USER="$LEON_USER" LOGNAME="$LEON_USER" \
      PATH="$SYS_PATH" LANG=C.UTF-8 LC_ALL=C.UTF-8 "$@"
  }

  # Voz e transcricao sao OBRIGATORIAS nos dois motores (o produto fala e escuta
  # de fabrica): falha = ERRO + suporte, nunca "opcional" em silencio. Cada bloco
  # e idempotente: so refaz o que nao existe.
  echo ">> instalando voz local gratis (Piper TTS · pt_BR)..."
  como_leon bash -s <<'PIPER_SETUP' || { echo "ERRO: a voz local (Piper TTS) nao instalou. suporte: https://wa.me/5511961562217" >&2; exit 1; }
set -e
mkdir -p ~/.leon/piper-venv ~/.leon/voices/piper
if [ ! -x ~/.leon/piper-venv/bin/piper ]; then
  python3 -m venv ~/.leon/piper-venv
  ~/.leon/piper-venv/bin/pip install --quiet piper-tts >/dev/null
fi
for f in pt_BR-faber-medium.onnx pt_BR-faber-medium.onnx.json; do
  if [ ! -s ~/.leon/voices/piper/$f ]; then
    curl -sfL -o ~/.leon/voices/piper/$f.part "https://huggingface.co/rhasspy/piper-voices/resolve/main/pt/pt_BR/faber/medium/$f"
    mv -f ~/.leon/voices/piper/$f.part ~/.leon/voices/piper/$f
  fi
done
PIPER_SETUP

  echo ">> instalando voz nuvem gratis (Edge TTS · Antonio/Francisca)..."
  como_leon bash -s <<'EDGE_SETUP' || { echo "ERRO: a voz nuvem (Edge TTS) nao instalou. suporte: https://wa.me/5511961562217" >&2; exit 1; }
set -e
mkdir -p ~/.leon/edgetts-venv
if [ ! -x ~/.leon/edgetts-venv/bin/edge-tts ]; then
  python3 -m venv ~/.leon/edgetts-venv
  ~/.leon/edgetts-venv/bin/pip install --quiet edge-tts >/dev/null
fi
EDGE_SETUP

  echo ">> instalando transcricao de audio local (faster-whisper)..."
  como_leon bash -s <<'WHISPER_SETUP' || { echo "ERRO: a transcricao de audio (faster-whisper) nao instalou. suporte: https://wa.me/5511961562217" >&2; exit 1; }
set -e
mkdir -p ~/.leon/whisper-venv
if [ ! -x ~/.leon/whisper-venv/bin/python3 ] || ! ~/.leon/whisper-venv/bin/python3 -c "import faster_whisper" 2>/dev/null; then
  python3 -m venv ~/.leon/whisper-venv
  ~/.leon/whisper-venv/bin/pip install --quiet --upgrade pip >/dev/null
  ~/.leon/whisper-venv/bin/pip install --quiet faster-whisper >/dev/null
fi
# 25/08 (lei do dono: "transcricao TEM que ser nativa"): o modelo baixa AGORA, na
# instalacao — nao no primeiro audio do cliente. Sem isto, o primeiro audio dele
# virava "roda /audio e espera uns minutos": vergonha na frente de cliente novo.
# Baixa 'small' (o mesmo do voice-handler); ~460MB, uma vez so. Falha nao derruba
# a instalacao (sem rede pro hub = o updater baixa no proximo ciclo).
timeout 600 ~/.leon/whisper-venv/bin/python3 - <<'PYMODEL' || echo "   (aviso) modelo de audio nao baixou agora; o proximo update completa"
from faster_whisper import WhisperModel
WhisperModel("small", device="cpu", compute_type="int8")
print("   modelo de audio pronto (transcricao nativa de fabrica)")
PYMODEL
WHISPER_SETUP

  # O atualizador do Codex le TOML em python; Ubuntu 22.04 tem Python 3.10, sem
  # tomllib (so 3.11+). Garante o tomli no usuario leon, ou aborta com erro claro.
  if [ "$LEON_ENGINE" = codex ]; then
    if ! como_leon python3 -c 'import tomllib' >/dev/null 2>&1 \
       && ! como_leon python3 -c 'import tomli' >/dev/null 2>&1; then
      echo ">> instalando leitor TOML (tomli) pro atualizador..."
      como_leon python3 -m pip install --quiet --user tomli >/dev/null 2>/tmp/pip-tomli.err || true
      if ! como_leon python3 -c 'import tomli' >/dev/null 2>&1; then
        echo "ERRO: o python do usuario '$LEON_USER' ficou sem tomllib/tomli; o atualizador nao conseguiria ler o config.toml." >&2
        [ -s /tmp/pip-tomli.err ] && echo "detalhe pip: $(tail -n 3 /tmp/pip-tomli.err)" >&2
        echo "abortando. suporte: https://wa.me/5511961562217" >&2
        exit 1
      fi
    fi
  fi

  # Baixa este mesmo script pra home do user e re-executa como ele (env vars preservadas)
  LEON_HOME="$LEON_HOME_TMP"
  if ! curl -fsSL "$CENTRAL/install-leon.sh" -o "$LEON_HOME/install-leon.sh"; then
    echo "ERRO: falha ao baixar $CENTRAL/install-leon.sh pra $LEON_HOME/install-leon.sh." >&2
    exit 1
  fi
  chown "$LEON_USER:$LEON_USER" "$LEON_HOME/install-leon.sh"
  chmod 0755 "$LEON_HOME/install-leon.sh"
  if [ ! -s "$LEON_HOME/install-leon.sh" ]; then
    echo "ERRO: $LEON_HOME/install-leon.sh vazio apos download." >&2
    exit 1
  fi

  echo ""
  echo "========================================"
  echo "  PASSO ROOT · CONCLUIDO"
  echo "========================================"
  echo "Continuando como '$LEON_USER'..."
  echo ""

  # Pivota com runuser (sem sudoers) e env EXPLICITO: o cwd vai pra home do leon
  # (o de root nao e legivel por ele) e so o que a fase user precisa atravessa.
  cd "$LEON_HOME"
  exec runuser -u "$LEON_USER" -- env -i \
    HOME="$LEON_HOME" USER="$LEON_USER" LOGNAME="$LEON_USER" PATH="$SYS_PATH" \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM="${TERM:-dumb}" \
    EMAIL="$EMAIL" \
    NOME="$NOME" \
    GENDER="$GENDER" \
    BOT_TOKEN="$BOT_TOKEN" \
    MOCK_MODE="$MOCK_MODE" \
    LEON_ENGINE="$LEON_ENGINE" \
    LEON_CENTRAL="$CENTRAL" \
    LEON_DIR="${LEON_DIR:-}" \
    OWNER_CHAT_ID="${OWNER_CHAT_ID:-}" \
    CODEX_MODEL="$CODEX_MODEL" \
    LEON_SERVICO_PARADO_PELO_INSTALADOR="${LEON_SERVICO_PARADO_PELO_INSTALADOR:-}" \
    bash "$LEON_HOME/install-leon.sh"
fi

# ============================================================
# 2. FASE USER (nao-root)
# ============================================================
# Se a fase root parou o LEON antigo e esta fase abortar antes de gravar a unit
# nova, o servico antigo volta (sudoers da instalacao anterior permite start).
# Sem isto, "o servico antigo continua no ar" era mentira: ficava parado (23/08).
religar_servico_antigo_se_abortar() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ "${LEON_SERVICO_PARADO_PELO_INSTALADOR:-}" = "1" ] \
     && [ -f /etc/systemd/system/leon-agente.service ]; then
    if sudo -n /bin/systemctl start leon-agente.service >/dev/null 2>&1; then
      echo ">> instalacao abortada; o LEON antigo foi religado e continua no ar." >&2
    else
      echo ">> instalacao abortada e nao consegui religar o LEON antigo sozinho: rode 'sudo systemctl start leon-agente.service' como root. suporte: https://wa.me/5511961562217" >&2
    fi
  fi
  exit "$rc"
}
trap religar_servico_antigo_se_abortar EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
# ============================================================
# (continuacao da fase user)
# ============================================================
INSTALL_DIR="${LEON_DIR:-$HOME/socio-ia}"

if [ "$MOCK_MODE" = "1" ]; then
  # Bancada: dir separado por padrao, pra NUNCA sobrescrever uma instalacao real
  # que more em ~/socio-ia. LEON_DIR explicito continua mandando.
  [ -z "${LEON_DIR:-}" ] && INSTALL_DIR="$HOME/socio-ia-mock"
  echo ">> MOCK_MODE=1: fase root pulada INTEIRA (sem apt, sem usuario, sem unit systemd, sem sudoers)."
  echo ">> MOCK roda como '$(id -un)' e escreve so em: $INSTALL_DIR"
fi

command -v curl    >/dev/null || { echo "ERRO: curl faltando." >&2; exit 1; }
command -v tar     >/dev/null || { echo "ERRO: tar faltando." >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERRO: python3 faltando." >&2; exit 1; }
# Os DOIS motores verificam manifesto assinado (Ed25519) antes de extrair qualquer coisa.
command -v openssl >/dev/null || { echo "ERRO: openssl faltando." >&2; exit 1; }

# ------------------------------------------------------------
# 2.0 Runtime do motor. Codex: Node e Codex CLI PINADOS no prefixo dedicado
# do usuario (A4), antes de qualquer login. Claude: confere o Node do sistema
# e o Claude Code que a fase root instalou.
# ------------------------------------------------------------
if [ "$MOCK_MODE" != "1" ]; then
  if [ "$LEON_ENGINE" = codex ]; then
    echo ">> preparando runtime dedicado do Codex (Node $LEON_NODE_VERSION + Codex CLI $LEON_CODEX_CLI_VERSION)..."
    ensure_node_runtime \
      || { echo "ERRO: o Node dedicado $LEON_NODE_VERSION nao ficou pronto. suporte: https://wa.me/5511961562217" >&2; exit 1; }
    ensure_codex_cli \
      || { echo "ERRO: o Codex CLI $LEON_CODEX_CLI_VERSION nao ficou pronto. suporte: https://wa.me/5511961562217" >&2; exit 1; }
  else
    [ -x /usr/bin/node ] || { echo "ERRO: node do sistema faltando (/usr/bin/node)." >&2; exit 1; }
    command -v claude >/dev/null || { echo "ERRO: claude CLI faltando." >&2; exit 1; }
  fi
fi

# ------------------------------------------------------------
# 2.1 Login no motor (unico ponto interativo: URL no navegador)
# Claude usa OAuth por codigo de 6 digitos; Codex usa o login por codigo de
# dispositivo (--device-auth) no binario pinado e em env limpo (ver
# codex_env_limpo), e em seguida prova que a conta responde no modelo (A8).
# ------------------------------------------------------------
if [ "$MOCK_MODE" != "1" ]; then
  if [ "$LEON_ENGINE" = codex ]; then
    mkdir -p "$LEON_CODEX_HOME" && chmod 0700 "$LEON_CODEX_HOME"
    codex_login_unificado || { echo "ERRO: login do Codex falhou. suporte: https://wa.me/5511961562217" >&2; exit 1; }
    provar_modelo_codex || exit 1
    echo ""
  elif [ ! -d "$HOME/.claude" ] || [ ! -f "$HOME/.claude/.credentials.json" ]; then
    echo ""
    echo "========================================"
    echo "  LOGIN NO CLAUDE (1 unica vez)"
    echo "========================================"
    echo "Vai aparecer uma URL grande. Copia, abre no navegador,"
    echo "faz login na conta Anthropic, autoriza. Cola o codigo"
    echo "de 6 digitos de volta aqui e enter."
    echo ""
    claude auth login < /dev/tty || { echo "ERRO: claude auth login falhou." >&2; exit 1; }
    echo ""
  fi
fi

# ------------------------------------------------------------
# 2.2 Machine ID
# ------------------------------------------------------------
MAC=$(ip link show 2>/dev/null | awk '/link\/ether/{print $2;exit}' || echo "no-mac")
HOSTID=$(hostname)
MACHINE_ID=$(echo -n "$MAC-$HOSTID" | sha256sum | awk '{print $1}')
echo "machine_id: ${MACHINE_ID:0:16}..."

# ------------------------------------------------------------
# 2.3 Valida compra + baixa motor
# ------------------------------------------------------------
# RAMO B2 · runtime do motor (unificacao 2.0.5): so o Codex carrega runtime assinado.
# baixa_runtime_codex baixa o manifesto assinado da release (release-manifest.json +
# .sig), confere a assinatura Ed25519 com openssl pkeyutl contra a chave publica
# gravada por write_release_public_key, e valida kind/channel/keyFingerprint + o
# contrato de cada artefato num python (o mesmo do install-codex, copiado verbatim).
# So depois disso passa pelo gate de compra (/download-codex?email=), confere o
# pacote-base com verify_signed_artifact e instala base + bundle no INSTALL_DIR. O
# Claude segue no bloco /download original, intacto.

# normalizar_agent_base resolve os placeholders @@LEON_*@@ / $LEON_* do AGENT-BASE
# do pacote-base contra os caminhos reais desta instalacao (skills, install, tmp,
# codex home, brain, area de trabalho, saida de missao). Falha dura se sobrar
# @@LEON_ ou $LEON_ (verbatim do install-codex; install_dir -> $INSTALL_DIR,
# brain -> $LEON_DATA_DIR/brain).
normalizar_agent_base() {
  local agent_base="$1"
  [ -f "$agent_base" ] || return 0
  python3 - "$agent_base" "$LEON_SKILLS_DIR" "$INSTALL_DIR" "$LEON_TMPDIR" "$LEON_CODEX_HOME" \
    "$LEON_DATA_DIR/brain" "$LEON_WORK_AREA" "$LEON_MISSION_OUTPUT_DIR" <<'PY'
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
if "@@LEON_" in text or re.search(r"\$LEON_", text):
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

baixa_runtime_codex() {
  echo ""
  echo ">> validando compra e baixando motor Codex (release assinada)..."
  local RELEASE_MANIFEST RELEASE_SIGNATURE RELEASE_PUBLIC_KEY RELEASE_METADATA
  RELEASE_MANIFEST=$(mktemp)
  RELEASE_SIGNATURE=$(mktemp)
  RELEASE_PUBLIC_KEY=$(mktemp)
  RELEASE_METADATA=$(mktemp)
  curl -fsSL --max-filesize 524288 --retry 3 --retry-delay 2 --retry-connrefused "$CENTRAL/release-manifest.json" -o "$RELEASE_MANIFEST" \
    && curl -fsSL --max-filesize 64 --retry 3 --retry-delay 2 --retry-connrefused "$CENTRAL/release-manifest.sig" -o "$RELEASE_SIGNATURE" \
    || { echo "ERRO: a central nao entregou o manifesto assinado da release." >&2; exit 1; }
  write_release_public_key "$RELEASE_PUBLIC_KEY" \
    || { echo "ERRO: chave publica da release nao confere o fingerprint de confianca." >&2; exit 1; }
  openssl pkeyutl -verify -rawin -pubin -inkey "$RELEASE_PUBLIC_KEY" \
    -in "$RELEASE_MANIFEST" -sigfile "$RELEASE_SIGNATURE" >/dev/null 2>&1 \
    || { echo "ERRO: assinatura da release invalida." >&2; exit 1; }
  python3 - "$RELEASE_MANIFEST" "$LEON_RELEASE_TRUST_FINGERPRINT" > "$RELEASE_METADATA" <<'PY' \
    || { echo "ERRO: contrato da release invalido." >&2; exit 1; }
import json,re,sys
manifest,fingerprint=sys.argv[1:]
try: data=json.load(open(manifest,encoding="utf-8"))
except Exception: raise SystemExit(1)
if set(data)!={"schema","kind","channel","version","minVersion","codexCliVersion","nodeVersion","keyFingerprint","artifacts"}: raise SystemExit(1)
if data["schema"]!=2 or data["kind"]!="leon-codex-release" or data["channel"]!="stable": raise SystemExit(1)
if data["keyFingerprint"]!=fingerprint: raise SystemExit(1)
version_re=re.compile(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)")
if not version_re.fullmatch(str(data["version"])) or not version_re.fullmatch(str(data["minVersion"])): raise SystemExit(1)
if data["codexCliVersion"]!="0.147.0" or data["nodeVersion"]!="22.22.0": raise SystemExit(1)
artifacts=data["artifacts"]
if set(artifacts)!={"base","bundle","skills","updater"}: raise SystemExit(1)
expected={
 "base":("leon-base-curated.tar.gz","/download-codex",True),
 "bundle":("leon-codex-appserver-v2.tar.gz","/leon-codex-appserver-v2.tar.gz",False),
 "skills":("leon-skills-codex-minimal.tar.gz","/leon-skills-codex-minimal.tar.gz",False),
 "updater":("update-pago-codex.sh","/update-pago-codex.sh",False),
}
print("version="+data["version"]); print("minVersion="+data["minVersion"]); print("channel="+data["channel"])
print("codexCliVersion="+data["codexCliVersion"]); print("nodeVersion="+data["nodeVersion"])
for key,(name,url,licensed) in expected.items():
    item=artifacts[key]
    if set(item)!={"file","url","sha256","bytes","licensed"}: raise SystemExit(1)
    if item["file"]!=name or item["url"]!=url or item["licensed"] is not licensed: raise SystemExit(1)
    if not re.fullmatch(r"[0-9a-f]{64}",str(item["sha256"])) or not isinstance(item["bytes"],int) or not 1<=item["bytes"]<=536_870_912: raise SystemExit(1)
    print(f"{key}_sha256={item['sha256']}"); print(f"{key}_bytes={item['bytes']}"); print(f"{key}_url={item['url']}")
PY
  # shellcheck disable=SC1090
  . "$RELEASE_METADATA"
  rm -f -- "$RELEASE_MANIFEST" "$RELEASE_SIGNATURE" "$RELEASE_PUBLIC_KEY" "$RELEASE_METADATA"

  # Gate de compra: o pacote-base sai por /download-codex?email= (licenciado).
  echo ">> validando compra..."
  local TARBALL EMAIL_ENC HTTP_CODE
  TARBALL=$(mktemp --suffix=.tar.gz)
  EMAIL_ENC=$(printf %s "$EMAIL" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))" 2>/dev/null || printf %s "$EMAIL")
  HTTP_CODE=$(curl -sS --max-filesize "$base_bytes" --retry 3 --retry-delay 2 --retry-connrefused \
    -w "%{http_code}" -o "$TARBALL" "$CENTRAL$base_url?email=$EMAIL_ENC")
  if [ "$HTTP_CODE" != "200" ]; then
    echo "ERRO: nao consegui validar a compra (HTTP $HTTP_CODE)." >&2
    echo "possiveis causas:" >&2
    echo "  · email diferente do que voce usou na compra (Cakto/Hubla)" >&2
    echo "  · compra ainda nao processada (aguarde 1min e tente de novo)" >&2
    echo "  · reembolso/cancelamento (licenca bloqueada)" >&2
    echo "suporte: https://wa.me/5511961562217" >&2
    rm -f -- "$TARBALL"
    exit 1
  fi
  verify_signed_artifact "$TARBALL" "$base_sha256" "$base_bytes" "pacote-base" \
    || { rm -f -- "$TARBALL"; exit 1; }
  echo ">> motor baixado. instalando em $INSTALL_DIR..."
  mkdir -p "$INSTALL_DIR"
  local STAGE INNER
  STAGE=$(mktemp -d)
  tar --no-same-owner --no-same-permissions -xzf "$TARBALL" -C "$STAGE"
  INNER=$(find "$STAGE" -maxdepth 1 -mindepth 1 -type d | head -1)
  if [ -z "$INNER" ]; then
    echo "ERRO: tarball sem conteudo esperado." >&2
    rm -rf -- "$STAGE" "$TARBALL"
    exit 1
  fi
  cp -a "$INNER"/. "$INSTALL_DIR"/
  normalizar_agent_base "$INSTALL_DIR/AGENT-BASE.md"
  # NUCLEO UNICO (23/08): a alma do agente e a MESMA nos dois motores; o que muda e o
  # bloco _MOTOR-<motor>. As pecas vem PRONTAS no pacote (o cliente nao gera doutrina) e
  # moram na persona, ao lado do que o bridge ja le. Placeholders resolvidos igual ao
  # AGENT-BASE, senao o agente le "@@LEON_TMPDIR@@" no lugar do caminho de verdade.
  mkdir -p "$PERSONA_DIR_LOCAL"
  for _peca in NUCLEO-LEON.md _MOTOR-CLAUDE.md _MOTOR-CODEX.md; do
    if [ -f "$INSTALL_DIR/$_peca" ]; then
      mv -f "$INSTALL_DIR/$_peca" "$PERSONA_DIR_LOCAL/$_peca"
      normalizar_agent_base "$PERSONA_DIR_LOCAL/$_peca"
    fi
  done
  [ -f "$INSTALL_DIR/CAMINHOS-CANONICOS.md" ] && normalizar_agent_base "$INSTALL_DIR/CAMINHOS-CANONICOS.md"
  rm -rf -- "$STAGE" "$TARBALL"

  # Runtime app-server v2: bundle assinado (bridge, adapter, shim juntos). Validado
  # por verify_signed_artifact e por um python de estrutura (verbatim do install-codex)
  # antes de tocar no INSTALL_DIR.
  echo ">> instalando runtime Codex persistente..."
  local BUNDLE_TMP BUNDLE_EXTRACT
  BUNDLE_TMP=$(mktemp)
  if ! curl -fsSL --max-filesize "$bundle_bytes" --retry 3 --retry-delay 2 --retry-connrefused \
      "$CENTRAL$bundle_url" -o "$BUNDLE_TMP"; then
    echo "ERRO: nao consegui baixar o runtime Codex completo." >&2
    rm -f -- "$BUNDLE_TMP"
    exit 1
  fi
  verify_signed_artifact "$BUNDLE_TMP" "$bundle_sha256" "$bundle_bytes" "runtime Codex" \
    || { rm -f -- "$BUNDLE_TMP"; exit 1; }
  if ! python3 - "$BUNDLE_TMP" <<'PY'
import posixpath, sys, tarfile

allowed_files = {
    "bridge.cjs",
    "capabilities.json",
    "appserver/adapter.cjs",
    "appserver/index.cjs",
    "appserver/package.json",
    "lib/onboarding.js",
    "lib/meta-connect.js",
    "lib-motores/codex-appserver.cjs",
    "smoke/appserver-smoke.cjs",
    "workers/piper.js",
}
allowed_dirs = {"appserver", "lib", "lib-motores", "smoke", "workers"}
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
        if name not in allowed_dirs:
            raise SystemExit(1)
        continue
    if not member.isfile() or name not in allowed_files or member.size > 2_000_000:
        raise SystemExit(1)
    seen.add(name)
raise SystemExit(0 if seen == allowed_files else 1)
PY
  then
    echo "ERRO: bundle Codex incompleto ou com caminho inseguro." >&2
    rm -f -- "$BUNDLE_TMP"
    exit 1
  fi
  BUNDLE_EXTRACT=$(mktemp -d)
  tar --no-same-owner --no-same-permissions -xzf "$BUNDLE_TMP" -C "$BUNDLE_EXTRACT"
  cp -a "$BUNDLE_EXTRACT"/. "$INSTALL_DIR"/
  chmod 0700 "$INSTALL_DIR/bridge.cjs" "$INSTALL_DIR/smoke/appserver-smoke.cjs" "$INSTALL_DIR/workers/piper.js" 2>/dev/null || true
  chmod 0600 "$INSTALL_DIR/capabilities.json" 2>/dev/null || true
  chmod 0600 "$INSTALL_DIR/appserver"/*.cjs "$INSTALL_DIR/appserver/package.json" "$INSTALL_DIR/lib"/*.js "$INSTALL_DIR/lib-motores"/*.cjs 2>/dev/null || true
  rm -rf -- "$BUNDLE_EXTRACT"
  rm -f -- "$BUNDLE_TMP"
  write_runtime_files_manifest "$INSTALL_DIR"
  echo "   runtime app-server validado e aplicado."

  # Atualizador assinado que preserva o motor Codex: baixado da central (updater_url
  # / updater_sha256 / updater_bytes ja vieram do release-manifest sourced acima),
  # conferido por verify_signed_artifact, bash -n, e um triplo gate de conteudo
  # (sem o flag perigoso, com o alvo appserver-v2 e com verify_release_manifest).
  # O chmod +x fica no bloco compartilhado adiante (nao duplicar aqui).
  echo ">> instalando atualizador que preserva o motor Codex..."
  local DANGEROUS_FLAG UPDATE_TMP
  DANGEROUS_FLAG="--dangerously-bypass-approvals-and-"'sandbox'
  UPDATE_TMP=$(mktemp)
  if ! curl -fsSL --max-filesize "$updater_bytes" --retry 3 --retry-delay 2 --retry-connrefused \
      "$CENTRAL$updater_url" -o "$UPDATE_TMP"; then
    rm -f -- "$UPDATE_TMP"
    echo "ERRO: nao consegui baixar o atualizador da versao Codex." >&2
    echo "sem ele uma atualizacao futura poderia reverter o motor. tente de novo em 1min." >&2
    exit 1
  fi
  if verify_signed_artifact "$UPDATE_TMP" "$updater_sha256" "$updater_bytes" "atualizador" \
     && bash -n "$UPDATE_TMP" 2>/dev/null \
     && ! grep -q -- "$DANGEROUS_FLAG" "$UPDATE_TMP" \
     && grep -q 'leon-codex-appserver-v2.tar.gz' "$UPDATE_TMP" \
     && grep -q 'verify_release_manifest' "$UPDATE_TMP"; then
    cp -f "$UPDATE_TMP" "$INSTALL_DIR/update-pago.sh"
    rm -f -- "$UPDATE_TMP"
  else
    rm -f -- "$UPDATE_TMP"
    echo "ERRO: nao consegui instalar o atualizador da versao Codex." >&2
    echo "sem ele uma atualizacao futura poderia reverter o motor. tente de novo em 1min." >&2
    exit 1
  fi
}

if [ "$MOCK_MODE" != "1" ]; then
  if [ "$LEON_ENGINE" = codex ]; then
    baixa_runtime_codex
  else
    echo ""
    echo ">> validando compra e baixando motor..."
    TARBALL=$(mktemp --suffix=.tar.gz)
    EMAIL_ENC=$(printf %s "$EMAIL" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read().strip()))" 2>/dev/null || printf %s "$EMAIL")
    HTTP_CODE=$(curl -sSL -w "%{http_code}" -o "$TARBALL" "$CENTRAL/download?email=$EMAIL_ENC")
    if [ "$HTTP_CODE" != "200" ]; then
      echo "ERRO: nao consegui validar a compra (HTTP $HTTP_CODE)." >&2
      echo "conteudo:" >&2
      head -c 300 "$TARBALL" >&2
      echo "" >&2
      echo "possiveis causas:" >&2
      echo "  · email diferente do que voce usou na compra (Cakto/Hubla)" >&2
      echo "  · compra ainda nao processada (aguarde 1min e tente de novo)" >&2
      echo "  · reembolso/cancelamento (licenca bloqueada)" >&2
      echo "suporte: https://wa.me/5511961562217" >&2
      rm -f "$TARBALL"
      exit 1
    fi
    # Confere o motor contra o manifesto ASSINADO antes de extrair. Sem isto o instalador
    # extraia o que viesse do cabo, que foi exatamente o buraco do acidente de 12/08. A
    # cadeia e a mesma do Codex: chave publica conferida por fingerprint, manifesto por
    # assinatura Ed25519, artefato por sha256+tamanho (o canario 19/08 rodada 2 pegou o
    # Claude protegido so por hash). Se qualquer elo faltar ou nao bater, para aqui.
    MOTOR_MANIFEST=$(mktemp)
    MOTOR_SIG=$(mktemp)
    MOTOR_PUBKEY=$(mktemp)
    # O -f e obrigatorio: sem ele o curl sai com codigo 0 num 404 e grava o HTML
    # de erro no arquivo, e o instalador acusa "manifesto invalido" quando o
    # problema real e rota faltando no servidor (canario 19/08).
    if ! curl -fsSL --max-filesize 65536 -o "$MOTOR_MANIFEST" "$CENTRAL/release-manifest-claude.json"; then
      echo "ERRO: nao consegui baixar o manifesto do motor." >&2
      rm -f -- "$MOTOR_MANIFEST" "$MOTOR_SIG" "$MOTOR_PUBKEY" "$TARBALL"; exit 1
    fi
    if ! curl -fsSL --max-filesize 64 -o "$MOTOR_SIG" "$CENTRAL/release-manifest-claude.sig"; then
      echo "ERRO: nao consegui baixar a assinatura do manifesto do motor." >&2
      rm -f -- "$MOTOR_MANIFEST" "$MOTOR_SIG" "$MOTOR_PUBKEY" "$TARBALL"; exit 1
    fi
    write_release_public_key "$MOTOR_PUBKEY" || {
      echo "ERRO: chave publica da release nao confere o fingerprint de confianca." >&2
      rm -f -- "$MOTOR_MANIFEST" "$MOTOR_SIG" "$MOTOR_PUBKEY" "$TARBALL"; exit 1; }
    openssl pkeyutl -verify -rawin -pubin -inkey "$MOTOR_PUBKEY" \
      -in "$MOTOR_MANIFEST" -sigfile "$MOTOR_SIG" >/dev/null 2>&1 || {
      echo "ERRO: assinatura do manifesto do motor nao confere — instalacao abortada." >&2
      rm -f -- "$MOTOR_MANIFEST" "$MOTOR_SIG" "$MOTOR_PUBKEY" "$TARBALL"; exit 1; }
    rm -f -- "$MOTOR_SIG" "$MOTOR_PUBKEY"
    MOTOR_META=$(mktemp)
    if ! python3 - "$MOTOR_MANIFEST" "$LEON_RELEASE_TRUST_FINGERPRINT" > "$MOTOR_META" <<'PY'
import json,re,sys
manifest,fingerprint=sys.argv[1:]
try: data=json.load(open(manifest,encoding="utf-8"))
except Exception: raise SystemExit(1)
if data.get("schema")!=1 or data.get("kind")!="leon-claude-motor-release" or data.get("channel")!="stable": raise SystemExit(1)
if data.get("keyFingerprint")!=fingerprint: raise SystemExit(1)
item=data.get("artifacts",{}).get("motor")
if not isinstance(item,dict) or set(item)!={"file","url","sha256","bytes","licensed"}: raise SystemExit(1)
if item["url"]!="/download" or item["licensed"] is not True: raise SystemExit(1)
if not re.fullmatch(r"[0-9a-f]{64}",str(item["sha256"])): raise SystemExit(1)
if not isinstance(item["bytes"],int) or not 1<=item["bytes"]<=536_870_912: raise SystemExit(1)
print("motor_sha256="+item["sha256"]); print("motor_bytes=%d"%item["bytes"])
PY
    then
      echo "ERRO: manifesto do motor invalido — instalacao abortada." >&2
      rm -f -- "$MOTOR_MANIFEST" "$MOTOR_META" "$TARBALL"; exit 1
    fi
    # shellcheck disable=SC1090
    . "$MOTOR_META"
    rm -f -- "$MOTOR_MANIFEST" "$MOTOR_META"
    verify_signed_artifact "$TARBALL" "$motor_sha256" "$motor_bytes" "motor" \
      || { rm -f -- "$TARBALL"; exit 1; }

    echo ">> motor baixado e conferido. instalando em $INSTALL_DIR..."

    mkdir -p "$INSTALL_DIR"
    STAGE=$(mktemp -d)
    tar --no-same-owner --no-same-permissions -xzf "$TARBALL" -C "$STAGE"
    INNER=$(find "$STAGE" -maxdepth 1 -mindepth 1 -type d | head -1)
    if [ -z "$INNER" ]; then
      echo "ERRO: tarball sem conteudo esperado." >&2
      exit 1
    fi
    cp -a "$INNER"/. "$INSTALL_DIR"/
    rm -rf "$STAGE" "$TARBALL"
  fi
  # Atualizador e redes de seguranca precisam ser executaveis (o cron chama direto).
  chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
  chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true

  # Redes de seguranca no cron JA na instalacao. Antes elas so entravam a partir
  # do segundo update, entao o cliente recem-instalado ficava sem nenhuma: se o
  # primeiro /atualiza morresse, ninguem restaurava e ninguem avisava.
  agendar_rede() {  # $1 = script, $2 = periodicidade
    local alvo="$1" quando="$2" cur
    [ -f "$alvo" ] || return 0
    command -v crontab >/dev/null 2>&1 || return 0
    cur="$(crontab -l 2>/dev/null || true)"
    printf %s "$cur" | grep -qF "$alvo" && return 0
    { [ -n "$cur" ] && printf '%s\n' "$cur"; printf '%s %s >/dev/null 2>&1\n' "$quando" "$alvo"; } \
      | crontab - 2>/dev/null || true
  }
  agendar_rede "$INSTALL_DIR/scripts/update-guard.sh"   "*/5 * * * *"
  agendar_rede "$INSTALL_DIR/scripts/update-verdict.sh" "* * * * *"
  # Busca automatica de madrugada: sem isto, a instalacao paga so atualizava
  # quando o dono digitava /atualiza, e quem nunca digitava ficava pra tras.
  # Roda de hora em hora; o proprio script decide se e a hora dele (entre 3h e
  # 5h, horario de Brasilia, sorteada por maquina) e nao fala nada de noite.
  agendar_rede "$INSTALL_DIR/scripts/update-auto.sh"    "13 * * * *"
  agendar_rede "$INSTALL_DIR/scripts/aviso-manha.sh"    "21 * * * *"
  # 24/08: o BACKUP nunca era agendado (casa real auditada: zero backup em disco).
  # Memoria/persona do cliente sem copia = perda total se a VPS morrer.
  agendar_rede "$INSTALL_DIR/scripts/backup-diario.sh"  "40 3 * * *"
  # Banco Postgres `leon` (mesma estrutura do dono): garante agora e importa o
  # estado dos .md 1x/dia. Tolerante a falha: sem postgres, tudo segue igual.
  [ -x "$INSTALL_DIR/scripts/garante-banco.sh" ] && bash "$INSTALL_DIR/scripts/garante-banco.sh" || true
  if [ -f "$INSTALL_DIR/workers/importa-estado-pro-banco.cjs" ]; then
    agendar_rede_node(){ local alvo="$1" quando="$2" cur
      [ -f "$alvo" ] || return 0; command -v crontab >/dev/null 2>&1 || return 0
      cur="$(crontab -l 2>/dev/null || true)"
      printf %s "$cur" | grep -qF "$alvo" && return 0
      { [ -n "$cur" ] && printf '%s
' "$cur"; printf '%s /usr/bin/node %s >/dev/null 2>&1
' "$quando" "$alvo"; }         | crontab - 2>/dev/null || true
    }
    agendar_rede_node "$INSTALL_DIR/workers/importa-estado-pro-banco.cjs" "50 3 * * *"
  fi

  # ------------------------------------------------------------
  # 2.3b Skills do metodo Soft. Repo TRANCADO (so leitura); a chave
  # veio dentro do proprio pacote pago (ja validado por e-mail acima).
  # Sem isso o LEON pago ficava SEM as habilidades do metodo -
  # o motor sozinho nao ensina carrossel, webinario, funil etc.
  # ------------------------------------------------------------
  echo ""
  echo ">> baixando as habilidades do metodo Soft..."
  SKILLS_DIR="$LEON_SKILLS_DIR"
  # Reexecucao numa casa que ja passou pelo /atualiza do Codex: o catalogo assinado
  # (skills-manifest.json, modos 0500/0400) e do atualizador; nao se escreve por cima.
  # O atualizador remove o skills-manifest.json ao selar; o que sobra e o diretorio
  # 0500 (sem escrita pro dono). Qualquer um dos dois sinais = catalogo assinado.
  if [ -f "$SKILLS_DIR/skills-manifest.json" ] || { [ -d "$SKILLS_DIR" ] && [ ! -w "$SKILLS_DIR" ]; }; then
    echo "   catalogo assinado do atualizador ja mora em $SKILLS_DIR; mantido (o proximo /atualiza renova)."
  else
    SKILLS_KEY="$HOME/.ssh/soft-skills-deploy"
    if [ -f "$INSTALL_DIR/keys/agente-soft-skills-deploy" ]; then
      mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
      cp "$INSTALL_DIR/keys/agente-soft-skills-deploy" "$SKILLS_KEY" && chmod 600 "$SKILLS_KEY"
    fi
    SKILLS_SSH="ssh -i $SKILLS_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    FONTE_UNICA_OK=0
    FU_TMP="$(mktemp -d)"
    # FONTE UNICA (lei do dono 05/08): molinateston/soft e a casa das skills atualizadas.
    # Tenta ela primeiro (https publica; senao a chave, se o dono anexou la). Se ainda nao
    # responde, cai no repositorio antigo; instalacao nunca fica sem as skills por isso.
    FU_KEY="$INSTALL_DIR/keys/soft-fonte-unica-deploy"
    FU_SSH="ssh -i $FU_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    if GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 https://github.com/molinateston/soft.git "$FU_TMP/r" 2>/dev/null \
       || { [ -f "$FU_KEY" ] && chmod 600 "$FU_KEY" 2>/dev/null && GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$FU_SSH" git clone -q --depth 1 git@github.com:molinateston/soft.git "$FU_TMP/r" 2>/dev/null; }; then
      FU_SRC="$FU_TMP/r"; [ -d "$FU_TMP/r/skills" ] && FU_SRC="$FU_TMP/r/skills"
      if [ -n "$(find "$FU_SRC" -mindepth 2 -name 'SKILL.md' -print -quit 2>/dev/null)" ]; then
        mkdir -p "$SKILLS_DIR"
        ( cd "$FU_SRC" && tar -c --exclude=.git --exclude=README.md --exclude=.claude-plugin --exclude="LICENSE*" . ) | ( cd "$SKILLS_DIR" && tar -x ) \
          && { git -C "$FU_TMP/r" rev-parse HEAD 2>/dev/null > "$SKILLS_DIR/.fonte-unica-sha" || true; FONTE_UNICA_OK=1; echo "   habilidades instaladas da fonte unica (molinateston/soft)."; }
      fi
    fi
    rm -rf "$FU_TMP"
    if [ "$FONTE_UNICA_OK" -eq 1 ]; then
      :
    elif [ -d "$SKILLS_DIR/.git" ]; then
      CUR_URL="$(git -C "$SKILLS_DIR" remote get-url origin 2>/dev/null || echo '')"
      # FONTE UNICA (23/08, lei do dono): as skills e o plugin saem do MESMO repo (soft).
      # Casa antiga apontando pro repo aposentado e reapontada aqui, no proximo update.
      case "$CUR_URL" in
        *agente-soft-skills*|*molinateston/soft-skills*)
          git -C "$SKILLS_DIR" remote set-url origin git@github-softskills:molinateston/soft.git 2>/dev/null \
            || git -C "$SKILLS_DIR" remote set-url origin https://github.com/molinateston/soft.git 2>/dev/null || true ;;
      esac
      GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$SKILLS_SSH" git -C "$SKILLS_DIR" pull -q --ff-only 2>/dev/null \
        && echo "   habilidades atualizadas." \
        || echo "   (aviso) ja existiam habilidades aqui, mantive como estao."
    else
      if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$SKILLS_SSH" git clone -q git@github.com:molinateston/soft.git "$SKILLS_DIR" 2>/tmp/skills-clone.err; then
        echo "   habilidades instaladas ($(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d ! -name '.git' | wc -l) no total)."
      else
        echo "   (aviso) nao consegui baixar as habilidades agora (sem rede?). O proximo /atualiza tenta de novo."
      fi
    fi
  fi
else
  # MOCK: cria diretorio + package.json + bridge.cjs stub
  mkdir -p "$INSTALL_DIR"
  cat > "$INSTALL_DIR/package.json" <<'JSON'
{ "name": "leon-mock", "version": "0.0.1", "main": "bridge.cjs" }
JSON
  cat > "$INSTALL_DIR/bridge.cjs" <<'JS'
console.log("LEON mock bridge up");
setInterval(() => {}, 60000);
JS
  echo ">> MOCK: motor stub em $INSTALL_DIR"
fi

# HANDOFF do /atualiza (A11): o vigia do cron executa o atualizador que o bridge,
# preso na unit com NoNewPrivileges, so consegue pedir. Vale pros dois motores.
injetar_handoff_update_verdict "$INSTALL_DIR/scripts/update-verdict.sh" || exit 1

cd "$INSTALL_DIR"

# ------------------------------------------------------------
# 2.4 Captura chat_id via Telegram getUpdates (60s + fallback)
# ------------------------------------------------------------
OWNER_CHAT_ID="${OWNER_CHAT_ID:-}"
# Reexecucao na mesma casa (dono rodou o instalador de novo depois de um tropeco):
# o .env anterior ja diz quem e o dono deste bot. Pedir a frase de novo, com o
# servico parado, deixou cliente sem LEON por 5 minutos e abortou (23/08).
if ! printf %s "$OWNER_CHAT_ID" | grep -qE '^-?[1-9][0-9]*$' && [ -f "$INSTALL_DIR/.env" ]; then
  _dono_antigo="$(sed -n 's/^OWNER_CHAT_ID=//p' "$INSTALL_DIR/.env" | head -1)"
  _bot_antigo="$(sed -n 's/^TELEGRAM_BOT_TOKEN=//p; s/^BOT_TOKEN=//p' "$INSTALL_DIR/.env" | head -1)"
  if printf %s "$_dono_antigo" | grep -qE '^-?[1-9][0-9]*$' && [ "$_bot_antigo" = "$BOT_TOKEN" ]; then
    OWNER_CHAT_ID="$_dono_antigo"
    echo ">> proprietario ja vinculado nesta casa (mesmo bot): chat_id=$OWNER_CHAT_ID"
  fi
  unset _dono_antigo _bot_antigo
fi
if printf %s "$OWNER_CHAT_ID" | grep -qE '^-?[1-9][0-9]*$'; then
  echo ">> proprietario recebido de forma explicita: chat_id=$OWNER_CHAT_ID"
elif [ "$MOCK_MODE" = "1" ]; then
  OWNER_CHAT_ID="999999"
  echo ">> MOCK: OWNER_CHAT_ID=999999"
else
  NONCE="LEON-$(python3 -c 'import secrets; print(secrets.token_hex(3).upper())')"
  echo ""
  echo "========================================"
  echo "  ULTIMO PASSO — vincular teu Telegram"
  echo "========================================"
  echo "Abre uma conversa PRIVADA com o bot (o que você acabou de criar no @BotFather) e manda exatamente: $NONCE"
  echo "(copie a frase acima; sem pressa — você tem 5 minutos)"
  echo "Essa frase unica impede outra pessoa de capturar teu LEON."
  echo "Vou esperar por ate 5 minutos (sem pressa: abra o Telegram, ache o SEU bot e cole a frase)."
  echo ""

  # CAPTURA MODELADA NO INSTALADOR DO OUTRO MOTOR + frase de seguranca (17/08). O bloco anterior tinha
  # um python que NAO COMPILAVA (recuo errado no 'pass'): a captura NUNCA funcionou, o erro era engolido
  # e a instalacao dizia "nao recebi a frase" toda vez. Agora: (1) DRENA a fila antiga por offset (frases
  # de tentativas anteriores tem codigo velho, sao lixo e escondiam a nova); (2) le a cada volta com
  # offset avancado (a fila nao recresce nem reprocessa); (3) aceita mensagem E mensagem editada, e casa
  # a frase por conteudo, sem exigir texto exato (colar com texto junto, ou o teclado capitalizando,
  # funciona). A frase continua obrigatoria: e ela que impede outra pessoa de capturar o bot.
  OFFSET_Q="getUpdates"
  DRAIN_FILE=$(mktemp)
  if telegram_api_get_file "$BOT_TOKEN" 'getUpdates' "$DRAIN_FILE" 10; then
    LAST_ID=$(python3 -c '
import json, sys
try:
    r = json.load(open(sys.argv[1], encoding="utf-8")).get("result", [])
    ids = [u.get("update_id") for u in r if isinstance(u.get("update_id"), int)]
    print(max(ids) if ids else "")
except Exception:
    print("")
' "$DRAIN_FILE" 2>/dev/null || true)
    if printf %s "$LAST_ID" | grep -qE '^[0-9]+$'; then OFFSET_Q="getUpdates?offset=$((LAST_ID + 1))"; fi
  fi
  rm -f -- "$DRAIN_FILE"

  for _ in $(seq 1 150); do
    UPDATES_FILE=$(mktemp)
    telegram_api_get_file "$BOT_TOKEN" "$OFFSET_Q" "$UPDATES_FILE" 10 || printf '{}\n' > "$UPDATES_FILE"
    CAPTURA=$(python3 -c '
import json, sys
nonce = sys.argv[1].strip().upper()
chat_id = ""
last_id = -1
try:
    data = json.load(open(sys.argv[2], encoding="utf-8"))
    for update in data.get("result", []):
        uid = update.get("update_id")
        if isinstance(uid, int) and uid > last_id:
            last_id = uid
        msg = update.get("message") or update.get("edited_message") or {}
        chat = msg.get("chat") or {}
        text = str(msg.get("text", "")).upper()
        if chat.get("type") == "private" and nonce and nonce in text:
            chat_id = chat.get("id", "")
except Exception:
    pass
print("%s|%s" % (chat_id, last_id if last_id >= 0 else ""))
' "$NONCE" "$UPDATES_FILE" 2>/dev/null || printf '|')
    rm -f -- "$UPDATES_FILE"
    CHAT_ID=$(printf %s "$CAPTURA" | cut -d'|' -f1)
    NOVO_ID=$(printf %s "$CAPTURA" | cut -d'|' -f2)
    if printf %s "$NOVO_ID" | grep -qE '^[0-9]+$'; then OFFSET_Q="getUpdates?offset=$((NOVO_ID + 1))"; fi
    if printf %s "$CHAT_ID" | grep -qE '^-?[1-9][0-9]*$'; then
      OWNER_CHAT_ID="$CHAT_ID"
      echo ">> Telegram vinculado com seguranca: chat_id=$OWNER_CHAT_ID"
      break
    fi
    sleep 2
  done

  if ! printf %s "$OWNER_CHAT_ID" | grep -qE '^-?[1-9][0-9]*$'; then
    echo "ERRO: nao recebi a frase de vinculacao. Nada foi sobrescrito e o servico antigo continua no ar." >&2
    echo "Rode o instalador de novo e envie a frase mostrada na tela." >&2
    exit 1
  fi
fi

# ------------------------------------------------------------
# 2.5 .env do cliente
# ------------------------------------------------------------
cat > .env <<EOF
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
OWNER_CHAT_ID=$OWNER_CHAT_ID
LEON_LICENSE_EMAIL=$EMAIL
LEON_LICENSE_CENTRAL=$CENTRAL
LEON_MACHINE_ID=$MACHINE_ID
AGENT_NAME=$NOME
AGENT_GENDER=$GENDER
ENGINE=$LEON_ENGINE
ENGINE_DEFAULT=$LEON_ENGINE
TTS_PROVIDER=edgetts
VOICE_REPLY=mirror
VOICE_PY=$LEON_DATA_DIR/whisper-venv/bin/python3
EOF
chmod 600 .env

# RAMO C: motor Codex ganha .env estendido + dirs de dados. Mesmo conjunto de
# chaves que o install-codex.sh gravava e que o update-pago-codex.sh regrava:
# CODEX_BIN e o binario PINADO (unico caminho que o bridge aceita),
# LEON_CODEX_CLI_VERSION cravada, CODEX_MODEL = o que respondeu na prova (A8).
# O motor Claude nao precisa dessas chaves, entao so o codex entra aqui.
if [ "$LEON_ENGINE" = codex ]; then
  CODEX_BIN_ENV="${LEON_CODEX_BIN_RESOLVED:-$LEON_DATA_DIR/codex-cli/releases/$LEON_CODEX_CLI_VERSION/bin/codex}"
  cat >> .env <<EOF
LEON_CODEX_ONLY=1
CODEX_APP_SERVER=1
CODEX_HOME=$LEON_CODEX_HOME
CODEX_BIN=$CODEX_BIN_ENV
CODEX_MODEL=$CODEX_MODEL
CODEX_REASONING_EFFORT=high
LEON_CODEX_CLI_VERSION=$LEON_CODEX_CLI_VERSION
LEON_DATA_DIR=$LEON_DATA_DIR
BRAIN_DIR=$LEON_DATA_DIR/brain
PERSONA_DIR=$LEON_DATA_DIR/persona
LEON_SKILLS_DIR=$LEON_SKILLS_DIR
LEON_TMPDIR=$LEON_TMPDIR
LEON_WORK_AREA=$LEON_WORK_AREA
LEON_STATE_DIR=$LEON_STATE_DIR
LEON_MISSIONS_DIR=$LEON_MISSIONS_DIR
LEON_PROMISES_DIR=$LEON_PROMISES_DIR
LEON_MISSION_OUTPUT_DIR=$LEON_MISSION_OUTPUT_DIR
WORK_DIR=$INSTALL_DIR
VOICE_HANDLER=$INSTALL_DIR/workers/voice-handler.py
EDGE_TTS_WORKER=$INSTALL_DIR/workers/edge-tts.js
EDGE_TTS_PY=$LEON_DATA_DIR/edgetts-venv/bin/python3
PIPER_WORKER=$INSTALL_DIR/workers/piper.js
PIPER_BIN=$LEON_DATA_DIR/piper-venv/bin/piper
PIPER_MODEL=$LEON_DATA_DIR/voices/piper/pt_BR-faber-medium.onnx
MEMVIVA_FILE=$LEON_DATA_DIR/brain/MEMORIA-VIVA.md
ASSUNTOS_FILE=$LEON_DATA_DIR/brain/ASSUNTOS-VIVOS.md
EOF
  chmod 600 .env
  mkdir -p "$LEON_CODEX_HOME" "$LEON_TMPDIR" "$LEON_DATA_DIR/brain" \
    "$LEON_DATA_DIR/persona" "$LEON_WORK_AREA" "$LEON_STATE_DIR" "$LEON_MISSIONS_DIR" \
    "$LEON_PROMISES_DIR" "$LEON_MISSION_OUTPUT_DIR"
  chmod 700 "$LEON_DATA_DIR" "$LEON_CODEX_HOME" "$LEON_TMPDIR" "$LEON_STATE_DIR" "$LEON_MISSION_OUTPUT_DIR"
  # Perfil dedicado do LEON: o motor escreve apenas nas areas de trabalho,
  # nao enxerga arquivos de credencial e so acessa destinos de rede aprovados.
  cat > "$LEON_CODEX_HOME/config.toml" <<EOF
model = "$CODEX_MODEL"
model_reasoning_effort = "high"
preferred_auth_method = "chatgpt"
approval_policy = "never"
default_permissions = "leon"
allow_login_shell = false

[projects."$INSTALL_DIR"]
trust_level = "untrusted"

[projects."$LEON_WORK_AREA"]
trust_level = "trusted"

[permissions.leon]
description = "LEON: leitura mínima e escrita apenas em diretórios de dados explícitos."

[permissions.leon.workspace_roots]
"$LEON_WORK_AREA" = true
"$LEON_DATA_DIR/brain" = true
"$LEON_TMPDIR" = true
"$LEON_MISSION_OUTPUT_DIR" = true

[permissions.leon.filesystem]
glob_scan_max_depth = 4
":root" = "deny"
":minimal" = "read"
"$LEON_DATA_DIR/codex-cli" = "read"
# 26/08: rede ligada exige DNS — sem estes dois em leitura, o resolv morre e a rede "ligada"
# continua inútil (medido na auditoria: TCP pra IP direto passa, nome de domínio falha).
"/etc/resolv.conf" = "read"
"/etc/hosts" = "read"
"$LEON_SKILLS_DIR" = "read"
"$LEON_WORK_AREA" = "write"
"$LEON_DATA_DIR/brain" = "write"
"$LEON_TMPDIR" = "write"
"$LEON_MISSION_OUTPUT_DIR" = "write"

[permissions.leon.filesystem.":workspace_roots"]
"." = "read"
".env" = "deny"
"**/.env" = "deny"
"**/.env.*" = "deny"
"keys" = "deny"
"keys/**" = "deny"

[permissions.leon.network]
# 26/08 (lei do dono): Vercel, Zernio e afins são APIs BÁSICAS DO USO — o agente precisa de
# rede pros comandos dele (curl, CLIs de deploy). O cofre de credenciais só faz sentido com
# isto ligado. Raiz negada e filtros de env seguem valendo.
enabled = true

# Knob OFICIAL do Codex: sandbox workspace-write bloqueia rede por padrão; sem esta seção,
# o enabled acima não basta.
[sandbox_workspace_write]
network_access = true

[features]
multi_agent_v2 = false

[agents]
enabled = true
max_concurrent_threads_per_session = 2
default_subagent_reasoning_effort = "low"

[agents."braco-conteudo"]
description = "Conteudo: carrossel, reel, stories, headline, calendario, post."
config_file = "$INSTALL_DIR/.codex/agents/braco-conteudo.toml"
nickname_candidates = ["conteudo"]

[agents."braco-funil"]
description = "Funil: carta/VSL, landing, isca, webinario, lancamento, captura."
config_file = "$INSTALL_DIR/.codex/agents/braco-funil.toml"
nickname_candidates = ["funil"]

[agents."braco-vendas"]
description = "Vendas: script, objecao, fechamento, prospeccao, pipeline, pos-venda."
config_file = "$INSTALL_DIR/.codex/agents/braco-vendas.toml"
nickname_candidates = ["vendas"]

[agents."braco-financeiro"]
description = "Financeiro: contas, saldo, conciliacao, cobranca, relatorio."
config_file = "$INSTALL_DIR/.codex/agents/braco-financeiro.toml"
nickname_candidates = ["financeiro"]

[agents."braco-advogado"]
description = "Juridico: contrato, clausula, risco legal, LGPD, revisao de termo."
config_file = "$INSTALL_DIR/.codex/agents/braco-advogado.toml"
nickname_candidates = ["advogado"]

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
  chmod 600 "$LEON_CODEX_HOME/config.toml"
fi

# ------------------------------------------------------------
# 2.6 Ativa licenca no central
# ------------------------------------------------------------
if [ "$MOCK_MODE" != "1" ]; then
  echo ""
  echo ">> ativando licenca..."
  RESP=$(curl -fsS -X POST "$CENTRAL/activate" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"machine_id\":\"$MACHINE_ID\"}" || echo '{"ok":false,"code":"sem_conexao"}')
  echo "$RESP"
  if ! printf %s "$RESP" | grep -q '"ok":true'; then
    echo "ATENCAO: ativacao no central falhou. motor instalado mas nao ativou."
    echo "se for machine_mismatch: essa chave ja foi ativada em outra VPS."
    echo "suporte: https://wa.me/5511961562217"
  fi
fi

# ------------------------------------------------------------
# 2.7 npm install (opcional: motor atual so usa modulos nativos)
# Codex nunca roda npm: o runtime de release usa so modulos nativos e o
# pacote curado nao traz package.json com dependencia. Claude usa o npm do
# sistema, com o PATH limpo.
# ------------------------------------------------------------
if [ "$MOCK_MODE" != "1" ] && [ "$LEON_ENGINE" = codex ]; then
  echo ">> motor Codex: sem npm install (runtime so com modulos nativos)."
elif [ "$MOCK_MODE" != "1" ] && [ -f package.json ]; then
  echo ""
  echo ">> instalando dependencias..."
  PATH="$SYS_PATH" /usr/bin/npm install --no-audit --no-fund
elif [ "$MOCK_MODE" != "1" ]; then
  echo ""
  echo ">> motor sem package.json (so modulos nativos), pulando npm install."
fi

# ------------------------------------------------------------
# 2.8 systemd system service (criado na fase root, agora e so subir)
# ------------------------------------------------------------
SERVICE_NAME="leon-agente.service"

if [ "$MOCK_MODE" != "1" ]; then
  if [ ! -f /etc/systemd/system/$SERVICE_NAME ]; then
    echo "ERRO: /etc/systemd/system/$SERVICE_NAME nao existe (fase root nao rodou?)." >&2
    exit 1
  fi

  sudo -n /bin/systemctl enable --now $SERVICE_NAME

  sleep 3
  if sudo -n /bin/systemctl is-active $SERVICE_NAME >/dev/null; then
    echo ""
    echo "========================================"
    echo "  INSTALADO COM SUCESSO"
    echo "========================================"
    echo ""
    echo "Teu LEON esta rodando em $INSTALL_DIR"
    echo "Servico: sudo systemctl status $SERVICE_NAME"
    echo "Log: sudo journalctl -u $SERVICE_NAME -f"
    echo ""
    echo "Manda uma mensagem no teu bot pelo Telegram pra testar."
    echo ""
  else
    echo ""
    echo "ATENCAO: o servico subiu mas nao ficou ativo."
    echo "veja: sudo journalctl -u $SERVICE_NAME -n 50"
  fi
else
  # MOCK: bancada seca. NUNCA dizer "INSTALADO COM SUCESSO" aqui: esse verde seco
  # ja fez quem testava achar que tinha validado justamente o download+verificacao
  # que quebrou a frota em 12/08. O resumo diz na cara o que rodou e o que nao rodou.
  if command -v node >/dev/null 2>&1; then
    node --check "$INSTALL_DIR/bridge.cjs" || { echo "ERRO: stub bridge.cjs nao compila." >&2; exit 1; }
  fi
  echo ""
  echo "=================================================="
  echo "  BANCADA MOCK CONCLUIDA (exit 0)"
  echo "  ISTO NAO E UMA INSTALACAO VALIDADA"
  echo "=================================================="
  echo ""
  echo "O que o mock EXERCITOU:"
  echo "  · validacao das env vars obrigatorias (EMAIL/NOME/GENDER/BOT_TOKEN)"
  echo "  · machine_id"
  echo "  · stub do motor + .env em $INSTALL_DIR"
  echo "  · fluxo do script do inicio ao fim sem erro de shell"
  echo ""
  echo "O que o mock NAO exercitou (rodou ZERO disso):"
  echo "  · download do motor no central ($CENTRAL/download)"
  echo "  · VERIFICACAO manifesto+sha256 do motor (a parte que quebrou em 12/08)"
  echo "  · extracao do tarball real e skills do metodo Soft"
  echo "  · login no motor (OAuth) e ativacao da licenca"
  echo "  · captura real do Telegram (chat_id mockado=999999)"
  echo "  · apt/node/CLI do motor, voz (Piper/Edge/faster-whisper) e tomli"
  echo "  · runtime dedicado do Codex (Node/Codex CLI pinados), login e prova do modelo"
  echo "  · usuario dedicado, unit systemd e sudoers (NAO foram criados nesta maquina)"
  echo ""
  echo "Validacao de verdade: rodar SEM MOCK_MODE numa VPS descartavel."
  echo "Limpar esta bancada: rm -rf $INSTALL_DIR"
  echo ""
fi
