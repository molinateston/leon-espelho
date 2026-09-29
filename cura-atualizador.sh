#!/usr/bin/env bash
# =====================================================================
# cura-atualizador.sh — destrava o /atualiza preso pelo bug do $version.
#
# POR QUE EXISTE:
#   As releases 2.4.14 a 2.4.17 saíram com um atualizador (update-pago.sh)
#   que gravava a versão ANTES de defini-la. Com `set -u`, ele morre em
#   "version: unbound variable" ANTES de aplicar qualquer atualização. O
#   dono vê "Atualizando..." e depois "interrompida, versão preservada",
#   pra sempre. O rollback funciona (o bot continua no ar), mas o
#   atualizador nunca mais consegue trocar de versão sozinho — inclusive
#   não consegue baixar a correção (o ovo-galinha).
#
# O QUE FAZ:
#   Troca SÓ o atualizador quebrado pelo são (2.4.18), baixado da central
#   e conferido pela MESMA cadeia assinada do instalador (Ed25519 +
#   sha256). Não mexe em mais nada. Depois disso, o /atualiza volta a
#   funcionar e a atualização automática da madrugada aplica a 2.4.18.
#
#   Motor-agnóstico: serve Claude E Codex (o atualizador é o mesmo nos
#   dois; muda só o motor, que este script NÃO toca). Sem sudo: o
#   atualizador é do próprio usuário do LEON.
#
# SEGURANÇA (regra de ouro: na menor dúvida, NÃO troca):
#   - Só troca se o atualizador LOCAL for RECONHECIDAMENTE um dos bugados
#     (sha256 numa lista fechada de 3). Qualquer outro = não toca.
#   - Só INSTALA o atualizador são cujo sha256 este script conhece e testou
#     (allowlist de 1). Central servindo outra coisa (mesmo assinada) = aborta.
#   - Assinatura Ed25519 do manifesto + sha256/tamanho do artefato conferidos
#     antes de qualquer troca. Qualquer divergência = aborta sem tocar.
#   - Troca por rename atômico DENTRO do diretório da instalação (nunca
#     deixa o updater pela metade nem some). Falso-negativo só adia a cura;
#     falso-positivo (trocar um são, ou deixar um meio-trocado) é o que não
#     pode acontecer.
#
# Uso (o dono cola no terminal da VPS dele):
#   curl -fsSL https://licenca.leonardomolina.com.br/cura-atualizador.sh | bash
# =====================================================================
set -uo pipefail

