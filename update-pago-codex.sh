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
    if not re.fullmatch(r"0|[1-9]\d*(?:\.(?:0|[1-9]\d*)){2}", value): raise SystemExit(2)
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
if data["codexCliVersion"]!="0.147.0" or data["nodeVersion"]!="22.22.0": raise SystemExit(1)
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

# Bash le scripts por offset. Uma copia fora do runtime impede que o rename da
# instalacao altere o arquivo que esta sendo executado.
if [ "$FINALIZE_MODE" -eq 0 ] && [ -z "${LEON_UPDATE_BLINDADO:-}" ]; then
  SAFE_COPY="$(mktemp "${TMPDIR:-/tmp}/leon-update.XXXXXX")"
  cp -- "$SCRIPT_PATH" "$SAFE_COPY"
  chmod 0700 "$SAFE_COPY"
  export LEON_UPDATE_BLINDADO=1
  export LEON_INSTALL_DIR="${LEON_INSTALL_DIR:-$SELF}"
  export LEON_UPDATE_COPIA="$SAFE_COPY"
  exec /usr/bin/env bash "$SAFE_COPY" "$@"
fi

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

env_get_from() {
  local file="$1" key="$2"
  grep -E "^${key}=" "$file" 2>/dev/null | tail -1 | cut -d= -f2- \
    | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//' \
    || true
}

# Lê uma única chave do .env pelo mesmo fd validado. Notificações e smokes
# acontecem depois de renames; nunca voltamos a abrir o caminho com grep, nem
# deixamos uma cópia temporária contendo o token em caso de sinal/crash.
safe_env_value() {
  local file="$1" key="$2"
  "$PYTHON_BIN" - "$file" "$key" <<'PY'
import os,re,stat,sys
path,key=sys.argv[1:]
if not re.fullmatch(r"[A-Z][A-Z0-9_]*",key): raise SystemExit(1)
seen=os.lstat(path)
if not stat.S_ISREG(seen.st_mode) or stat.S_ISLNK(seen.st_mode) or seen.st_nlink!=1 \
   or seen.st_uid!=os.getuid() or stat.S_IMODE(seen.st_mode)&0o077 or seen.st_size>256*1024:
    raise SystemExit(1)
fd=os.open(path,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0))
try:
    before=os.fstat(fd)
    raw=os.read(fd,before.st_size+1)
    after=os.fstat(fd)
finally: os.close(fd)
if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or before.st_dev!=seen.st_dev \
   or before.st_ino!=seen.st_ino or after.st_dev!=before.st_dev or after.st_ino!=before.st_ino \
   or after.st_nlink!=1 or after.st_size!=before.st_size or len(raw)!=before.st_size:
    raise SystemExit(1)
text=raw.decode("utf-8")
found=None; keys=set()
for line in text.splitlines():
    if not line.strip() or line.lstrip().startswith("#"): continue
    match=re.fullmatch(r"\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*",line)
    if not match or match.group(1) in keys: raise SystemExit(1)
    name,value=match.groups(); keys.add(name)
    if name==key: found=value
if found is None: raise SystemExit(1)
sys.stdout.write(found)
PY
}

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
if m["schema"]!=2 or m["kind"]!="leon-codex-minimal-skills" or m["skills"]!=["soft-critico-copy","soft-designer"] or m["skill_count"]!=2: raise SystemExit(1)
if m["placeholders"]!={"@@LEON_SKILLS_DIR@@":"absolute read-only skills directory","@@LEON_WORK_AREA@@":"absolute user work directory"}: raise SystemExit(1)
if m["capabilities"]!={"connectors_required":False,"credentials_collected_in_chat":False,"designer_output":"self-contained HTML attachment","dynamic_dependency_install":False,"network_required":False}: raise SystemExit(1)
if m["source"]!={"commit":"35a8ee976ff079396b26ce1bc19919b1f8c1a05f","dirty":False,"repository":"https://github.com/molinateston/soft.git"}: raise SystemExit(1)
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
  "MemoryHigh":"80%","MemoryMax":"90%","NoNewPrivileges":"true",
 }
 for key,value in required.items(): one(key,value)
except Exception: raise SystemExit(1)
PY
}

prepare_smoke_codex_home() {
  local source_home="$1" config_candidate="$2" destination="$3"
  "$PYTHON_BIN" - "$source_home" "$config_candidate" "$destination" <<'PY'
import os,stat,sys
source_home,config,destination=map(os.path.abspath,sys.argv[1:])
def safe_read(path,cap,owner):
 seen=os.lstat(path)
 if not stat.S_ISREG(seen.st_mode) or seen.st_nlink!=1 or seen.st_size>cap: raise ValueError()
 if seen.st_uid!=owner or stat.S_IMODE(seen.st_mode)&0o077: raise ValueError()
 fd=os.open(path,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0))
 try: before=os.fstat(fd); raw=os.read(fd,cap+1); after=os.fstat(fd)
 finally: os.close(fd)
 if (seen.st_dev,seen.st_ino)!=(before.st_dev,before.st_ino): raise ValueError()
 if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or len(raw)!=before.st_size: raise ValueError()
 if (before.st_dev,before.st_ino,before.st_size)!=(after.st_dev,after.st_ino,after.st_size) or after.st_nlink!=1: raise ValueError()
 return raw