main() {  # tudo dentro de main(): se o `curl | bash` cortar no meio, um
          # corpo incompleto não roda (o shell só chama main na última linha).

  msg()  { printf '%s\n' "$*"; }
  ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
  warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
  die()  { printf '\033[31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

  # --- chave pública de PRODUÇÃO (a MESMA do instalador e do reparar.sh) --
  # Pinada no código, NUNCA vem da rede. Conferida pelo fingerprint antes de
  # qualquer verificação de assinatura. (A de staging é outra — não usar.)
  # Marcadores IGUAIS aos do updater/instalador: o build reescreve fingerprint e PEM
  # aqui tambem (staging ou producao), entao rotacao de chave nunca deixa a cura velha.
  local LEON_RELEASE_TRUST_FINGERPRINT='eb70521f5e4dd9bb1cd11e6ceb0b2bddd65596558322908a2d04fd3dec5cbe08'
  write_release_public_key() {
    local output="$1"
    cat > "$output" <<'PEM'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAzLQi1On9pdcj/g7Z8WxHxPeTijp0t3yhGnfoZfDzpXI=
-----END PUBLIC KEY-----
PEM
    [ "$(sha256sum "$output" | awk '{print $1}')" = "$LEON_RELEASE_TRUST_FINGERPRINT" ]
  }

  # --- os atualizadores BUGADOS conhecidos ------------------------------
  # Sha256 dos ARTEFATOS realmente servidos por cada release (batem com os
  # manifestos assinados). Lista fechada: só troca o que está aqui.
  #   c10cd4a1 = 2.4.14/15 · 4f071236 = 2.4.16 · 6a15bc3e = 2.4.17
  #   58135216 = 2.4.19-curated (o build curated regrediu o bug do $version;
  #              achado vivo no LEON 99, que estava com esse updater). O curated
  #              tem que ser rebaseado com o fix 607a971 antes de voltar a servir.
  local DENYLIST="\
c10cd4a16ab1a040e6381c42ed4e9e608e41f05e7c6ccf7f66e64bf9172159eb
4f071236863a3f77a30a9bfb3d585f757c4c7364da7e522d48e2f7b2b51ea36c
6a15bc3e79d798d8007ce4e94c59b0d37f6b1c2ced0c84c12cd643da84bffe64
581352168317879252569168c3387f62f4a1fb94db109a697debeb845b45b15d"

  # --- o ÚNICO atualizador são que esta cura instala (allowlist, 2.4.18) --
  # Pin positivo: mesmo um manifesto validamente assinado que aponte pra
  # OUTRO updater (release futura bugada, engano no deploy) é recusado. Ao
  # trocar o updater são, reemitir a cura com o sha novo — a falha em
  # esquecer é ruidosa e segura (recusa), nunca silenciosa.
  # 12/09 (obra, item 08): o updater sao passou a ser o PUBLICADO 2.4.48 com as duas
  # curas do 0.7 (chave de licenca gravada no .env; skills-pessoais e quarentena
  # retida). Trocar o updater muda o sha, e o proprio comentario acima manda
  # reemitir o pin. Anterior (publicado 2.4.48 sem cura): 3f30053dda56854e60a5b6726bd7ac7e9ca8cc00087ea13acf4d8ad0dc808f7e
  local SANE_SHA='741e623f381ec3302ca3b5c6f59584f24de6b63c54d7abd63f7b3d45b3908e45'

  # --- dependências mínimas --------------------------------------------
  local dep
  for dep in curl openssl python3 sha256sum; do
    command -v "$dep" >/dev/null 2>&1 \
      || die "'$dep' faltando nesta VPS — instale e rode de novo."
  done

  # --- descobrir a instalação ------------------------------------------
  local INSTALL_DIR UPDATER
  INSTALL_DIR="${LEON_DIR:-$HOME/socio-ia}"
  [ -f "$INSTALL_DIR/.env" ] || die "não achei a instalação em $INSTALL_DIR (rode como o usuário do LEON)."
  UPDATER="$INSTALL_DIR/update-pago.sh"

  env_get() {
    grep -E "^$1=" "$INSTALL_DIR/.env" 2>/dev/null | tail -1 | cut -d= -f2- \
      | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//' || true
  }
  local CENTRAL
  CENTRAL="${LEON_CENTRAL:-$(env_get LEON_LICENSE_CENTRAL)}"
  CENTRAL="${CENTRAL:-https://licenca.leonardomolina.com.br}"

  msg "LEON — cura do atualizador"
  msg "  instalação: $INSTALL_DIR"
  msg "  central:    $CENTRAL"
  msg ""

  # --- o atualizador local está entre os bugados conhecidos? -----------
  [ -f "$UPDATER" ] || die "não achei o atualizador em $UPDATER — instalação incompleta, chame o suporte."
  [ -L "$UPDATER" ] && die "o atualizador é um link simbólico — não vou tocar por segurança."
  [ -O "$UPDATER" ] || die "o atualizador não é seu ($UPDATER) — rode como o usuário do LEON."

  local LOCAL_SHA
  LOCAL_SHA="$(sha256sum "$UPDATER" | awk '{print $1}')"
  if ! printf '%s\n' "$DENYLIST" | grep -qx "$LOCAL_SHA"; then
    ok ">> Seu atualizador NÃO é um dos que travaram (sha ${LOCAL_SHA:0:12}…)."
    ok "   Nada a consertar aqui. Se o /atualiza está preso por outro motivo,"
    ok "   chame o suporte: https://wa.me/5511988890934"
    exit 0
  fi
  warn ">> Atualizador BUGADO detectado (sha ${LOCAL_SHA:0:12}…). Vou trocar pelo são."
  msg ""

  # --- trava: uma cura por vez (com PID, pra limpar trava morta) --------
  local LOCK="$INSTALL_DIR/.cura-updater.lock"
  if ! mkdir "$LOCK" 2>/dev/null; then
    local dono_pid
    dono_pid="$(cat "$LOCK/pid" 2>/dev/null || echo '')"
    if [ -n "$dono_pid" ] && kill -0 "$dono_pid" 2>/dev/null; then
      die "já há uma cura em andamento (pid $dono_pid). Aguarde ela terminar."
    fi
    # trava órfã (processo morto por SIGKILL/reboot/OOM): recupera.
    rm -rf "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || die "não consegui criar a trava $LOCK — verifique permissões."
  fi
  echo "$$" > "$LOCK/pid" 2>/dev/null || true

  # temp DENTRO da instalação: garante que o `mv` final seja no MESMO
  # filesystem (rename atômico de verdade). /tmp costuma ser tmpfs em
  # filesystem diferente, e aí o mv vira unlink+copy (updater some/meio).
  local TMP_DIR
  TMP_DIR="$(mktemp -d "$INSTALL_DIR/.cura-tmp.XXXXXX")" \
    || die "não consegui criar diretório temporário em $INSTALL_DIR."
  trap 'rm -rf "$LOCK" "$TMP_DIR" 2>/dev/null || true' EXIT

  # --- não brigar com um /atualiza em curso ----------------------------
  # pgrep -f varre a linha de comando inteira, então pode casar o PRÓPRIO
  # processo da cura (e sua árvore) se a string aparecer no argv. Excluímos
  # a nós mesmos e aos ancestrais antes de decidir que há um update rodando.
  update_em_curso() {
    local hits p anc eh_ancestral
    hits="$(pgrep -u "$(id -u)" -f 'update-pago\.sh' 2>/dev/null)" || return 1
    for p in $hits; do
      case " $$ $PPID " in *" $p "*) continue ;; esac
      anc="$PPID"; eh_ancestral=0
      while [ "${anc:-0}" -gt 1 ] 2>/dev/null; do
        [ "$anc" = "$p" ] && { eh_ancestral=1; break; }
        # PPid via /proc/status: imune a espaço/parênteses no comm (o campo
        # 4 do /proc/stat quebra quando o nome do processo tem espaço).
        anc="$(awk '/^PPid:/{print $2}' "/proc/$anc/status" 2>/dev/null)"
        [ -z "$anc" ] && break
      done
      [ "$eh_ancestral" -eq 1 ] && continue
      return 0
    done
    return 1
  }
  if update_em_curso; then
    die "há uma atualização rodando agora. Espere ela terminar e rode a cura de novo."
  fi

  umask 077

  # =====================================================================
  # 1) manifesto ASSINADO da release (schema 2, artefato "updater")
  # =====================================================================
  msg ">> baixando e conferindo o manifesto assinado da release…"
  local MANIFEST="$TMP_DIR/release-manifest.json"
  local SIG="$TMP_DIR/release-manifest.sig"
  local PUBKEY="$TMP_DIR/release.pub"

  curl -fsSL --proto '=https' --proto-redir '=https' --max-redirs 2 \
    --connect-timeout 10 --max-time 30 --retry 2 --max-filesize 524288 \
    -o "$MANIFEST" "$CENTRAL/release-manifest.json" \
    || die "não consegui baixar o manifesto da release de $CENTRAL."
  curl -fsSL --proto '=https' --proto-redir '=https' --max-redirs 2 \
    --connect-timeout 10 --max-time 30 --retry 2 --max-filesize 64 \
    -o "$SIG" "$CENTRAL/release-manifest.sig" \
    || die "não consegui baixar a assinatura do manifesto de $CENTRAL."

  write_release_public_key "$PUBKEY" \
    || die "chave pública da release não confere o fingerprint de confiança (bug no script)."
  openssl pkeyutl -verify -rawin -pubin -inkey "$PUBKEY" \
    -in "$MANIFEST" -sigfile "$SIG" >/dev/null 2>&1 \
    || die "assinatura do manifesto não confere (central usada: $CENTRAL) — cura abortada, nada foi tocado."

  # --- validar o contrato do manifesto e extrair sha/bytes/versão do updater
  local UPD_META="$TMP_DIR/updater.meta"
  python3 - "$MANIFEST" "$LEON_RELEASE_TRUST_FINGERPRINT" > "$UPD_META" <<'PY' \
    || die "manifesto da release inválido — cura abortada."
import json,re,sys
manifest,fingerprint=sys.argv[1:]
try: data=json.load(open(manifest,encoding="utf-8"))
except Exception: raise SystemExit(1)
if data.get("kind")!="leon-codex-release" or data.get("channel")!="stable": raise SystemExit(1)
try:
    if int(data.get("schema",0))!=2: raise SystemExit(1)
except Exception: raise SystemExit(1)
if data.get("keyFingerprint")!=fingerprint: raise SystemExit(1)
item=data.get("artifacts",{}).get("updater")
if not isinstance(item,dict): raise SystemExit(1)
# caminho FIXO — nunca seguimos uma URL arbitrária do JSON
if item.get("url")!="/update-pago-codex.sh": raise SystemExit(1)
if item.get("licensed") is True: raise SystemExit(1)  # updater é público, sem e-mail
if not re.fullmatch(r"[0-9a-f]{64}",str(item.get("sha256",""))): raise SystemExit(1)
b=item.get("bytes")
if isinstance(b,bool) or not isinstance(b,int) or not 1<=b<=536_870_912: raise SystemExit(1)
ver=str(data.get("version",""))
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+",ver): raise SystemExit(1)
print("upd_sha256="+item["sha256"])
print("upd_bytes=%d"%b)
print("upd_version="+ver)
PY
  # shellcheck disable=SC1090
  . "$UPD_META"

  # --- allowlist: a cura instala SÓ o updater são que ela conhece --------
  if [ "${upd_sha256:-}" != "$SANE_SHA" ]; then
    die "a central serve um atualizador que esta cura não conhece (esperado ${SANE_SHA:0:12}…, veio ${upd_sha256:0:12}…) — abortada. Atualize a cura ou chame o suporte."
  fi
  ok "   manifesto ok — release ${upd_version}, atualizador são ${upd_sha256:0:12}…"

  # =====================================================================
  # 2) baixar o atualizador são e conferir EXATAMENTE contra o manifesto
  # =====================================================================
  msg ">> baixando o atualizador são…"
  # nome sem a substring 'update-pago.sh' de propósito (senão o pgrep -f de
  # outros vigias bateria neste arquivo temporário).
  local CAND="$TMP_DIR/updater-sao.candidate"
  curl -fsSL --proto '=https' --proto-redir '=https' --max-redirs 2 \
    --connect-timeout 10 --max-time 120 --retry 2 --max-filesize "$((upd_bytes + 1))" \
    -o "$CAND" "$CENTRAL/update-pago-codex.sh" \
    || die "não consegui baixar o atualizador são de $CENTRAL."

  # confere hash + tamanho + inode (O_NOFOLLOW), verbatim do reparar.sh
  verify_signed_artifact() {
    python3 - "$1" "$2" "$3" <<'PY' \
      || { echo "ERRO: $4 difere do artefato assinado." >&2; return 1; }
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
  verify_signed_artifact "$CAND" "$upd_sha256" "$upd_bytes" "atualizador são" \
    || die "o atualizador baixado não bate o manifesto assinado — cura abortada, nada foi tocado."

  # sanidade barata do candidato (o que o próprio instalador faz): sintaxe
  # ok e é mesmo um updater (tem a verificação de manifesto assinado dentro).
  bash -n "$CAND" 2>/dev/null \
    || die "o atualizador baixado não passou no teste de sintaxe — cura abortada."
  grep -q 'verify_release_manifest' "$CAND" 2>/dev/null \
    || die "o atualizador baixado não parece um atualizador do LEON — cura abortada."
  ok "   atualizador são conferido (assinatura + sha256 + tamanho + sintaxe)."

  # =====================================================================
  # 3) instalar o são no lugar (backup + rename atômico no mesmo fs)
  # =====================================================================
  local BACKUP="$INSTALL_DIR/update-pago.sh.bugado-${LOCAL_SHA:0:12}"
  # backup falhando = disco cheio (provável) = pare ANTES de tocar no updater.
  cp -p "$UPDATER" "$BACKUP" \
    || die "não consegui guardar a cópia de segurança (disco cheio?) — cura abortada antes de trocar nada."
  chmod 0700 "$CAND" 2>/dev/null || true
  # mv no mesmo filesystem = troca atômica; nunca cp por cima (um leitor
  # concorrente pegaria o arquivo pela metade).
  mv -f "$CAND" "$UPDATER" || die "não consegui instalar o atualizador são (permissão?)."

  # --- registrar no log e deixar um marcador ---------------------------
  local NOW
  NOW="$(date '+%F %T')"
  printf '%s [cura] atualizador trocado: %s -> %s (release %s)\n' \
    "$NOW" "${LOCAL_SHA:0:12}" "${upd_sha256:0:12}" "$upd_version" \
    >> "$INSTALL_DIR/upgrade.log" 2>/dev/null || true
  printf '{"curadoEm":"%s","de":"%s","para":"%s","versao":"%s"}\n' \
    "$NOW" "$LOCAL_SHA" "$upd_sha256" "$upd_version" \
    > "$INSTALL_DIR/.cura-updater.json" 2>/dev/null || true

  msg ""
  ok "✅ Pronto! Seu atualizador foi consertado."
  ok "   O que era: ${LOCAL_SHA:0:12}…  →  agora: ${upd_sha256:0:12}… (release $upd_version)"
  msg ""
  msg "Agora é só mandar  /atualiza  no seu LEON, ou deixar que ele se"
  msg "atualize sozinho na próxima madrugada. Nada da sua conversa se perdeu."
  msg "(a versão de antes ficou guardada em $BACKUP)"
  exit 0
}

main "$@"