uid=os.getuid()
auth=safe_read(os.path.join(source_home,"auth.json"),2*1024*1024,uid)
cfg=safe_read(config,256*1024,uid)
if os.path.lexists(destination): raise ValueError()
os.mkdir(destination,0o700)
for name,raw in (("auth.json",auth),("config.toml",cfg)):
 path=os.path.join(destination,name)
 fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,"O_NOFOLLOW",0),0o600)
 try: os.write(fd,raw); os.fsync(fd)
 finally: os.close(fd)
dirfd=os.open(destination,os.O_RDONLY|getattr(os,"O_DIRECTORY",0)|getattr(os,"O_NOFOLLOW",0))
try: os.fsync(dirfd)
finally: os.close(dirfd)
PY
}

# BAIXA COM ESPELHO (23/08, lei do dono: "o LEON deles deveria atualizar independente").
# A central do dono era ponto unico de falha: VPS fora = frota inteira sem atualizar,
# inclusive quem paga. Agora: tenta a central; se ela nao responde, cai pro espelho
# publico no GitHub. A SEGURANCA NAO MUDA: todo artefato e conferido por sha256 e pelo
# manifesto assinado depois do download, venha de onde vier. O que exige licenca (a base
# do produto) continua SO na central: o espelho serve apenas o que ja e livre.
LEON_ESPELHO="${LEON_ESPELHO:-https://raw.githubusercontent.com/molinateston/leon-espelho/main}"
baixa_com_espelho() {  # baixa_com_espelho <caminho-na-central> <destino> <max-bytes>
  local rel="$1" dest="$2" max="$3"
  if curl -fsSL --max-filesize "$max" --retry 2 --retry-delay 2 --retry-connrefused \
      --max-time 180 "$CENTRAL$rel" -o "$dest" 2>/dev/null; then
    return 0
  fi
  # central fora: o espelho publico assume. O nome do arquivo e o mesmo dos dois lados.
  local nome="${rel##*/}"
  if [ -n "$nome" ] && curl -fsSL --max-filesize "$max" --retry 2 --retry-delay 2 \
      --max-time 180 "$LEON_ESPELHO/$nome" -o "$dest" 2>/dev/null; then
    say "   (a central nao respondeu; peguei do espelho publico)"
    return 0
  fi
  return 1
}

run_candidate_model_smoke() {
  local live="$1" tx="$2" status=0
  [ "$TEST_MODE" != "1" ] || return 0
  MODEL_SMOKE_HOME="$(mktemp -d "$LEON_TMPDIR/.codex-home-smoke-$TX_ID.XXXXXX")"
  rmdir -- "$MODEL_SMOKE_HOME"
  MODEL_SMOKE_DIR="$LEON_WORK_AREA/.leon-update-smoke-$TX_ID"
  MODEL_SMOKE_OUT="$(mktemp "$LEON_TMPDIR/.appserver-smoke-$TX_ID.XXXXXX")"
  prepare_smoke_codex_home "$CODEX_HOME_DIR" "$tx/config.candidate" "$MODEL_SMOKE_HOME" || status=1
  if [ "$status" -eq 0 ]; then
    mkdir -m 0700 "$MODEL_SMOKE_DIR"
    if ! PATH="$(dirname "$NODE_BIN"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
      CODEX_HOME="$MODEL_SMOKE_HOME" LEON_CODEX_HOME="$MODEL_SMOKE_HOME" CODEX_BIN="$CODEX_BIN_PATH" \
      CODEX_MODEL="${CODEX_MODEL_EFETIVO:-gpt-5.6-sol}" LEON_RUNTIME_DIR="$live" LEON_SMOKE_DIR="$MODEL_SMOKE_DIR" \
      "$NODE_BIN" "$live/smoke/appserver-smoke.cjs" >"$MODEL_SMOKE_OUT" 2>&1; then
      status=1
    elif ! "$PYTHON_BIN" - "$MODEL_SMOKE_OUT" "${CODEX_MODEL_EFETIVO:-gpt-5.6-sol}" <<'PY'
import json,sys
try:
 lines=[line for line in open(sys.argv[1],encoding="utf-8") if line.strip()]
 data=json.loads(lines[-1])
 if data!={"ok":True,"persistentSession":True,"model":sys.argv[2]}: raise ValueError()
except Exception: raise SystemExit(1)
PY
    then status=1
    fi
  fi
  rm -rf -- "$MODEL_SMOKE_HOME" "$MODEL_SMOKE_DIR"
  rm -f -- "$MODEL_SMOKE_OUT"
  MODEL_SMOKE_HOME=""; MODEL_SMOKE_DIR=""; MODEL_SMOKE_OUT=""
  return "$status"
}

normalize_agent_base() {
  local agent_base="$1" skills_dir="$2"
  [ -f "$agent_base" ] || return 0
  "$PYTHON_BIN" - "$agent_base" "$skills_dir" "$INSTALL_DIR" "$LEON_TMPDIR" "$CODEX_HOME_DIR" \
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

filter_user_env() {
  local source="$1" destination="$2"
  "$PYTHON_BIN" - "$source" "$destination" <<'PY'
import os,re,sys
source,destination=sys.argv[1:]
allowed={
 "TELEGRAM_BOT_TOKEN","OWNER_CHAT_ID","GROUP_CHAT_ID","ALLOWED_SENDERS",
 "LEON_LICENSE_EMAIL","LEON_LICENSE_CENTRAL","LEON_MACHINE_ID","AGENT_NAME","AGENT_GENDER",
 "EDGE_TTS_VOICE","TTS_VOICE","TTS_MODEL",
 "ELEVENLABS_API_KEY","ELEVENLABS_VOICE_ID","ELEVENLABS_MODEL_ID","ELEVENLABS_STABILITY",
 "ELEVENLABS_SIMILARITY","ELEVENLABS_STYLE","HOSTINGER_API_TOKEN","HOSTINGER_VM_ID",
 "DEBOUNCE_MS","DEBOUNCE_MAX","MAX_CONCURRENT","MAX_FILE_MB","MISSAO_CAP_MIN",
 "MISSAO_STALL_MIN","MISSAO_MAX_RETRIES","MISSAO_RETAIN_DAYS",
 "MISSAO_GATE_MIN","TMP_RETENTION_MS","MEMVIVA_READ_MAX",
 "MEMVIVA_ROTATE_AT","ASSUNTOS_READ_MAX","HEARTBEAT_SEG","AVISO_PESADA_SEG","DRAIN_SEG","TZ",
}
selected=[]; seen=set()
for line in open(source,encoding="utf-8").read().splitlines():
    if not line.strip() or line.lstrip().startswith("#"): continue
    match=re.fullmatch(r"\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*",line)
    if not match or match.group(1) in seen: raise SystemExit(1)
    key,value=match.groups(); seen.add(key)
    if key in allowed:
        if any(ch in value for ch in "\r\n\x00") or len(value)>8192: raise SystemExit(1)
        selected.append(f"{key}={value}\n")
temp=destination+".allow-new"
fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,"O_NOFOLLOW",0),0o600)
try: os.write(fd,"".join(selected).encode()); os.fsync(fd)
finally: os.close(fd)
os.replace(temp,destination)
PY
}

rewrite_runtime_env() {
  local env_file="$1" temp
  temp="${env_file}.managed-new"
  # Preserva o modelo já validado no login (a prova pós-login testa em ordem
  # e grava o que respondeu): a conta ChatGPT do cliente pode não ter o "sol",
  # e o update não pode voltar pro default sobrescrevendo o que já funciona.
  local codex_model="${CODEX_MODEL_EFETIVO:-gpt-5.6-sol}" existing_model
  if existing_model="$(safe_env_value "$env_file" CODEX_MODEL 2>/dev/null)" \
    && printf '%s' "$existing_model" | grep -qE '^[A-Za-z0-9._-]+$'; then
    codex_model="$existing_model"
  fi
  filter_user_env "$env_file" "$temp" || return 1
  cat >> "$temp" <<EOF
ENGINE=codex
ENGINE_DEFAULT=codex
LEON_CODEX_ONLY=1
CODEX_APP_SERVER=1
CODEX_HOME=$CODEX_HOME_DIR
CODEX_MODEL=$codex_model
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
VOICE_PY=$LEON_DATA_DIR/whisper-venv/bin/python3
EDGE_TTS_WORKER=$INSTALL_DIR/workers/edge-tts.js
EDGE_TTS_PY=$LEON_DATA_DIR/edgetts-venv/bin/python3
PIPER_WORKER=$INSTALL_DIR/workers/piper.js
PIPER_BIN=$LEON_DATA_DIR/piper-venv/bin/piper
PIPER_MODEL=$LEON_DATA_DIR/voices/piper/pt_BR-faber-medium.onnx
MEMVIVA_FILE=$LEON_DATA_DIR/brain/MEMORIA-VIVA.md
ASSUNTOS_FILE=$LEON_DATA_DIR/brain/ASSUNTOS-VIVOS.md
CODEX_BIN=$CODEX_BIN_PATH
TTS_PROVIDER=edgetts
VOICE_REPLY=mirror
EOF
  chmod 0600 "$temp"
  mv -f -- "$temp" "$env_file"
}

# O vigia (scripts/update-verdict.sh) vem do pacote-base e e trocado a cada update; o
# handoff do /atualiza (bridge sob NoNewPrivileges nao dispara o updater, o cron dispara)
# precisa ser regravado no stage toda vez, senao o proximo /atualiza volta a morrer.
injetar_handoff_update_verdict() {
  local vigia="$1" tmp
  [ -f "$vigia" ] || return 0
  if grep -q 'LEON-HANDOFF-UPDATE v1' "$vigia"; then
    return 0
  fi
  tmp="$vigia.leon-new"
  python3 - "$vigia" "$tmp" <<'PY' || { rm -f -- "$tmp"; return 1; }
import os, re, sys
src, dst = sys.argv[1:]
text = open(src, encoding="utf-8").read()
bloco = r'''# --- LEON-HANDOFF-UPDATE v1 (gravado pelo instalador e pelo atualizador) ------------------
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
    return 1
  fi
  mv -f -- "$tmp" "$vigia"
}

write_codex_config_candidate() {
  local destination="$1"
  cat > "$destination" <<EOF
model = "${CODEX_MODEL_EFETIVO:-gpt-5.6-sol}"
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
description = "LEON: raiz negada e acesso somente a diretórios explícitos."

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
multi_agent_v2 = true

[agents]
enabled = true
max_concurrent_threads_per_session = 2
default_subagent_reasoning_effort = "low"

[agents."braco_conteudo"]
description = "Conteudo: carrossel, reel, stories, headline, calendario, post."
config_file = "$INSTALL_DIR/.codex/agents/braco_conteudo.toml"
nickname_candidates = ["conteudo"]

[agents."braco_funil"]
description = "Funil: carta/VSL, landing, isca, webinario, lancamento, captura."
config_file = "$INSTALL_DIR/.codex/agents/braco_funil.toml"
nickname_candidates = ["funil"]

[agents."braco_vendas"]
description = "Vendas: script, objecao, fechamento, prospeccao, pipeline, pos-venda."
config_file = "$INSTALL_DIR/.codex/agents/braco_vendas.toml"
nickname_candidates = ["vendas"]

[agents."braco_financeiro"]
description = "Financeiro: contas, saldo, conciliacao, cobranca, relatorio."
config_file = "$INSTALL_DIR/.codex/agents/braco_financeiro.toml"
nickname_candidates = ["financeiro"]

[agents."braco_advogado"]
description = "Juridico: contrato, clausula, risco legal, LGPD, revisao de termo."
config_file = "$INSTALL_DIR/.codex/agents/braco_advogado.toml"
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
  # Preserva a conexão Meta (meta-connect): se o dono já conectou, o bloco MCP re-entra no
  # candidate. Sem isto, TODO update regenerava o config.toml do template e desconectava o
  # Meta em silêncio (achado da auditoria 26/08). MODO-FILTRO (idêntico ao que
  # lib/meta-connect.js:writeMcpConfig gera): o Codex spawna o filtro local
  # meta-mcp-codex-filter.cjs, que aplica a allowlist de leitura (5 ads_insights_*) e lê o
  # token DIRETO do .meta-token.json — por isso NÃO há bearer_token_env_var nem url-crua. A
  # url-crua expunha os 106 tools da Meta (incl. escrita) e cada /atualiza a regravava, matando
  # o filtro instalado pelo meta-connect (achado Fable 30/08).
  if [ -f "$INSTALL_DIR/.meta-token.json" ]; then
    cat >> "$destination" <<METAEOF

[mcp_servers.meta-ads]
command = "node"
args = ["$INSTALL_DIR/lib/meta-mcp-codex-filter.cjs"]
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
profile=data.get("permissions",{}).get("leon",{})
filesystem=profile.get("filesystem",{})
if data.get("approval_policy")!="never" or data.get("default_permissions")!="leon": raise SystemExit(1)
if filesystem.get(":root")!="deny" or filesystem.get(":minimal")!="read": raise SystemExit(1)
if "sandbox_mode" in data: raise SystemExit(1)
# 26/08 (lei do dono: APIs basicas do uso): rede LIGADA e permitida — mas SO ela.
# sandbox_workspace_write aceito com exatamente {"network_access": true}; qualquer outra
# chave nessa secao (writable_roots etc.) continua proibida — rede nao afrouxa filesystem.
sww=data.get("sandbox_workspace_write")
if sww is not None and sww!={"network_access": True}: raise SystemExit(1)
PY
}

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

restore_config_from_tx() {
  local tx="$1" config_path had_config tmp
  config_path="$(tx_read "$tx" config-path)"
  had_config="$(tx_read "$tx" had-config)"
  mkdir -p -- "$(dirname "$config_path")"
  if [ "$had_config" = "1" ] && [ -f "$tx/config.backup" ]; then
    tmp="${config_path}.leon-restore-$$"
    cp -p -- "$tx/config.backup" "$tmp"
    mv -f -- "$tmp" "$config_path"
  elif [ "$had_config" = "0" ]; then
    rm -f -- "$config_path"
  fi
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

health_smoke() {
  local tx="$1" live expected expected_skills skills_path attempts stable_sleep pid1 pid2 i
  live="$(tx_read "$tx" live-path)"
  expected="$(tx_read "$tx" bridge-sha256)"
  expected_skills="$(tx_read "$tx" skills-expected-digest)"
  skills_path="$(tx_read "$tx" skills-path)"
  attempts="${LEON_HEALTH_ATTEMPTS:-15}"
  stable_sleep="${LEON_HEALTH_STABLE_SLEEP:-3}"
  [ "${LEON_TEST_FAIL_AT:-}" != "health" ] || return 1
  [ -f "$live/bridge.cjs" ] || return 1
  [ -s "$live/appserver/adapter.cjs" ] || return 1
  [ -s "$live/lib/onboarding.js" ] || return 1
  [ -s "$live/lib-motores/codex-appserver.cjs" ] || return 1
  [ -s "$live/smoke/appserver-smoke.cjs" ] || return 1
  [ -s "$live/workers/piper.js" ] || return 1
  [ "$(sha256sum "$live/bridge.cjs" | awk '{print $1}')" = "$expected" ] || return 1
  [ "$(installed_skills_digest "$skills_path")" = "$expected_skills" ] || return 1
  "$NODE_BIN" --check "$live/bridge.cjs" >/dev/null 2>&1 || return 1
  "$NODE_BIN" --check "$live/appserver/adapter.cjs" >/dev/null 2>&1 || return 1
  "$NODE_BIN" --check "$live/lib/onboarding.js" >/dev/null 2>&1 || return 1
  "$NODE_BIN" --check "$live/lib-motores/codex-appserver.cjs" >/dev/null 2>&1 || return 1
  "$NODE_BIN" --check "$live/workers/piper.js" >/dev/null 2>&1 || return 1
  pid1=0
  i=0
  while [ "$i" -lt "$attempts" ]; do
    if service_read is-active "$SERVICE" >/dev/null 2>&1; then
      pid1="$(service_read show -p MainPID --value "$SERVICE" 2>/dev/null || echo 0)"
      case "$pid1" in ''|*[!0-9]*) pid1=0 ;; esac
      [ "$pid1" -gt 0 ] && break
    fi
    i=$((i + 1))
    sleep 1
  done
  [ "$pid1" -gt 0 ] || return 1
  sleep "$stable_sleep"
  pid2="$(service_read show -p MainPID --value "$SERVICE" 2>/dev/null || echo 0)"
  [ "$pid1" = "$pid2" ] && service_read is-active "$SERVICE" >/dev/null 2>&1 || return 1
  telegram_smoke "$live"
}

finalize_transaction() {
  local tx="$1" marker live lock_dir thread chat tx_service skills_backup skills_path
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
  lock_dir="$tx/.finalize-lock"
  mkdir "$lock_dir" 2>/dev/null || return 0
  trap 'rmdir -- "$lock_dir" 2>/dev/null || true' RETURN
  if health_smoke "$tx"; then
    # O veredito de saúde torna o commit definitivo. A remoção posterior do
    # backup é limpeza de quarentena; nunca tentamos rollback depois de apagá-lo.
    skills_backup="$(tx_read "$tx" skills-backup-path 2>/dev/null || true)"
    skills_path="$(tx_read "$tx" skills-path 2>/dev/null || true)"
    remove_committed_skills_backup "$skills_path" "$skills_backup" || {
      rmdir -- "$lock_dir" 2>/dev/null || true
      trap - RETURN
      return 1
    }
    printf 'succeeded\n' > "$tx/status"
    remove_finalize_cron "$marker"
    rm -f -- "$live/.update-pending.json" 2>/dev/null || true
    notify_from_runtime "$live" "✅ Atualização concluída. O motor Codex passou nos testes e o LEON está no ar." "$thread" "$chat"
    rmdir -- "$lock_dir" 2>/dev/null || true
    trap - RETURN
    return 0
  fi
  rollback_transaction "$tx"
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
LEON_DATA_DIR="${LEON_DATA_DIR:-$HOME/.leon}"
LEON_SKILLS_DIR="${LEON_SKILLS_DIR:-}"
CODEX_HOME_DIR="${LEON_CODEX_HOME:-$LEON_DATA_DIR/codex}"
LEON_TMPDIR="${LEON_TMPDIR:-}"
LEON_WORK_AREA="${LEON_WORK_AREA:-}"
LEON_STATE_DIR="${LEON_STATE_DIR:-}"
LEON_MISSIONS_DIR="${LEON_MISSIONS_DIR:-}"
LEON_PROMISES_DIR="${LEON_PROMISES_DIR:-}"
LEON_MISSION_OUTPUT_DIR="${LEON_MISSION_OUTPUT_DIR:-}"
LEON_CODEX_CLI_VERSION="${LEON_CODEX_CLI_VERSION:-}"
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
MODEL_SMOKE_HOME=""
MODEL_SMOKE_DIR=""
MODEL_SMOKE_OUT=""
MUTATION_STARTED=0
CRON_ARMED=0
RESTARTING=0
FAIL_MESSAGE="A atualização foi interrompida antes de concluir. A versão anterior foi preservada."
DANGEROUS_FLAG="--dangerously-bypass-approvals-and-"'sandbox'

say() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null || true
}

fatal() {
  FAIL_MESSAGE="$1"
  printf 'ERRO: %s\n' "$1" >&2
  exit 1
}

cleanup_main() {
  local status=$?
  set +e
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
  [ -z "$MODEL_SMOKE_HOME" ] || rm -rf -- "$MODEL_SMOKE_HOME"
  [ -z "$MODEL_SMOKE_DIR" ] || rm -rf -- "$MODEL_SMOKE_DIR"
  [ -z "$MODEL_SMOKE_OUT" ] || rm -f -- "$MODEL_SMOKE_OUT"
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
    else
      [ ! -e "$STAGE" ] || rm -rf -- "$STAGE"
      [ -z "${SKILLS_STAGE:-}" ] || [ ! -e "$SKILLS_STAGE" ] || rm -rf -- "$SKILLS_STAGE"
      if [ "$CRON_ARMED" -eq 1 ]; then
        restore_crontab_from_tx "$TX_DIR" >/dev/null 2>&1 || true
      fi
    fi
    notify_from_runtime "$INSTALL_DIR" "⚠️ $FAIL_MESSAGE" "$THREAD_ARG" "$CHAT_ARG"
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
case "$CONFIG_PATH" in "$HOME"/*) ;; *) fatal "o perfil Codex está fora da home esperada." ;; esac

for required in "$CURL_BIN" tar "$PYTHON_BIN" sha256sum cp mv; do
  command -v "$required" >/dev/null 2>&1 || fatal "falta o programa obrigatório: $required."
done
command -v "$CRONTAB_BIN" >/dev/null 2>&1 || fatal "o cron não está disponível para concluir a atualização com rollback."

ENV_READ_SAFE="$(mktemp "${TMPDIR:-/tmp}/leon-env-read.XXXXXX")"
safe_copy_state_file "$ENV_FILE" "$ENV_READ_SAFE" env \
  || fatal "o .env atual não é um arquivo regular 0600 seguro."

EMAIL="$(env_get_from "$ENV_READ_SAFE" LEON_LICENSE_EMAIL)"
CENTRAL="$(env_get_from "$ENV_READ_SAFE" LEON_LICENSE_CENTRAL)"
if [ -z "$EMAIL" ] || [ -z "$CENTRAL" ]; then
  fatal "faltam os dados da licença na configuração."
fi
[ -n "$LEON_CODEX_CLI_VERSION" ] || LEON_CODEX_CLI_VERSION="0.147.0"
[ -n "$LEON_SKILLS_DIR" ] || LEON_SKILLS_DIR="$LEON_DATA_DIR/skills"
[ -n "$LEON_TMPDIR" ] || LEON_TMPDIR="$LEON_DATA_DIR/tmp"
[ -n "$LEON_WORK_AREA" ] || LEON_WORK_AREA="$HOME/trabalho"
[ -n "$LEON_STATE_DIR" ] || LEON_STATE_DIR="$LEON_DATA_DIR/state"
[ -n "$LEON_MISSIONS_DIR" ] || LEON_MISSIONS_DIR="$LEON_STATE_DIR/missions"
[ -n "$LEON_PROMISES_DIR" ] || LEON_PROMISES_DIR="$LEON_STATE_DIR/promises"
[ -n "$LEON_MISSION_OUTPUT_DIR" ] || LEON_MISSION_OUTPUT_DIR="$LEON_DATA_DIR/mission-output"
EXPECTED_NODE_BIN="$LEON_DATA_DIR/node/releases/$LEON_NODE_VERSION/bin/node"
if [ "$TEST_MODE" = "1" ] && [ -n "$NODE_BIN" ]; then
  : # Fixture explícita; produção nunca aceita override do executável.
else
  NODE_BIN="$EXPECTED_NODE_BIN"
fi
command -v "$NODE_BIN" >/dev/null 2>&1 \
  || fatal "o runtime Node dedicado está ausente. Rode novamente o instalador Codex antes do /atualiza."
if [ "$TEST_MODE" != "1" ] || [ "$NODE_BIN" = "$EXPECTED_NODE_BIN" ]; then
  validate_dedicated_node "$NODE_BIN" "$LEON_DATA_DIR" "$LEON_NODE_VERSION" \
    || fatal "o runtime Node dedicado está ausente ou inseguro. Rode novamente o instalador Codex antes do /atualiza."
  [ "$($NODE_BIN --version 2>/dev/null || true)" = "v$LEON_NODE_VERSION" ] \
    || fatal "o runtime Node dedicado é incompatível. Rode novamente o instalador Codex antes do /atualiza."
fi
validate_service_unit "$UNIT_PATH" "$INSTALL_DIR" "$NODE_BIN" "$(id -un)" \
  || fatal "a unit do LEON não usa o runtime dedicado e o perfil endurecido. Rode novamente o instalador Codex antes do /atualiza."
SKILLS_STAGE="$LEON_DATA_DIR/.skills-stage-$TX_ID"
SKILLS_BACKUP="$LEON_DATA_DIR/.skills-backup-$TX_ID"
SKILLS_FAILED="$LEON_DATA_DIR/.skills-failed-$TX_ID"
case "$LEON_SKILLS_DIR" in "$HOME"/*) ;; *) fatal "o catálogo de skills precisa ficar dentro da home." ;; esac
validate_runtime_roots 0 || fatal "os caminhos de dados são inseguros ou passam por link simbólico; runtime preservado."
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
if [ "$TEST_MODE" = "1" ]; then
  case "$CENTRAL" in http://*|https://*) ;; *) fatal "endereço da central inválido." ;; esac
else
  case "$CENTRAL" in https://*) ;; *) fatal "a central de licença precisa usar HTTPS." ;; esac
fi

mkdir -p -- "$TX_ROOT" "$CODEX_HOME_DIR" "$LEON_TMPDIR" "$LEON_WORK_AREA" \
  "$LEON_DATA_DIR/brain" "$LEON_DATA_DIR/persona" "$LEON_MISSIONS_DIR" "$LEON_PROMISES_DIR" "$LEON_MISSION_OUTPUT_DIR"
chmod 0700 "$LEON_DATA_DIR" "$TX_ROOT" "$CODEX_HOME_DIR" 2>/dev/null || true
validate_runtime_roots 1 || fatal "os caminhos de dados mudaram durante a preparação; runtime preservado."
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
printf '0\n' > "$TX_DIR/skills-had-original"
printf '0\n' > "$TX_DIR/skills-applied"

HAD_CONFIG=0
if [ -f "$CONFIG_PATH" ]; then
  cp -p -- "$CONFIG_PATH" "$TX_DIR/config.backup"
  HAD_CONFIG=1
fi
printf '%s\n' "$HAD_CONFIG" > "$TX_DIR/had-config"
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
if ! curl_common -fsSL --max-filesize 524288 --retry 3 --retry-delay 2 --retry-connrefused \
    "$CENTRAL/release-manifest.json" -o "$RELEASE_MANIFEST" \
   || ! curl_common -fsSL --max-filesize 64 --retry 3 --retry-delay 2 --retry-connrefused \
    "$CENTRAL/release-manifest.sig" -o "$RELEASE_SIGNATURE"; then
  fatal "a central não entregou o manifesto assinado; runtime preservado."
fi
validate_download_file "$RELEASE_MANIFEST" 524288 \
  && validate_download_file "$RELEASE_SIGNATURE" 64 64 \
  || fatal "manifesto ou assinatura excede o contrato de transporte; runtime preservado."
verify_release_manifest "$RELEASE_MANIFEST" "$RELEASE_SIGNATURE" "$RELEASE_PUBLIC_KEY" "$RELEASE_METADATA" \
  || fatal "assinatura ou contrato da release inválido; runtime preservado."
RELEASE_MANIFEST_SHA256="$(sha256sum "$RELEASE_MANIFEST" | awk '{print $1}')"
# shellcheck disable=SC1090
. "$RELEASE_METADATA"
semver_ge "$version" "$minVersion" || fatal "release abaixo da versão mínima assinada."
[ "$codexCliVersion" = "$LEON_CODEX_CLI_VERSION" ] \
  || fatal "a release exige Codex CLI $codexCliVersion; rode o instalador antes do /atualiza."
[ "$nodeVersion" = "$LEON_NODE_VERSION" ] \
  || fatal "a release exige Node $nodeVersion; rode o instalador antes do /atualiza."
INSTALLED_RELEASE_IDENTITY="$(read_installed_release_identity "$INSTALL_DIR")" \
  || fatal "o marcador da release instalada é inseguro ou inválido."
IFS=$'\t' read -r INSTALLED_RELEASE_VERSION INSTALLED_RELEASE_DIGEST <<< "$INSTALLED_RELEASE_IDENTITY"
release_identity_acceptable "$version" "$RELEASE_MANIFEST_SHA256" "$INSTALLED_RELEASE_VERSION" "${INSTALLED_RELEASE_DIGEST:-}" \
  || fatal "manifesto assinado é downgrade, replay ambíguo ou equivoca a release $INSTALLED_RELEASE_VERSION."

TARBALL="$(mktemp "${TMPDIR:-/tmp}/leon-package.XXXXXX.tar.gz")"
say "baixando pacote para transacao $TX_ID"
if ! HTTP_CODE="$(curl_common -sS --max-filesize "$base_bytes" --retry 3 --retry-delay 2 --retry-connrefused \
    --max-time 180 -w '%{http_code}' -o "$TARBALL" \
    "$CENTRAL/download-codex?email=$EMAIL_ENC")"; then
  fatal "a internet falhou durante o download; nada foi trocado."
fi
[ "$HTTP_CODE" = "200" ] || fatal "a central recusou o download (HTTP $HTTP_CODE); nada foi trocado."
verify_signed_artifact "$TARBALL" "$base_sha256" "$base_bytes" "pacote-base"

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
for _peca in NUCLEO-LEON.md _MOTOR-CLAUDE.md _MOTOR-CODEX.md _REGRAS-DURAS.md CAMINHOS-CANONICOS.md; do
  if [ -f "$STAGE/$_peca" ]; then
    normalize_agent_base "$STAGE/$_peca" "$LEON_SKILLS_DIR" 2>/dev/null || true
    install -m 0600 "$STAGE/$_peca" "$LEON_DATA_DIR/persona/$_peca" 2>/dev/null || true
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
write_codex_config_candidate "$TX_DIR/config.candidate" \
  || fatal "não consegui gerar o perfil Codex root-deny canônico."

# O bridge v2 depende do adapter e do shim da mesma versão. Baixamos um bundle
# indivisível, validamos hash, lista exata e sintaxe, e só então sobrepomos o stage.
BUNDLE_TMP="$(mktemp "${TMPDIR:-/tmp}/leon-codex-v2.XXXXXX.tar.gz")"
# o cap de transporte (--max-filesize) e aplicado dentro de baixa_com_espelho, nos DOIS
# caminhos (central e espelho), com o valor passado no terceiro argumento.
if ! baixa_com_espelho "$bundle_url" "$BUNDLE_TMP" "$bundle_bytes"; then
  fatal "não consegui baixar o runtime Codex v2 completo."
fi
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
    "lib/inbound.js",
    "lib/meta-connect.js",
    "lib/meta-mcp-codex-filter.cjs",
    "lib/meta-account-guard.cjs",
    "lib-motores/codex-appserver.cjs",
    "smoke/appserver-smoke.cjs",
    "workers/piper.js",
}
directories = {"appserver", "lib", "lib-motores", "smoke", "workers"}
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
    if not member.isfile() or member.size > 2_000_000:
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
for runtime_js in bridge.cjs appserver/adapter.cjs lib/onboarding.js lib/inbound.js lib/meta-connect.js lib/meta-mcp-codex-filter.cjs lib/meta-account-guard.cjs lib-motores/codex-appserver.cjs smoke/appserver-smoke.cjs workers/piper.js; do
  "$NODE_BIN" --check "$BUNDLE_EXTRACT/$runtime_js" >/dev/null 2>&1 \
    || fatal "o runtime Codex v2 contém JavaScript inválido: $runtime_js."
done
LEGACY_NAME='open''claw'
if LC_ALL=C grep -Rqi -- "$LEGACY_NAME" "$BUNDLE_EXTRACT" \
   || LC_ALL=C grep -Rq -- 'bypassPermissions' "$BUNDLE_EXTRACT" \
   || LC_ALL=C grep -R -l --binary-files=text -- "$DANGEROUS_FLAG" "$BUNDLE_EXTRACT" >/dev/null 2>&1 \
   || ! grep -q 'const LEON_CODEX_ONLY = true' "$BUNDLE_EXTRACT/bridge.cjs" \
   || ! grep -q 'createCodexAppServerMotor' "$BUNDLE_EXTRACT/bridge.cjs"; then
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
# o cap de transporte (--max-filesize) e aplicado dentro de baixa_com_espelho, nos DOIS
# caminhos (central e espelho), com o valor passado no terceiro argumento.
if ! baixa_com_espelho "$skills_url" "$SKILLS_TMP" "$skills_bytes"; then
  fatal "não consegui baixar o catálogo Codex assinado."
fi
verify_signed_artifact "$SKILLS_TMP" "$skills_sha256" "$skills_bytes" "catálogo de skills"
audit_skills_archive "$SKILLS_TMP" \
  || fatal "o catálogo de skills contém membros inseguros ou incompletos."
SKILLS_EXTRACT="$(mktemp -d "$LEON_DATA_DIR/.skills-extract-$TX_ID.XXXXXX")"
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
# o cap de transporte (--max-filesize) e aplicado dentro de baixa_com_espelho, nos DOIS
# caminhos (central e espelho), com o valor passado no terceiro argumento.
if ! baixa_com_espelho "$updater_url" "$UPDATE_TMP" "$updater_bytes"; then
  fatal "não consegui baixar o atualizador candidato assinado."
fi
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
chmod u+x "$STAGE"/*.sh "$STAGE"/scripts/*.sh 2>/dev/null || true
find "$STAGE" -xdev -type d -exec chmod go-rwx {} +
find "$STAGE" -xdev -type f -exec chmod go-rwx {} +
"$NODE_BIN" --check "$STAGE/bridge.cjs" >/dev/null 2>&1 \
  || fatal "o motor preparado falhou no último teste de sintaxe."
[ -s "$STAGE/appserver/adapter.cjs" ] \
  && [ -s "$STAGE/lib/onboarding.js" ] \
  && [ -s "$STAGE/lib-motores/codex-appserver.cjs" ] \
  && [ -s "$STAGE/smoke/appserver-smoke.cjs" ] \
  && [ -s "$STAGE/workers/piper.js" ] \
  && [ -s "$STAGE/capabilities.json" ] \
  || fatal "o stage perdeu uma peça obrigatória do runtime app-server."
"$NODE_BIN" --check "$STAGE/workers/piper.js" >/dev/null 2>&1 \
  || fatal "o worker Piper preparado falhou no último teste de sintaxe."
grep -q 'const LEON_CODEX_ONLY = true' "$STAGE/bridge.cjs" \
  || fatal "o stage não é Codex-only."
bash -n "$STAGE/update-pago.sh" || fatal "o atualizador preparado falhou no último teste de sintaxe."
BRIDGE_SHA="$(sha256sum "$STAGE/bridge.cjs" | awk '{print $1}')"
printf '%s\n' "$BRIDGE_SHA" > "$TX_DIR/bridge-sha256"

# O modelo e a sessão persistente são provados no stage, com cópia efêmera e
# segura da autenticação. Falha de acesso ao modelo nunca cai para outro modelo.
run_candidate_model_smoke "$STAGE" "$TX_DIR" \
  || fatal "o app-server não obteve duas respostas persistentes do modelo ${CODEX_MODEL_EFETIVO:-gpt-5.6-sol}; runtime preservado. Rode o instalador para revisar login e acesso ao modelo."

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

rewrite_runtime_env "$STAGE/.env" \
  || fatal "o .env atual não pôde ser reduzido à configuração suportada; runtime preservado."

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
  || fatal "não consegui ativar o catálogo Codex assinado."
[ "$(installed_skills_digest "$LEON_SKILLS_DIR")" = "$SKILLS_EXPECTED_DIGEST" ] \
  || fatal "o catálogo Codex mudou durante o commit."
if [ "${LEON_TEST_FAIL_AT:-}" = "after_skills" ]; then
  fatal "falha injetada depois da troca de skills."
fi
if [ -f "$TX_DIR/config.candidate" ]; then
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
# 3b) MODELO DE AUDIO NATIVO (25/08, caso Leticia): casa instalada antes do fix
# nao tem o modelo whisper — o 1o audio do cliente dispara download de 464MB DENTRO
# do bridge rodando (pico ~580MB de RAM = perfil de OOM em VPS pequena). Baixa AGORA,
# fora do bridge, com teto de tempo. Idempotente: cache pronto = sai na hora.
if [ -x "$HOME/.leon/whisper-venv/bin/python3" ]; then
  timeout 600 "$HOME/.leon/whisper-venv/bin/python3" - <<'PYMODEL' >/dev/null 2>&1 && say "   modelo de audio pronto (transcricao nativa)." || true
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

# 4) REPORTA A VERSAO pra central (24/08): a rota /versao-report existia e NINGUEM
# chamava — versao_atual vazia nas 32 licencas, dono cego sobre quem esta em qual
# versao. Best-effort: falha de rede nao atrapalha o update.
curl -fsS --max-time 15 -X POST "$CENTRAL/versao-report" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"versao\":\"$version\"}" >/dev/null 2>&1 || true

say "commit atomico concluido; reiniciando $SERVICE"
if [ "$TEST_MODE" = "1" ]; then
  service_write restart "$SERVICE"
  MUTATION_STARTED=0
  if finalize_transaction "$TX_DIR"; then
    exit 0
  fi
  exit 1
fi

# O restart normalmente encerra este processo junto com o cgroup antigo. O
# finalizador ja esta no cron e assume a prova de estabilidade ou o rollback.
RESTARTING=1
set +e
service_write restart "$SERVICE"
RESTART_STATUS=$?
set -e
if [ "$RESTART_STATUS" -ne 0 ]; then
  RESTARTING=0
  rollback_transaction "$TX_DIR" || true
  fatal "o serviço recusou o reinício; a versão anterior foi restaurada."
fi

# Algumas units encerram somente o processo principal e deixam o atualizador
# terminar. Nesse caso concluimos agora; o cron percebe o veredito e se remove.
RESTARTING=0
MUTATION_STARTED=0
finalize_transaction "$TX_DIR"
