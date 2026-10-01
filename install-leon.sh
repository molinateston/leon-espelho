#!/usr/bin/env bash
# ===== LIGA-CODEX (11/09): liga o 2o motor numa casa que JA roda. INERTE na instalacao normal; =====
# ===== so entra com LEON_LIGA_MOTOR=codex. Provado em container (E2E). Fonte: liga-codex.sh no repo. =====
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

if [ "${LEON_LIGA_MOTOR:-}" = codex ]; then
# =============================================================================
# liga-codex.sh — ADICIONA o motor Codex numa casa LEON que JA roda (mono, motor
# claude), SEM reinstalar e SEM derrubar o LEON no ar. Depois o dono da /codex no
# Telegram e o agente troca pro Codex; /claude volta. Multimotor de fato, do jeito
# do mestre.
#
# COMO FUNCIONA (desenho Fable, validado Astra — wf_7eb3306a-dfe, 11/09):
#  - Roda COMO O USER leon (os prefixos dedicados sao 0700 dono leon; o auth.json,
#    o .env e o config.toml tem que nascer dono leon). SO o passo do PATH do
#    servico (SEC7) precisa de root.
#  - REUSA as funcoes JA PROVADAS do install-leon.sh (nao reimplementa): extrai as
#    13 funcoes de runtime/login por awk e sourcea SO o extrato (nao roda o install
#    inteiro — ele nao tem guarda main e reinstalaria a casa).
#  - So PREENCHE valores de chaves que o install ja escreve (todas na allowlist do
#    bridge; zero chave nova = zero crash-loop). NAO mexe em ENGINE_DEFAULT (fica
#    claude): o /codex grava motor-escolhido.json, que vence o .env.
#  - Se o login/prova do Codex falhar, ABORTA sem tocar no .env: o LEON claude fica
#    intacto. Idempotente: rodar 2x nao dispara device-auth de novo.
#
# USO (no terminal do navegador da casa do cliente):
#   sudo -iu leon bash -c 'curl -fsSL https://licenca.leonardomolina.com.br/liga-codex.sh | bash'
#   (o -i reseta HOME=/home/leon — obrigatorio, senao o runtime iria pra /root)
# =============================================================================
set -uo pipefail
# Tudo que este script cria nasce privado (0700/0600). A validacao dos prefixos
# dedicados (install-leon.sh) rejeita diretorio com escrita de grupo/outros; um
# login shell no Ubuntu vem com umask 002 e criaria .leon 775 -> reprova. Nao
# depender do umask de quem chama.
umask 077

# ------------------------------------------------------------
# SEC0 · Contexto seguro: sou o user leon, com HOME certo?
#   (FURO-1 Astra: sudo -u leon sem -i deixa HOME=/root -> LEON_DATA_DIR=/root/.leon
#    e ensure_node_runtime reprova por case "$target_home"/*. Exijo HOME correto.)
# ------------------------------------------------------------
LEON_USER="${LEON_USER:-leon}"
CENTRAL="${LEON_CENTRAL:-https://licenca.leonardomolina.com.br}"
SYS_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
: "${LEON_NODE_VERSION:=22.22.0}"
: "${LEON_LIGA_FASE:=}"

# SEC0-root · O terminal do navegador do cliente e root. Como root, este script
# pivota pro user leon (mesmo runuser/env -i do install-leon.sh L1296) pra fazer
# runtime+login+.env+config (SEC1-6, tudo dono leon), e volta como root pra aplicar
# o PATH do servico e o restart (SEC7). Um comando, sem copiar-colar.
if [ "$(id -u)" -eq 0 ]; then
  id "$LEON_USER" >/dev/null 2>&1 || { echo "ERRO: usuario '$LEON_USER' nao existe; a casa LEON nao esta instalada aqui." >&2; exit 1; }
  LEON_HOME="$(getent passwd "$LEON_USER" | cut -d: -f6)"
  [ -n "$LEON_HOME" ] && [ -d "$LEON_HOME" ] || { echo "ERRO: home de '$LEON_USER' nao encontrada." >&2; exit 1; }
  SELF="$LEON_HOME/liga-codex.sh"
  if [ -f "${BASH_SOURCE[0]:-}" ]; then
    [ "$(readlink -f -- "${BASH_SOURCE[0]}")" = "$(readlink -f -- "$SELF" 2>/dev/null || true)" ] || cp -- "${BASH_SOURCE[0]}" "$SELF"
  else
    curl -fsSL --connect-timeout 20 "${LEON_ESPELHO:-https://raw.githubusercontent.com/molinateston/leon-espelho/main}/install-leon.sh" -o "$SELF" \
      || curl -fsSL --connect-timeout 10 "$CENTRAL/install-leon.sh" -o "$SELF" \
      || { echo "ERRO: nao baixei o install-leon.sh (GitHub e central)." >&2; exit 1; }
  fi
  chown "$LEON_USER:$LEON_USER" "$SELF"; chmod 0700 "$SELF"
  # LEITOR UNICO DAS PASTAS (24/09, rodada 5): a LEON_DATA_DIR da casa sai do .env dela
  leon_bases_do_dono "${LEON_DIR:-$LEON_HOME/socio-ia}/.env" "$LEON_HOME" \
    || { echo "ERRO: nao consegui ler as pastas do .env da casa." >&2; exit 1; }
  echo "== liga-codex · fase root: passando pro usuario '$LEON_USER' =="
  runuser -u "$LEON_USER" -- env -i \
    HOME="$LEON_HOME" USER="$LEON_USER" LOGNAME="$LEON_USER" PATH="$SYS_PATH" \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM="${TERM:-dumb}" \
    LEON_USER="$LEON_USER" LEON_LIGA_FASE=user LEON_CENTRAL="$CENTRAL" \
    LEON_DIR="${LEON_DIR:-}" LEON_DATA_DIR="$LEON_DATA_DIR" \
    LEON_NODE_VERSION="$LEON_NODE_VERSION" LEON_CODEX_CLI_VERSION="${LEON_CODEX_CLI_VERSION:-}" \
    CODEX_MODEL="${CODEX_MODEL:-}" \
    LEON_INSTALLER_SRC="${LEON_INSTALLER_SRC:-$SELF}" LEON_LIGA_MOTOR=codex \
    LEON_TEST_NODE_ONLY="${LEON_TEST_NODE_ONLY:-}" LEON_TEST_NODE_ARCH="${LEON_TEST_NODE_ARCH:-}" \
    LEON_TEST_NODE_TGZ="${LEON_TEST_NODE_TGZ:-}" LEON_TEST_NODE_SHA256="${LEON_TEST_NODE_SHA256:-}" \
    LEON_TEST_CODEX_CLI_ONLY="${LEON_TEST_CODEX_CLI_ONLY:-}" LEON_TEST_CODEX_ARCH="${LEON_TEST_CODEX_ARCH:-}" \
    LEON_TEST_CODEX_MAIN_TGZ="${LEON_TEST_CODEX_MAIN_TGZ:-}" LEON_TEST_CODEX_PLATFORM_TGZ="${LEON_TEST_CODEX_PLATFORM_TGZ:-}" \
    LEON_TEST_CODEX_MAIN_SHA512="${LEON_TEST_CODEX_MAIN_SHA512:-}" LEON_TEST_CODEX_PLATFORM_SHA512="${LEON_TEST_CODEX_PLATFORM_SHA512:-}" \
    bash "$SELF" || { echo "ERRO: a fase do usuario '$LEON_USER' nao concluiu. Nada foi trocado no servico; o LEON atual segue no ar." >&2; exit 1; }
  # SEC7 como root (sem sudo): o node dedicado que a fase user acabou de validar, na mesma
  # LEON_DATA_DIR que a fase user leu do .env da casa (leitor unico, 24/09 rodada 5)
  NODE_DIR="$LEON_DATA_DIR/node/releases/$LEON_NODE_VERSION/bin"
  [ -x "$NODE_DIR/node" ] || { echo "ERRO: node dedicado nao encontrado em $NODE_DIR apos a fase user." >&2; exit 1; }
  UNIT=leon-agente.service
  DROPIN_DIR=/etc/systemd/system/$UNIT.d
  DROPIN=$DROPIN_DIR/10-codex-path.conf
  echo ">> aplicando PATH do runtime dedicado no servico e reiniciando..."
  mkdir -p "$DROPIN_DIR"
  printf '[Service]\nEnvironment="PATH=%s:%s"\n' "$NODE_DIR" "$SYS_PATH" > "$DROPIN"
  chmod 0644 "$DROPIN"
  systemctl daemon-reload
  systemctl restart "$UNIT"
  sleep 2
  if systemctl is-active "$UNIT" >/dev/null 2>&1; then
    echo "   ✅ Codex ligado. O servico voltou no ar."
  else
    echo "   ⚠️ o servico nao voltou active. Veja: journalctl -u $UNIT -n 50 --no-pager" >&2
    exit 1
  fi
  echo ""
  echo "== PRONTO. Agora no Telegram: mande /codex pra trocar pro Codex; /claude volta. =="
  echo "   O motor padrao continua CLAUDE; nada da conversa foi perdido."
  exit 0
fi

# SEC0-user · daqui pra baixo roda como leon (vindo da fase root, ou direto).
_ME="$(id -un)"
if [ "$_ME" != "$LEON_USER" ]; then
  echo "ERRO: rode como root (o terminal do navegador) ou como o usuario '$LEON_USER'. Recebi '$_ME'." >&2
  exit 1
fi
if [ "${HOME:-}" != "/home/$LEON_USER" ]; then
  echo "ERRO: HOME='$HOME' inesperado; esperava /home/$LEON_USER. Use 'sudo -iu $LEON_USER' (login shell reseta HOME)." >&2
  exit 1
fi
INSTALL_DIR="${LEON_DIR:-$HOME/socio-ia}"
ENV_FILE="$INSTALL_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERRO: nao achei a casa LEON em $ENV_FILE. Este script liga o Codex numa casa JA instalada." >&2
  exit 1
fi
WORK="$HOME/.leon/liga-codex"
mkdir -p "$WORK"
say(){ printf '%s\n' "$*"; }

say "== liga-codex · adicionar o motor Codex nesta casa =="
say "   casa: $INSTALL_DIR (o LEON atual segue no ar o tempo todo)"

# ------------------------------------------------------------
# SEC1 · Defaults de TODAS as vars que as funcoes leem bare, sob set -u.
#   (FURO-2 Astra: faltar UM LEON_TEST_* estoura unbound = o bug que quebrou o
#    Bruno. Copiado VERBATIM de install-leon.sh:95-135, byte a byte, ZERO abreviacao.)
# ------------------------------------------------------------
# LEITOR UNICO DAS PASTAS (24/09, rodada 5): LEON_DATA_DIR e as pastas derivadas saem do .env
# da casa (que aqui sempre existe), pelo leitor do bridge; o ambiente nao vale pra elas.
leon_bases_do_dono "$ENV_FILE" || { echo "ERRO: nao consegui ler as pastas do .env desta casa." >&2; exit 1; }
LEON_CODEX_HOME="$LEON_DATA_DIR/codex"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-sol}"
: "${LEON_NODE_VERSION:=22.22.0}"
: "${LEON_CODEX_CLI_VERSION:=0.154.0}"
: "${LEON_NODE_ROOT:=}"
: "${LEON_CODEX_CLI_ROOT:=}"
: "${LEON_NODE_BIN_RESOLVED:=}"
: "${LEON_CODEX_BIN_RESOLVED:=}"
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

# ------------------------------------------------------------
# SEC2 · Extrai as 13 funcoes provadas do install-leon.sh e sourcea SO o extrato.
#   (NAO 'source install-leon.sh': ele nao tem guarda main e reinstalaria a casa.)
# ------------------------------------------------------------
SRC=""
# Fonte das funcoes: LEON_INSTALLER_SRC (bancada/prova) > a CENTRAL (fonte viva) >
# a copia local da casa (~/install-leon.sh, do dia da instalacao — pode estar velha:
# o pin do Codex 0.154.0 mudou depois da instalacao do Bruno, 11/09).
if [ -n "${LEON_INSTALLER_SRC:-}" ] && [ -r "${LEON_INSTALLER_SRC:-}" ]; then
  SRC="$LEON_INSTALLER_SRC"
elif { curl -fsSL -m 30 "${LEON_ESPELHO:-https://raw.githubusercontent.com/molinateston/leon-espelho/main}/install-leon.sh" -o "$WORK/install-leon.src" 2>/dev/null \
       || curl -fsSL -m 30 "$CENTRAL/install-leon.sh" -o "$WORK/install-leon.src" 2>/dev/null; } && [ -s "$WORK/install-leon.src" ]; then
  SRC="$WORK/install-leon.src"
elif [ -r "$HOME/install-leon.sh" ]; then
  SRC="$HOME/install-leon.sh"
  say "   AVISO: sem acesso a central; usando a copia local do instalador."
else
  echo "ERRO: nao consegui obter o install-leon.sh (central e copia local)." >&2; exit 1
fi
FUNCS="$WORK/funcoes.sh"
awk -v names="ensure_node_runtime ensure_codex_cli codex_login_unificado provar_modelo_codex codex_cli_version node_runtime_version repair_managed_prefix_dirs validate_dedicated_node extract_pinned_node_binary verify_codex_package_archive validate_dedicated_codex_cli codex_env_limpo codex_auth_looks_valid" '
  BEGIN{n=split(names,a," ");for(i=1;i<=n;i++)want[a[i]]=1}
  /^[a-z_]+\(\) \{$/{f=$0;sub(/\(\).*/,"",f);cap=(f in want)}
  cap{print}
  cap&&/^\}$/{cap=0}
' "$SRC" > "$FUNCS"
bash -n "$FUNCS" || { echo "ERRO: o extrato de funcoes nao compila (a fonte mudou?)." >&2; exit 1; }
# shellcheck disable=SC1090
source "$FUNCS"
declare -F ensure_node_runtime ensure_codex_cli codex_login_unificado provar_modelo_codex >/dev/null \
  || { echo "ERRO: extracao das 4 funcoes de runtime/login falhou." >&2; exit 1; }
say "   funcoes de runtime/login carregadas da fonte provada."

# ------------------------------------------------------------
# SEC3 · Runtime dedicado do Codex (Node 22.22.0 + Codex CLI 0.154.0 pinados).
#   Idempotente: revalida sem rebaixar. NAO derruba o LEON claude (so instala arquivos).
# ------------------------------------------------------------
say ">> preparando runtime dedicado do Codex (Node $LEON_NODE_VERSION + Codex CLI $LEON_CODEX_CLI_VERSION)..."
ensure_node_runtime  || { echo "ERRO: Node dedicado nao ficou pronto. O LEON atual segue no ar. suporte: https://wa.me/5511988890934" >&2; exit 1; }
ensure_codex_cli     || { echo "ERRO: Codex CLI dedicado nao ficou pronto. O LEON atual segue no ar. suporte: https://wa.me/5511988890934" >&2; exit 1; }

# ------------------------------------------------------------
# SEC4 · Login do Codex + prova do modelo. codex_login_unificado e IDEMPOTENTE:
#   se ja ha auth valido, preserva; senao device-auth (imprime URL no terminal, sem tty).
#   Se qualquer um falhar, ABORTA aqui — o .env ainda NAO foi tocado, LEON claude intacto.
# ------------------------------------------------------------
# CODEX_HOME DA CASA (23/09): o .env e do dono. Se ele declara um CODEX_HOME que nao e a pasta
# do LEON (ou a pasta do LEON e link pro ~/.codex pessoal), e ESSE que o bridge usa: o login e
# a prova do modelo rodam nele, a linha do .env fica como esta e o config.toml dele nao e escrito.
LIGA_CODEX_HOME_DO_DONO=0
if leon_preserva codex-home-do-dono "$ENV_FILE" "$LEON_DATA_DIR" >/dev/null 2>&1; then
  LIGA_CODEX_HOME_DO_DONO=1
  # a pasta que o bridge usa hoje (homeDoMotor): a declarada, ou o ~/.codex com credencial
  # quando o .env nao declara (24/09, rodada 3); pasta do LEON por link fica a do LEON
  LEON_CODEX_HOME="$(leon_preserva home-do-motor "$ENV_FILE" codex "$LEON_CODEX_HOME")"
  say "   CODEX_HOME desta casa e do dono ($LEON_CODEX_HOME): login e prova rodam nele; config.toml dele nao e escrito."
fi
if [ "$LIGA_CODEX_HOME_DO_DONO" = 1 ]; then
  [ -d "$LEON_CODEX_HOME" ] || { mkdir -p "$LEON_CODEX_HOME" && chmod 0700 "$LEON_CODEX_HOME"; }
else
  mkdir -p "$LEON_CODEX_HOME" && chmod 0700 "$LEON_CODEX_HOME"
fi
codex_login_unificado || { echo "ERRO: login do Codex nao concluiu. O LEON atual segue no ar (nada foi trocado). suporte: https://wa.me/5511988890934" >&2; exit 1; }
provar_modelo_codex   || { echo "ERRO: nenhum modelo respondeu nesta conta. O LEON atual segue no ar. suporte: https://wa.me/5511988890934" >&2; exit 1; }
# a partir daqui: CODEX_MODEL = o modelo que passou; LEON_CODEX_BIN_RESOLVED = o codex dedicado.
CODEX_BIN_ENV="${LEON_CODEX_BIN_RESOLVED:-$LEON_DATA_DIR/codex-cli/releases/$LEON_CODEX_CLI_VERSION/bin/codex}"
if [ ! -x "$CODEX_BIN_ENV" ]; then
  echo "ERRO: o binario Codex esperado nao existe/executavel ($CODEX_BIN_ENV). Abortando sem tocar no .env." >&2
  exit 1
fi

# ------------------------------------------------------------
# SEC5 · Liga o bloco Codex no .env EXISTENTE. O .ENV E DO DONO (23/09, desenho estrutural):
#   nenhuma linha que ja existe e reescrita; o bloco Codex entra no FIM so com as chaves que
#   faltam (leon_preserva env-acrescenta, o mesmo do /atualiza e da reinstalacao). CODEX_MODEL,
#   CODEX_REASONING_EFFORT e CODEX_HOME do dono ficam como estao: numa casa Claude o
#   CODEX_MODEL=claude-* e do motor Claude, e o bridge alinha o modelo do Codex ao padrao dele
#   na troca de motor (/codex). A unica troca e da lista PRODUTO_ENV, com o valor invalido
#   provado aqui: CODEX_BIN e LEON_CODEX_CLI_VERSION que apontam pro CLI do produto abaixo do
#   pinado (ou pra binario do produto que nao executa). (FURO-5 Astra: tmp NO MESMO
#   diretorio do .env -> mv atomico, nlink==1, mode 600. NAO mexe em ENGINE/ENGINE_DEFAULT.)
# ------------------------------------------------------------
LIGA_OBRA="$(mktemp -d "$(dirname "$ENV_FILE")/.env-liga.XXXXXX")" || { echo "ERRO: mktemp do .env falhou." >&2; exit 1; }
printf '%s\n' \
  "LEON_CODEX_ONLY=1" \
  "CODEX_APP_SERVER=1" \
  "CODEX_HOME=$(leon_preserva home-do-motor "$ENV_FILE" codex "$LEON_CODEX_HOME")" \
  "CODEX_BIN=$CODEX_BIN_ENV" \
  "CODEX_MODEL=$CODEX_MODEL" \
  "CODEX_REASONING_EFFORT=high" \
  "LEON_CODEX_CLI_VERSION=$LEON_CODEX_CLI_VERSION" > "$LIGA_OBRA/padroes"
: > "$LIGA_OBRA/trocas"
_ver_atual="$(leon_preserva env-valor "$ENV_FILE" LEON_CODEX_CLI_VERSION 2>/dev/null || true)"
_bin_atual="$(leon_preserva env-valor "$ENV_FILE" CODEX_BIN 2>/dev/null || true)"
_ver_troca=0
if [ -n "$_ver_atual" ] && [ "$_ver_atual" != "$LEON_CODEX_CLI_VERSION" ]; then
  if ! printf '%s' "$_ver_atual" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
     || [ "$(printf '%s\n%s\n' "$_ver_atual" "$LEON_CODEX_CLI_VERSION" | sort -V | head -1)" = "$_ver_atual" ]; then
    printf 'LEON_CODEX_CLI_VERSION=%s\n' "$LEON_CODEX_CLI_VERSION" >> "$LIGA_OBRA/trocas"; _ver_troca=1
  fi
fi
if [ -n "$_bin_atual" ] && [ "$_bin_atual" != "$CODEX_BIN_ENV" ]; then
  case "$_bin_atual" in
    "$LEON_DATA_DIR/codex-cli/"*)
      if [ ! -x "$_bin_atual" ] || [ "$_ver_troca" = 1 ]; then
        printf 'CODEX_BIN=%s\n' "$CODEX_BIN_ENV" >> "$LIGA_OBRA/trocas"
      fi ;;
  esac
fi
unset _ver_atual _bin_atual _ver_troca
_LIGA_RC=0
leon_preserva env-acrescenta "$ENV_FILE" "$LIGA_OBRA/padroes" "$LIGA_OBRA/trocas" "$LIGA_OBRA/saida" "$LIGA_OBRA/relatorio" "$LEON_DATA_DIR" || _LIGA_RC=$?
if [ "$_LIGA_RC" -ne 0 ]; then
  echo "ERRO: o .env desta casa tem linha que o LEON recusaria: $(sed -n 's/^recusa //p' "$LIGA_OBRA/relatorio" 2>/dev/null | tr '\n' ' ')" >&2
  echo "Nada foi escrito: o .env e teu e eu nao reescrevo linha tua. Corrija essa linha e rode de novo. O LEON atual segue no ar." >&2
  rm -rf -- "$LIGA_OBRA"; exit 1
fi
if ! cmp -s -- "$ENV_FILE" "$LIGA_OBRA/saida"; then
  cp -p "$ENV_FILE" "$ENV_FILE.bak-liga-codex" 2>/dev/null || true
  chmod 600 "$LIGA_OBRA/saida"
  mv -f -- "$LIGA_OBRA/saida" "$ENV_FILE"
fi
_liga_novas="$(sed -n 's/^\(nova\|religada\) //p' "$LIGA_OBRA/relatorio" | tr '\n' ' ')"
_liga_troc="$(sed -n 's/^trocada //p' "$LIGA_OBRA/relatorio" | tr '\n' ' ')"
_liga_dono="$(sed -n 's/^escolha-do-dono //p' "$LIGA_OBRA/relatorio" | tr '\n' ' ')"
rm -rf -- "$LIGA_OBRA"
say "   .env: nenhuma linha que ja existia foi mudada (ENGINE_DEFAULT preservado; backup em .env.bak-liga-codex)."
[ -z "$_liga_novas" ] || say "   acrescentadas no fim (faltavam): $_liga_novas"
[ -z "$_liga_troc" ] || say "   CLI do Codex do produto abaixo do pinado, corrigido: $_liga_troc"
[ -z "$_liga_dono" ] || say "   mantive a tua escolha: $_liga_dono"
unset _liga_novas _liga_troc _liga_dono _LIGA_RC

# ------------------------------------------------------------
# SEC6 · config.toml do Codex, sem [agents]: os filhos nativos e o papel designer entram
#   pela sobreposicao da thread (lib-motores/codex-appserver.cjs), igual em toda casa.
#   (FURO-4 Astra: nao buscar /download-codex, pode dar 403.)
# ------------------------------------------------------------
{
  cat <<EOF
model = "$CODEX_MODEL"
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
} > "$WORK/config.molde"
# 23/09 (desenho estrutural): o config.toml que ja existe e do dono; o molde so acrescenta o
# que falta (leon_preserva toml-funde). CODEX_HOME do dono (ou pasta do LEON por link): nada e
# escrito. Ilegivel DE VERDADE (python e Codex pinado recusam): o do dono fica ao lado em
# config.toml.ilegivel-<ts> e vai o molde.
if [ "$LIGA_CODEX_HOME_DO_DONO" = 1 ]; then
  say "   config.toml: o CODEX_HOME desta casa e do dono; nao escrevo config.toml nenhum."
else
  _cfg_ts="$(date -u +%Y%m%dT%H%M%SZ)"
  if [ -f "$LEON_CODEX_HOME/config.toml" ]; then
    cp -p -- "$LEON_CODEX_HOME/config.toml" "$LEON_CODEX_HOME/config.toml.anterior-$_cfg_ts" 2>/dev/null || true
  fi
  _cfg_rc=0
  LEON_PRESERVA_CODEX="$CODEX_BIN_ENV" \
  LEON_PRESERVA_PATH="$(dirname "${LEON_NODE_BIN_RESOLVED:-$LEON_DATA_DIR/node/releases/$LEON_NODE_VERSION/bin/node}"):$SYS_PATH" \
    leon_preserva toml-funde "$LEON_CODEX_HOME/config.toml" "$WORK/config.molde" "$WORK/config.novo" "$WORK/config.rel" "$INSTALL_DIR" || _cfg_rc=$?
  case "$_cfg_rc" in
    0) install -m 600 -- "$WORK/config.novo" "$LEON_CODEX_HOME/config.toml"
       say "   config.toml gravado." ;;
    2) [ ! -f "$LEON_CODEX_HOME/config.toml" ] || cp -p -- "$LEON_CODEX_HOME/config.toml" "$LEON_CODEX_HOME/config.toml.ilegivel-$_cfg_ts"
       install -m 600 -- "$WORK/config.molde" "$LEON_CODEX_HOME/config.toml"
       say "   config.toml anterior ilegivel (o Codex tambem recusa): gravei o molde; o teu esta em config.toml.ilegivel-$_cfg_ts." ;;
    *) say "   config.toml: mantido intacto ($(head -1 "$WORK/config.rel"))." ;;
  esac
  unset _cfg_ts _cfg_rc
fi
rm -f -- "$WORK/config.molde" "$WORK/config.novo" "$WORK/config.rel"

# ------------------------------------------------------------
# SEC7 · PATH do servico + restart. O app-server Codex herda o PATH do bridge; o
#   unit atual roda o bridge no node do SISTEMA. Um drop-in poe o node dedicado na
#   frente pro app-server usar a versao pinada. (FURO-3 Astra: daemon-reload e
#   escrever arquivo EXIGEM root; o sudoers do leon NAO cobre. Detecto sudo -n;
#   senao imprimo as 3 linhas pro root colar.)
# ------------------------------------------------------------
if [ "$LEON_LIGA_FASE" = user ]; then
  say "   (fase user concluida; o PATH do servico e o restart ficam com a fase root, que continua agora.)"
  exit 0
fi
NODE_DIR="$(dirname "${LEON_NODE_BIN_RESOLVED:-$LEON_DATA_DIR/node/releases/$LEON_NODE_VERSION/bin/node}")"
UNIT=leon-agente.service
DROPIN_DIR=/etc/systemd/system/$UNIT.d
DROPIN=$DROPIN_DIR/10-codex-path.conf
DROPIN_BODY="[Service]
Environment=\"PATH=$NODE_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""

say ""
if sudo -n true 2>/dev/null; then
  say ">> aplicando PATH do runtime dedicado no servico e reiniciando..."
  sudo mkdir -p "$DROPIN_DIR"
  printf '%s\n' "$DROPIN_BODY" | sudo tee "$DROPIN" >/dev/null
  sudo systemctl daemon-reload
  sudo -n /bin/systemctl restart "$UNIT" || sudo systemctl restart "$UNIT"
  sleep 2
  if sudo -n /bin/systemctl is-active "$UNIT" >/dev/null 2>&1 || systemctl is-active "$UNIT" >/dev/null 2>&1; then
    say "   ✅ Codex ligado. O servico voltou no ar."
  else
    say "   ⚠️ o servico nao voltou active — cole os comandos abaixo como root e cheque o journal."
  fi
else
  say "════════════════════════════════════════════════════════════"
  say "  FALTA 1 PASSO (precisa de root). Cole ISTO como root:"
  say "════════════════════════════════════════════════════════════"
  say "  mkdir -p $DROPIN_DIR"
  say "  printf '%s\\n' '$DROPIN_BODY' > $DROPIN"
  say "  systemctl daemon-reload && systemctl restart $UNIT"
  say "════════════════════════════════════════════════════════════"
  say "  (ate rodar isso, o Codex fica instalado mas o app-server pode usar o node do sistema.)"
fi

say ""
say "== PRONTO. Agora no Telegram: mande /codex pra trocar pro Codex; /claude volta. =="
say "   O motor padrao continua CLAUDE; nada da conversa foi perdido."
exit 0
fi
# ===== FIM LIGA-CODEX =====
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
# REINSTALAR NAO TROCA O MOTOR (23/09, lei do dono). Casa que ja existe diz o motor dela no
# .env (ENGINE_DEFAULT). Sem LEON_ENGINE explicito, vale o dela. Com LEON_ENGINE diferente, o
# instalador para ANTES de mexer em qualquer coisa: trocar de motor e escolha do dono, feita com
# LEON_TROCA_MOTOR=1 (ou pelo /codex e /claude no Telegram), nunca efeito de reinstalar.
_casa_env=""
# a casa e a do usuario do servico: como root (fase root), a home do LEON_USER quando ele ja existe
# (getent sem o usuario sai != 0; sob set -e e pipefail isso matava o instalador calado, rc 2, numa
# VPS nova: || true)
_casa_home=""
if [ "$(id -u)" = 0 ] && [ "$MOCK_MODE" != "1" ]; then
  _casa_home="$(getent passwd "${LEON_USER:-leon}" 2>/dev/null | cut -d: -f6 || true)"
fi
if [ -n "${LEON_DIR:-}" ]; then
  _casa_env="$LEON_DIR/.env"
elif [ "$MOCK_MODE" = "1" ]; then
  _casa_env="$HOME/socio-ia-mock/.env"
else
  _casa_dono="${_casa_home:-$(getent passwd "${LEON_USER:-leon}" 2>/dev/null | cut -d: -f6 || true)}"
  [ -n "$_casa_dono" ] && _casa_env="$_casa_dono/socio-ia/.env"
  unset _casa_dono
fi
_motor_casa=""
if [ -n "$_casa_env" ] && [ -f "$_casa_env" ]; then
  _motor_casa="$(leon_preserva env-valor "$_casa_env" ENGINE_DEFAULT 2>/dev/null || true)"
  [ -n "$_motor_casa" ] || _motor_casa="$(leon_preserva env-valor "$_casa_env" ENGINE 2>/dev/null || true)"
  case "$_motor_casa" in claude|codex) ;; *) _motor_casa="" ;; esac
fi
if [ -n "$_motor_casa" ]; then
  if [ -z "$LEON_ENGINE" ]; then
    LEON_ENGINE="$_motor_casa"
    echo ">> casa ja existente: motor $LEON_ENGINE (o que ela ja usa)."
  elif [ "$LEON_ENGINE" != "$_motor_casa" ] && [ "${LEON_TROCA_MOTOR:-0}" != "1" ]; then
    echo "ERRO: esta casa roda o motor $_motor_casa e o comando pediu $LEON_ENGINE." >&2
    echo "Reinstalar nao troca o motor do dono. Nada foi mexido." >&2
    echo "Pra reinstalar mantendo: rode de novo com LEON_ENGINE=$_motor_casa." >&2
    echo "Pra TROCAR de motor de proposito: rode com LEON_TROCA_MOTOR=1." >&2
    exit 1
  fi
fi
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
# Modelo padrao do segundo motor. Mesmo nome que o bridge oferece no /modelo; o dono
# troca depois pelo proprio comando, sem reinstalar nada.
# Lei do dono (23/09 noite): casa NOVA nasce no Opus (Claude) e no gpt-5.6-sol (Codex), nunca
# no Sonnet. Casa que JA existe nao e tocada: o bloco do .env mais abaixo mantem o modelo dela.
_LEON_CLAUDE_MODEL_DADO="${LEON_CLAUDE_MODEL:-}"
LEON_CLAUDE_MODEL="${LEON_CLAUDE_MODEL:-claude-opus-5-5}"
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
# LEITOR UNICO DAS PASTAS (24/09, rodada 5). Toda pasta sai do .env da casa que ja existe pelo
# leitor do bridge (leon_bases_do_dono, bloco LEON-PRESERVA), na ordem do bridge: LEON_DATA_DIR do
# .env; dele BRAIN_DIR, MEMVIVA_FILE, ASSUNTOS_FILE, LEON_STATE_DIR, LEON_MISSIONS_DIR,
# LEON_PROMISES_DIR, PERSONA_DIR. Antes o ${LEON_DATA_DIR:-$HOME/.leon} vinha antes de ler o .env:
# a casa com LEON_DATA_DIR proprio (~/dados) ganhava BRAIN_DIR, PERSONA_DIR e LEON_STATE_DIR de
# ~/.leon no fim do .env e o bridge passava a ler memoria, persona e estado vazios.
# Instalacao do zero (sem .env): valem as variaveis do comando, senao os padroes do bridge.
# A casa e a do usuario do servico (rodada 6): como root, a home do LEON_USER quando ele ja existe;
# nunca o HOME do root. E a fase root nao herda nada daqui: ela chama o leitor de novo com a home
# do usuario, e o leitor so aceita o que o comando passou (bloco LEON-PRESERVA).
leon_bases_do_dono "${_casa_env:-}" "${_casa_home:-$HOME}" || { echo "ERRO: nao consegui ler as pastas do .env desta casa." >&2; exit 1; }
# a pasta de login e config do Codex que o bridge usa HOJE (homeDoMotor): numa casa que roda no
# ~/.codex do dono, o login e o smoke conferem ELE (sem login a mais) e o config.toml dele nao e
# escrito (codex-home-do-dono). Casa nova: <LEON_DATA_DIR>/codex.
LEON_CODEX_HOME="$(HOME="${_casa_home:-$HOME}" leon_preserva home-do-motor "${_casa_env:-}" codex "$LEON_DATA_DIR/codex")"
unset _casa_env _casa_home
if [ -z "$LEON_SKILLS_DIR" ]; then
  if [ "$LEON_ENGINE" = codex ]; then LEON_SKILLS_DIR="$LEON_DATA_DIR/skills"; else LEON_SKILLS_DIR="$HOME/.claude/skills"; fi
fi
# PERSONA_DIR_LOCAL vale pros DOIS motores (o bridge le a persona/nucleo dela em ambos): a mesma
# PERSONA_DIR do leitor unico.
PERSONA_DIR_LOCAL="$PERSONA_DIR"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-sol}"
LEON_RELEASE_TRUST_FINGERPRINT='eb70521f5e4dd9bb1cd11e6ceb0b2bddd65596558322908a2d04fd3dec5cbe08'

# Versoes homologadas do runtime dedicado do Codex: as mesmas que o
# release-manifest declara e que o update-pago-codex.sh valida.
: "${LEON_NODE_VERSION:=22.22.0}"
: "${LEON_CODEX_CLI_VERSION:=0.154.0}"
: "${LEON_CLAUDE_CLI_MINIMA:=2.1.280}"   # 23/09: minimo do Claude Code (claude-opus-5 exige 2.1.280+)
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

# FONTE PRINCIPAL = GITHUB (23/09, lei do dono: "cliente nenhum pode depender da VPS, e sim de
# repositorio git"). O manifesto assinado e os artefatos livres (runtime, atualizador) vem
# PRIMEIRO do espelho no GitHub (LEON_ESPELHO) e a central vira reserva. A SEGURANCA NAO MUDA:
# quem chama confere chave pinada, assinatura e contrato do manifesto, e sha256+tamanho de cada
# artefato, venha de onde vier, e aborta se nao bater (manifesto ruim nao troca de origem).
# O pacote pago: licenca assinada (LEON_LICENCA_ASSINADA=1) abre a copia cifrada do espelho;
# sem ela, continua a central. Origem usada em MANIFESTO_ORIGEM/ARTEFATO_ORIGEM, no log.
LEON_ESPELHO="${LEON_ESPELHO:-https://raw.githubusercontent.com/molinateston/leon-espelho/main}"
MANIFESTO_ORIGEM=""
ARTEFATO_ORIGEM=""
baixa_par() {  # <base-url> <nome.json> <nome.sig> <saida.json> <saida.sig> <max-json> <connect-timeout>
  local b="$1" nj="$2" ns="$3" oj="$4" os="$5" mj="$6" ct="$7"
  [ -n "$b" ] || return 1
  { : > "$oj" && : > "$os"; } 2>/dev/null || return 1
  curl -fsSL --max-filesize "$mj" --retry 3 --retry-delay 2 --retry-connrefused \
       --connect-timeout "$ct" --max-time 60 "$b/$nj" -o "$oj" 2>/dev/null \
   && curl -fsSL --max-filesize 64 --retry 3 --retry-delay 2 --retry-connrefused \
       --connect-timeout "$ct" --max-time 60 "$b/$ns" -o "$os" 2>/dev/null
}
# So a ASSINATURA do par json/sig pela chave pinada; quem chama confere tudo de novo.
par_confere() {  # <arquivo.json> <arquivo.sig>
  local k
  k="$(mktemp)" || return 1
  if write_release_public_key "$k" \
     && openssl pkeyutl -verify -rawin -pubin -inkey "$k" -in "$1" -sigfile "$2" >/dev/null 2>&1; then
    rm -f -- "$k"; return 0
  fi
  rm -f -- "$k"; return 1
}
# PAR DO ESPELHO QUE NAO CONFERE (23/09 noite): o raw.githubusercontent guarda cache de uns 5 min
# por arquivo, e logo depois de um push pode servir o json novo com o sig velho. A central passa
# pela MESMA verificacao: troca de origem so se o par dela conferir. Nenhum confere: devolve o
# par do espelho e quem chama reprova a assinatura (falha fechada).
MANIFESTO_NOTA=""
baixa_manifesto_assinado() {  # <nome.json> <nome.sig> <saida.json> <saida.sig> <max-json>
  local tj ts
  MANIFESTO_ORIGEM=""; MANIFESTO_NOTA=""
  if [ -n "${LEON_ESPELHO:-}" ] && baixa_par "$LEON_ESPELHO" "$1" "$2" "$3" "$4" "$5" 20; then
    MANIFESTO_ORIGEM=espelho
    par_confere "$3" "$4" && return 0
    MANIFESTO_NOTA="espelho com assinatura invalida"
    tj="$(mktemp)" || return 0
    ts="$(mktemp)" || { rm -f -- "$tj"; return 0; }
    if baixa_par "$CENTRAL" "$1" "$2" "$tj" "$ts" "$5" 10 && par_confere "$tj" "$ts" \
       && cat -- "$tj" > "$3" && cat -- "$ts" > "$4"; then
      MANIFESTO_ORIGEM=central
      MANIFESTO_NOTA="espelho com assinatura invalida (cache do GitHub?); usei a central, par conferido"
    else
      MANIFESTO_NOTA="espelho com assinatura invalida e a central nao entregou par valido"
    fi
    rm -f -- "$tj" "$ts"
    return 0
  fi
  if baixa_par "$CENTRAL" "$1" "$2" "$3" "$4" "$5" 10; then
    MANIFESTO_ORIGEM=central; return 0
  fi
  return 1
}
confere_sha_tamanho() {  # <arquivo> <sha256> <bytes>
  python3 - "$1" "$2" "$3" <<'PY' 2>/dev/null
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
baixa_artefato_verificado() {  # <rel> <destino> <sha256> <bytes>
  local rel="$1" dest="$2" sha="$3" n="$4" nome="${1##*/}"
  ARTEFATO_ORIGEM=""
  if [ -n "${LEON_ESPELHO:-}" ] && [ -n "$nome" ] \
     && curl -fsSL --max-filesize "$n" --retry 3 --retry-delay 2 --retry-connrefused \
          --connect-timeout 20 --max-time 180 "$LEON_ESPELHO/$nome" -o "$dest" 2>/dev/null \
     && confere_sha_tamanho "$dest" "$sha" "$n"; then
    ARTEFATO_ORIGEM=espelho; return 0
  fi
  if curl -fsSL --max-filesize "$n" --retry 3 --retry-delay 2 --retry-connrefused \
       --connect-timeout 10 --max-time 180 "$CENTRAL$rel" -o "$dest" 2>/dev/null \
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
  { [ -n "${LEON_ESPELHO:-}" ] && curl -fsSL --max-filesize 1048576 --retry 2 --retry-delay 2 --connect-timeout 10 --max-time 30 \
      "$LEON_ESPELHO/licencas-revogadas.txt" -o "$2" 2>/dev/null; } \
  || { [ -n "$1" ] && curl -fsSL --max-filesize 1048576 --retry 1 --connect-timeout 5 --max-time 20 \
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
  if curl -fsSL --max-filesize "$((n + 4096))" --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 180 \
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
      platform_sha512=6b8148dc0f2c1adc06aceaa5b6b3dbad2da16a3ac7406e7dd44c2645f891a0b31bd74571741b54196e20bba20955810d898180ee4dcfe239511c4a02654fecf5 ;;
    aarch64|arm64)
      platform_alias=codex-linux-arm64; target_triple=aarch64-unknown-linux-musl
      platform_sha512=2a64c207a493e3ce3379894fa4a3ff2b93ff8116989ade938a1543fb3a2da1ee8ef6ad094813fe158bc2cf803fcd95d1ef10ce1d44534a31e9d2c0fcc164b461 ;;
    *) echo "ERRO: arquitetura sem pacote Codex homologado: $arch." >&2; return 1 ;;
  esac
  main_sha512=155ff1d4e1d762ffe27e37f79978fd4e14d301671464de9c18845046147190a34e3ee226bb5596d1cf1ebf5bd4904f57187f747449d81b5b418c8931462920d3
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
    lib-motores/codex-appserver.cjs lib-motores/claude.cjs lib-motores/index.cjs lib/onboarding.js lib/meta-connect.js lib/meta-graph.js lib/license.js \
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
# Auth do Codex parece utilizavel? (auth.json parseavel com refresh_token OU api key).
# Serve pra NAO disparar device-auth destrutivo quando o "login status" falha por
# AMBIENTE (env -i/PATH limpo), nao por auth ruim. Preserva o login existente.
codex_auth_looks_valid() {
  local auth_file="$LEON_CODEX_HOME/auth.json"
  [ -f "$auth_file" ] || return 1
  python3 - "$auth_file" >/dev/null 2>&1 <<'PY' || return 1
import json,sys
try:
    with open(sys.argv[1]) as f: d=json.load(f)
except Exception: raise SystemExit(1)
if not isinstance(d,dict): raise SystemExit(1)
tok=d.get("tokens") or {}
has_refresh=isinstance(tok,dict) and bool(tok.get("refresh_token"))
has_apikey=bool(d.get("OPENAI_API_KEY"))
raise SystemExit(0 if (has_refresh or has_apikey) else 1)
PY
}

codex_login_unificado() {
  [ -x "$LEON_CODEX_BIN_RESOLVED" ] && [ -x "$LEON_NODE_BIN_RESOLVED" ] \
    || { echo "ERRO: runtime dedicado do Codex ausente na hora do login." >&2; return 1; }

  # 1) Caminho feliz: o proprio codex confirma a sessao.
  if codex_env_limpo login status >/dev/null 2>&1; then
    echo ">> Codex ja esta autenticado nesta VPS."
    return 0
  fi

  # 2) "login status" falhou. Pode ser AMBIENTE (env -i/PATH limpo), nao auth ruim.
  #    Se existe auth.json parseavel com credencial, PRESERVA e NUNCA dispara
  #    device-auth (que apagaria o auth existente sem poder completar sem tty).
  #    O bug que mutou Delano/99: reinstalacao nao-interativa rodava device-auth
  #    cego, destruia o auth valido, e o cliente ficava mudo. O /login pelo
  #    Telegram (2.4.4) faz o relogin depois se o refresh expirou de verdade.
  if codex_auth_looks_valid; then
    echo ">> Codex ja tem credencial nesta VPS (login preservado; relogin pelo /login se precisar)."
    return 0
  fi

  # 3) Sem auth utilizavel: device-auth. Ele NAO precisa de tty — imprime a URL + o
  #    codigo de uso unico no stdout, o dono autoriza no navegador e o CLI faz polling
  #    ate completar. Isso e o que faz a instalacao em UM passo (curl|bash) funcionar.
  #    (03/09: a guarda de tty daqui abortava o curl|bash e quebrou o um-passo; provado
  #    no 99 que device-auth imprime a URL sem tty. O passo 2 acima ja protege um
  #    auth.json valido; aqui nao ha auth util, entao device-auth e seguro.)
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
    echo "abortando: sem modelo respondendo o LEON subiria mudo. suporte: https://wa.me/5511988890934" >&2
    return 1
  done
  echo "ERRO: nenhum modelo (${candidatos}) esta disponivel nesta conta ChatGPT." >&2
  echo "abortando. suporte: https://wa.me/5511988890934" >&2
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
  # FASE B: a unit ENDURECIDA vale pros dois motores. Ela e a mesma peca de seguranca
  # (sem privilegio novo, sem device, capacidades zeradas, teto de memoria e tarefa), e
  # o unico ponto que muda entre motores e o binario do Node e o diretorio. Deixar o
  # segundo motor na unit simples historica seria servir a mesma casa com metade da
  # protecao, e o validate_service_unit do atualizador reprova quem nao tem o perfil.
  # CONTENCAO DE MEMORIA (25/09, prova no mestre): um script fujao de skill chegou a 17 GB.
  # MemoryHigh estrangula TODO processo da unit enquanto o uso fica entre High e Max, e
  # com swap sem teto o fujao nunca chega ao Max: o LEON congelou 2 h sem OOM. Sem High,
  # com swap limitado e OOMPolicy=continue, o kernel mata so o fujao e a unit segue viva.
  if [ "$engine" = codex ] || [ "$engine" = claude ]; then
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
TimeoutStopSec=330
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
MemoryHigh=infinity
MemoryMax=90%
MemorySwapMax=1G
OOMPolicy=continue

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
  # v2 (24/09, rodada 5): o bloco v1 exportava a linha crua do .env; o leon-base publicado ja traz
  # o v1, entao o v1 e TROCADO pelo v2 (mesma posicao), nao so pulado.
  if grep -q 'LEON-HANDOFF-UPDATE v2' "$vigia"; then
    echo "   handoff do /atualiza ja presente no vigia."
    return 0
  fi
  tmp="$vigia.leon-new"
  python3 - "$vigia" "$tmp" <<'PY' || { rm -f -- "$tmp"; echo "ERRO: nao consegui gravar o handoff do /atualiza no vigia. suporte: https://wa.me/5511988890934" >&2; return 1; }
import os, re, sys
src, dst = sys.argv[1:]
text = open(src, encoding="utf-8").read()
bloco = r'''# --- LEON-HANDOFF-UPDATE v2 (gravado pelo instalador) ------------------
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
    echo "ERRO: o vigia com o handoff nao compila; original preservado. suporte: https://wa.me/5511988890934" >&2
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

# Rede primaria: confere a licenca do e-mail na central ANTES de baixar o motor,
# pra pegar e-mail digitado errado no primeiro segundo (o download tem o gate real).
# So o 404 explicito (email_nao_encontrado) para. Central fora do ar ou resposta
# inesperada nao emperra: segue pro download, que confere de novo.
if [ "$MOCK_MODE" != "1" ]; then
  EMAIL_ENC_CHK=$(printf %s "$EMAIL" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))" 2>/dev/null || printf %s "$EMAIL")
  STATUS_CODE=$(curl -sS --connect-timeout 10 --max-time 20 -o /dev/null -w "%{http_code}" "$CENTRAL/status?email=$EMAIL_ENC_CHK" 2>/dev/null || echo "000")
  if [ "$STATUS_CODE" = "404" ]; then
    echo "" >&2
    echo "O e-mail que voce digitou foi: $EMAIL" >&2
    echo "Nao achei licenca pra ele na central." >&2
    echo "Confere se esta EXATAMENTE igual ao da compra: sem espaco, com o dominio certo (gmail, ymail, hotmail)." >&2
    echo "Se estiver certo e voce comprou agora, aguarde 1 min e rode de novo." >&2
    echo "Suporte: https://wa.me/5511988890934" >&2
    exit 1
  fi
fi

echo ""
echo "========================================"
echo "  PROJETO LEON · Socio IA 24x7"
LEON_INSTALLER_STAMP="2026-09-21 10:52"
echo "  instalador oficial"
echo "  revisao do instalador: $LEON_INSTALLER_STAMP"
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
    || { echo "ERRO: 'runuser' (util-linux) nao existe nesta VPS. suporte: https://wa.me/5511988890934" >&2; exit 1; }

  # GUARDA DA UNIT ORFA (21/09/2026). Medido na bancada
  # leon-inst-ubuntu2404-18set: a unit ficou em /etc com
  # WorkingDirectory=/home/leon/socio-ia, mas o diretorio nao existia. Todo
  # systemctl restart morria com status=200/CHDIR, enquanto o processo antigo
  # ainda vivo seguia respondendo no Telegram: a casa parecia boa e so quebrava
  # quando o cliente reiniciava.
  #
  # POR QUE ACONTECE: o trap religar_servico_antigo_se_abortar cobre saida
  # normal e INT/TERM, mas morte nao-interceptavel (SIGKILL, OOM, queda de SSH,
  # reboot do provedor) pula o trap e deixa unit + sudoers no disco apontando
  # pra um runtime que a fase user nunca terminou de popular.
  #
  # TEM QUE VIR ANTES do 'is-active' abaixo: unit orfa NUNCA esta ativa (ela
  # falha em 200/CHDIR), entao aquele bloco nao a enxerga e o instalador seguia
  # por cima do entulho. Vem antes de apt, do pivot e de qualquer credencial:
  # detectar casa quebrada e a primeira coisa, nao a ultima.
  if [ -f /etc/systemd/system/leon-agente.service ] && [ ! -L /etc/systemd/system/leon-agente.service ]; then
    UNIT_RUNTIME_ATUAL="$(sed -n 's/^WorkingDirectory=//p' /etc/systemd/system/leon-agente.service | head -n1)"
    if [ -n "$UNIT_RUNTIME_ATUAL" ] && [ ! -e "$UNIT_RUNTIME_ATUAL/bridge.cjs" ]; then
      UNIT_ORFA_BACKUP="/etc/systemd/system/leon-agente.service.orfa-$(date -u +%Y%m%dT%H%M%SZ)"
      echo ">> a casa anterior ficou sem runtime em '$UNIT_RUNTIME_ATUAL'."
      echo "   (uma instalacao anterior foi interrompida antes de terminar)"
      echo "   guardando a unit quebrada em $UNIT_ORFA_BACKUP e recomecando limpo."
      systemctl stop leon-agente.service >/dev/null 2>&1 || true
      systemctl disable leon-agente.service >/dev/null 2>&1 || true
      cp -p -- /etc/systemd/system/leon-agente.service "$UNIT_ORFA_BACKUP" 2>/dev/null || true
      rm -f -- /etc/systemd/system/leon-agente.service
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl reset-failed leon-agente.service >/dev/null 2>&1 || true
    fi
    unset UNIT_RUNTIME_ATUAL
  fi

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
  # SEGUNDA TENTATIVA (cliente 18/09): Debian 11 com espelho de security desatualizado
  # devolveu 404 num .deb; um apt-get update novo + --fix-missing resolveu na hora.
  echo ">> instalando pacotes do sistema (git, curl, python3, ffmpeg, cron...)..."
  PACOTES_BASE=(
    git curl ca-certificates tar cron
    python3 python3-venv python3-pip ffmpeg
    dbus-user-session locales sudo
  )
  if ! "${APT_INSTALL[@]}" "${PACOTES_BASE[@]}" >/dev/null 2>/tmp/apt-base.err; then
    echo "   (aviso) pacotes nao vieram na primeira tentativa; atualizo o indice e tento de novo..."
    apt-get update -qq >/dev/null 2>>/tmp/apt-base.err || true
    if ! "${APT_INSTALL[@]}" --fix-missing "${PACOTES_BASE[@]}" >/dev/null 2>>/tmp/apt-base.err; then
      # TERCEIRA TENTATIVA (clientes 19/09, Debian 11): o apt recusa renovar o indice de um
      # Release vencido ("Valid-Until" passou) e continua pedindo .deb que o espelho ja trocou
      # (404 no security.debian.org). Renovar o indice ACEITANDO o Release vencido resolve.
      # (A versao anterior deste bloco apontava security.debian.org pro archive.debian.org:
      # ERRADO, o bullseye-security ainda NAO esta no archive; se uma rodada antiga trocou a
      # fonte, desfaz aqui.)
      echo "   (aviso) segunda tentativa tambem falhou; renovo o indice aceitando repositorio vencido..."
      for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [ -f "$f" ] || continue
        if grep -qE "archive\.debian\.org/debian-security" "$f"; then
          sed -i -E 's#https?://archive\.debian\.org/debian-security#http://security.debian.org/debian-security#g' "$f"
        fi
      done
      apt-get update -o Acquire::Check-Valid-Until=false --allow-releaseinfo-change >/dev/null 2>>/tmp/apt-base.err || true
      if ! "${APT_INSTALL[@]}" -o Acquire::Check-Valid-Until=false --fix-missing "${PACOTES_BASE[@]}" >/dev/null 2>>/tmp/apt-base.err; then
        # 19/09, provado em container Debian 11 real: o pool do bullseye-security foi REMOVIDO
        # do security.debian.org (48 .deb em 404, de python3-pip a curl e ffmpeg) e ainda nao
        # esta no archive.debian.org. Instalar so do espelho principal tambem nao da: o sistema
        # ja tem perl-base/libsystemd0 em versao do security e o apt recusa (held broken).
        # Nao existe conserto por script hoje. O caminho certo e recriar a VPS com um sistema
        # suportado. Dizer isso claro vale mais que uma quinta tentativa que falha igual.
        DISTRO_ID=$(. /etc/os-release 2>/dev/null; echo "${ID:-}"); DISTRO_VER=$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-}")
        if [ "$DISTRO_ID" = "debian" ] && [ "${DISTRO_VER%%.*}" = "11" ] && grep -qE "security\.debian\.org.*404|debian-security.*404" /tmp/apt-base.err 2>/dev/null; then
          echo "" >&2
          echo "ERRO: esta VPS roda Debian 11, que saiu de suporte, e a Debian removeu os pacotes de seguranca dele (o apt devolve 404 em quase tudo). Nao tem como instalar programas nela hoje, nem o LEON nem outra coisa." >&2
          echo "CONSERTO (5 minutos): no painel da hospedagem, reinstale o sistema da VPS escolhendo Ubuntu 24.04 ou Debian 12, e rode este mesmo comando de novo. Nada do LEON foi criado ainda, entao nao se perde nada." >&2
          echo "suporte: https://wa.me/5511988890934" >&2; exit 1
        fi
        echo "ERRO: pacotes base do sistema nao instalaram." >&2
        [ -s /tmp/apt-base.err ] && echo "detalhe apt: $(tail -n 3 /tmp/apt-base.err)" >&2
        echo "abortando. suporte: https://wa.me/5511988890934" >&2; exit 1
      fi
    fi
  fi
  # CRON ROBUSTO (fix bug-de-nascenca 01/09): o `|| true` cego deixava a casa nascer
  # com o cron MORTO sem ninguem saber — e o /atualiza (que roda pelo cron) travava
  # eterno. Agora liga de verdade, desmascara, e CONFERE. O motor reserva (leon-vigia.timer,
  # criado adiante) garante o /atualiza mesmo se o cron ainda assim nao subir.
  systemctl unmask cron >/dev/null 2>&1 || true
  systemctl enable --now cron >/dev/null 2>&1 || true
  systemctl is-active --quiet cron 2>/dev/null || { service cron start >/dev/null 2>&1 || true; sleep 1; }
  if systemctl is-active --quiet cron 2>/dev/null || pgrep -x cron >/dev/null 2>&1; then
    echo "   cron: ativo."
  else
    echo "   AVISO: o cron nao subiu nesta VPS. O /atualiza fica garantido pelo motor reserva"
    echo "     (leon-vigia.timer); backup e rotinas dependem de religar o cron depois."
  fi
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
    # SCHEMA DO 2o CEREBRO: NAO aplicamos aqui. Aqui INSTALL_DIR ainda nao existe (nasce ~L1338) e o
    # bundle ainda nao foi extraido, entao "$INSTALL_DIR/schema/schema-leon.sql" era 'unbound variable'
    # sob set -u e TRAVAVA a instalacao (bug 10/09->11/09). Quem garante o schema e o proprio bridge no
    # 1o boot (garanteSchemaBanco: existsSync do schema-leon.sql relativo ao bridge, aplica idempotente;
    # se faltar, segue e a memoria cai no "" tolerante). Banco vazio ate la NAO derruba nada.
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
    echo "abortando. suporte: https://wa.me/5511988890934" >&2
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
      echo "abortando. suporte: https://wa.me/5511988890934" >&2
      exit 1
    fi
    # 23/09 (caso real de cliente): o passo acima so instalava quando FALTAVA. Uma casa com o
    # Claude Code 2.1.246 reinstalada seguia na 2.1.246 e o claude-opus-5 do .env recusava toda
    # fala ("version 2.1.280 or newer is required"). Irmao do pin do Codex: garante a minima com
    # o MESMO comando do npm do sistema. Falha aqui nao aborta (o CLI existe e o Sonnet responde);
    # o atualizador e o bridge tentam de novo.
    claude_cli_versao() { PATH="$SYS_PATH" claude --version 2>/dev/null | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }' || true; }
    claude_cli_minima_ok() {
      local v; v="$(claude_cli_versao)"
      [ -n "$v" ] && [ "$(printf '%s\n%s\n' "$LEON_CLAUDE_CLI_MINIMA" "$v" | sort -V | head -n 1)" = "$LEON_CLAUDE_CLI_MINIMA" ]
    }
    if ! claude_cli_minima_ok; then
      echo ">> o Claude Code desta VPS ($(claude_cli_versao || true)) esta abaixo do minimo $LEON_CLAUDE_CLI_MINIMA; atualizando (npm do sistema)..."
      PATH="$SYS_PATH" /usr/bin/node /usr/bin/npm install -g --prefix=/usr @anthropic-ai/claude-code@latest \
        >/dev/null 2>/tmp/npm-claude.err || true
      if claude_cli_minima_ok; then
        echo "   Claude Code atualizado."
      else
        echo "   AVISO: nao consegui atualizar o Claude Code agora (sigo na $(claude_cli_versao || echo 'versao atual')). O LEON responde no Sonnet e tenta atualizar sozinho depois." >&2
        [ -s /tmp/npm-claude.err ] && echo "   detalhe npm: $(tail -n 3 /tmp/npm-claude.err)" >&2
      fi
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
  # o Node dedicado e as vozes moram na LEON_DATA_DIR da casa (a fase user instala e confere la,
  # e o .env aponta VOICE_PY/PIPER_BIN/EDGE_TTS_PY pra la): o leitor unico le a base do .env da
  # casa com a home do usuario do servico (24/09, rodada 5)
  leon_bases_do_dono "$INSTALL_DIR_TMP/.env" "$LEON_HOME_TMP" \
    || { echo "ERRO: nao consegui ler as pastas do .env da casa." >&2; exit 1; }
  if [ "$LEON_ENGINE" = codex ]; then
    NODE_BIN_UNIT="$LEON_DATA_DIR/node/releases/$LEON_NODE_VERSION/bin/node"
  else
    NODE_BIN_UNIT=/usr/bin/node
  fi
  # A unit nasce aqui APONTANDO pra um dir que a fase user ainda vai popular:
  # nesta altura o runtime legitimamente nao existe, entao o node --check NAO
  # cabe aqui. A trava do runtime mora no ponto onde a unit de fato vira
  # servico (secao 2.8, antes do 'enable --now'). O que cabe aqui e nao deixar
  # /etc apontando pra um caminho pior do que o que ja estava: se a unit
  # anterior era orfa, a guarda de entrada ja a aposentou.
  write_service_unit /etc/systemd/system/leon-agente.service "$LEON_USER" "$INSTALL_DIR_TMP" "$NODE_BIN_UNIT" "$LEON_ENGINE"
  systemctl daemon-reload

  # MOTOR RESERVA (fix bug-de-nascenca 01/09): o /atualiza depende de um vigia
  # (scripts/update-verdict.sh) que so o cron rodava — cron morto = /atualiza travado
  # eterno. Este timer do systemd (SYSTEM, imune ao cron) roda o MESMO vigia a cada
  # minuto no segundo :30 (fora de fase do cron no :00). O vigia tem trava atomica
  # (mkdir), entao cron + timer coexistem sem duplicar. Casa nova nasce imune: mesmo
  # sem cron, o LEON se atualiza sozinho.
  cat > /etc/systemd/system/leon-vigia.service <<EOF
[Unit]
Description=LEON vigia do /atualiza (motor reserva, independente do cron)
[Service]
Type=oneshot
User=$LEON_USER
WorkingDirectory=$INSTALL_DIR_TMP
ExecStart=/usr/bin/env bash $INSTALL_DIR_TMP/scripts/update-verdict.sh
KillMode=process
TimeoutStartSec=90
EOF
  cat > /etc/systemd/system/leon-vigia.timer <<EOF
[Unit]
Description=LEON vigia a cada minuto (motor reserva do /atualiza, independente do cron)
[Timer]
OnCalendar=*-*-* *:*:30
AccuracySec=1s
Persistent=false
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now leon-vigia.timer >/dev/null 2>&1 \
    && echo "   motor reserva do /atualiza: ativo (imune ao cron)." \
    || echo "   AVISO: motor reserva nao ativou; /atualiza depende so do cron."

  # Libera $LEON_USER a controlar SOMENTE o proprio service (sudo estreito, sem senha).
  # journalctl SEM coringa no fim e SEMPRE com --no-pager: com coringa, o agente podia pedir
  # uma saida que abre o "less" como root, e o less tem um comando (!) que abre terminal — ai
  # o acesso "estreito" virava root de verdade. Duas linhas fixas (com e sem -f) cobrem o uso
  # real (ver log recente, acompanhar ao vivo) sem deixar escolher flag nenhuma.
  # AUTO-CURA DO CRON (01/09): o LEON detecta o cron morto (cronDaemonVivo no bridge) e
  # PODE religar sozinho — sem o dono leigo tocar no terminal. Escopo ESTREITO: so os
  # comandos exatos de religar o cron e o motor reserva (nada de coringa, nada de shell).
  # Nao e "root de verdade": e um punhado de systemctl fixos, cada um cravado.
  cat > /etc/sudoers.d/leon-agente <<EOF
$LEON_USER ALL=(root) NOPASSWD: /bin/systemctl start leon-agente.service, /bin/systemctl stop leon-agente.service, /bin/systemctl restart leon-agente.service, /bin/systemctl enable leon-agente.service, /bin/systemctl disable leon-agente.service, /bin/systemctl status leon-agente.service, /bin/systemctl is-active leon-agente.service, /bin/systemctl enable --now leon-agente.service, /usr/bin/journalctl -u leon-agente.service -n 200 --no-pager, /usr/bin/journalctl -u leon-agente.service -n 200 --no-pager -f, /bin/systemctl unmask cron, /bin/systemctl enable --now cron, /bin/systemctl start cron, /bin/systemctl is-active cron, /bin/systemctl enable --now leon-vigia.timer, /bin/systemctl start leon-vigia.timer, /bin/systemctl is-active leon-vigia.timer
EOF
  chmod 0440 /etc/sudoers.d/leon-agente
  visudo -cf /etc/sudoers.d/leon-agente >/dev/null 2>&1 || echo "   AVISO: sudoers do leon-agente falhou na validacao (visudo)."
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
  como_leon env LEON_DADOS="$LEON_DATA_DIR" bash -s <<'PIPER_SETUP' || { echo "ERRO: a voz local (Piper TTS) nao instalou. suporte: https://wa.me/5511988890934" >&2; exit 1; }
set -e
mkdir -p "$LEON_DADOS"/piper-venv "$LEON_DADOS"/voices/piper
if [ ! -x "$LEON_DADOS"/piper-venv/bin/piper ]; then
  python3 -m venv "$LEON_DADOS"/piper-venv
  "$LEON_DADOS"/piper-venv/bin/pip install --quiet piper-tts >/dev/null
fi
for f in pt_BR-faber-medium.onnx pt_BR-faber-medium.onnx.json; do
  if [ ! -s "$LEON_DADOS"/voices/piper/$f ]; then
    curl -sfL -o "$LEON_DADOS"/voices/piper/$f.part "https://huggingface.co/rhasspy/piper-voices/resolve/main/pt/pt_BR/faber/medium/$f"
    mv -f "$LEON_DADOS"/voices/piper/$f.part "$LEON_DADOS"/voices/piper/$f
  fi
done
PIPER_SETUP

  echo ">> instalando voz nuvem gratis (Edge TTS · Antonio/Francisca)..."
  como_leon env LEON_DADOS="$LEON_DATA_DIR" bash -s <<'EDGE_SETUP' || { echo "ERRO: a voz nuvem (Edge TTS) nao instalou. suporte: https://wa.me/5511988890934" >&2; exit 1; }
set -e
mkdir -p "$LEON_DADOS"/edgetts-venv
if [ ! -x "$LEON_DADOS"/edgetts-venv/bin/edge-tts ]; then
  python3 -m venv "$LEON_DADOS"/edgetts-venv
  "$LEON_DADOS"/edgetts-venv/bin/pip install --quiet edge-tts >/dev/null
fi
EDGE_SETUP

  echo ">> instalando transcricao de audio local (faster-whisper)..."
  como_leon env LEON_DADOS="$LEON_DATA_DIR" bash -s <<'WHISPER_SETUP' || { echo "ERRO: a transcricao de audio (faster-whisper) nao instalou. suporte: https://wa.me/5511988890934" >&2; exit 1; }
set -e
mkdir -p "$LEON_DADOS"/whisper-venv
if [ ! -x "$LEON_DADOS"/whisper-venv/bin/python3 ] || ! "$LEON_DADOS"/whisper-venv/bin/python3 -c "import faster_whisper" 2>/dev/null; then
  python3 -m venv "$LEON_DADOS"/whisper-venv
  "$LEON_DADOS"/whisper-venv/bin/pip install --quiet --upgrade pip >/dev/null
  "$LEON_DADOS"/whisper-venv/bin/pip install --quiet faster-whisper >/dev/null
fi
# 25/08 (lei do dono: "transcricao TEM que ser nativa"): o modelo baixa AGORA, na
# instalacao — nao no primeiro audio do cliente. Sem isto, o primeiro audio dele
# virava "roda /audio e espera uns minutos": vergonha na frente de cliente novo.
# Baixa 'small' (o mesmo do voice-handler); ~460MB, uma vez so. Falha nao derruba
# a instalacao (sem rede pro hub = o updater baixa no proximo ciclo).
timeout 600 "$LEON_DADOS"/whisper-venv/bin/python3 - <<'PYMODEL' || echo "   (aviso) modelo de audio nao baixou agora; o proximo update completa"
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
        echo "abortando. suporte: https://wa.me/5511988890934" >&2
        exit 1
      fi
    fi
  fi

  # Leva este mesmo script pra home do user e re-executa como ele (env vars preservadas).
  # 23/09 (cliente sem VPS): se o script roda de um arquivo (o comando oficial baixa pra um
  # arquivo antes), copia ELE MESMO: os mesmos bytes que o dono ja rodou, sem rede. So quando
  # veio por pipe baixa de novo, do GitHub primeiro e da central de reserva.
  LEON_HOME="$LEON_HOME_TMP"
  if [ -f "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]}" ] && bash -n "${BASH_SOURCE[0]}" 2>/dev/null; then
    cp -- "${BASH_SOURCE[0]}" "$LEON_HOME/install-leon.sh.novo" && mv -f -- "$LEON_HOME/install-leon.sh.novo" "$LEON_HOME/install-leon.sh" \
      || { echo "ERRO: falha ao copiar o instalador pra $LEON_HOME/install-leon.sh." >&2; exit 1; }
  elif ! { [ -n "${LEON_ESPELHO:-}" ] && curl -fsSL --connect-timeout 20 --max-time 120 "$LEON_ESPELHO/install-leon.sh" -o "$LEON_HOME/install-leon.sh"; } \
       && ! curl -fsSL --connect-timeout 10 --max-time 120 "$CENTRAL/install-leon.sh" -o "$LEON_HOME/install-leon.sh"; then
    echo "ERRO: falha ao baixar o install-leon.sh (GitHub e central) pra $LEON_HOME/install-leon.sh." >&2
    exit 1
  fi
  chown "$LEON_USER:$LEON_USER" "$LEON_HOME/install-leon.sh"
  chmod 0755 "$LEON_HOME/install-leon.sh"
  if [ ! -s "$LEON_HOME/install-leon.sh" ]; then
    echo "ERRO: $LEON_HOME/install-leon.sh vazio apos download." >&2
    exit 1
  fi

  # 30/09 (cliente real): arquivo do root dentro da casa (comando antigo rodado como root) barrava o cp da
  # fase do usuario com "Permissao negada". A casa volta pro usuario antes do pulo; -h nao segue link.
  if [ -d "$INSTALL_DIR_TMP" ] && [ ! -L "$INSTALL_DIR_TMP" ]; then
    find "$INSTALL_DIR_TMP" -xdev ! -user "$LEON_USER" -exec chown -h "$LEON_USER:$LEON_USER" {} + 2>/dev/null || true
  fi
  echo ""
  echo "========================================"
  echo "  PASSO ROOT · CONCLUIDO"
  echo "========================================"
  echo "Continuando como '$LEON_USER'..."
  echo ""

  # Pivota com runuser (sem sudoers) e env EXPLICITO: o cwd vai pra home do leon
  # (o de root nao e legivel por ele) e so o que a fase user precisa atravessa.
  # As pastas atravessam pro usuario (rodada 6): a LEON_DATA_DIR que esta fase resolveu (unit,
  # Node e vozes ja estao nela) e as outras que o COMANDO passou. Com .env na casa, o leitor da fase
  # do usuario so le o .env; sem .env, as duas fases caem na mesma pasta.
  _passa_bases=("LEON_DATA_DIR=$LEON_DATA_DIR")
  for _p in "${_LEON_BASES_DO_COMANDO[@]}"; do
    case "$_p" in LEON_DATA_DIR=*|*=) ;; *) _passa_bases+=("$_p") ;; esac
  done
  cd "$LEON_HOME"
  exec runuser -u "$LEON_USER" -- env -i \
    HOME="$LEON_HOME" USER="$LEON_USER" LOGNAME="$LEON_USER" PATH="$SYS_PATH" \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM="${TERM:-dumb}" \
    "${_passa_bases[@]}" \
    EMAIL="$EMAIL" \
    NOME="$NOME" \
    GENDER="$GENDER" \
    BOT_TOKEN="$BOT_TOKEN" \
    MOCK_MODE="$MOCK_MODE" \
    LEON_ENGINE="$LEON_ENGINE" \
    LEON_TROCA_MOTOR="${LEON_TROCA_MOTOR:-0}" \
    LEON_CENTRAL="$CENTRAL" \
    LEON_DIR="${LEON_DIR:-}" \
    OWNER_CHAT_ID="${OWNER_CHAT_ID:-}" \
    CODEX_MODEL="$CODEX_MODEL" \
    LEON_SERVICO_PARADO_PELO_INSTALADOR="${LEON_SERVICO_PARADO_PELO_INSTALADOR:-}" \
    LEON_ESPELHO="${LEON_ESPELHO:-}" \
    LEON_LICENCA_ASSINADA="${LEON_LICENCA_ASSINADA:-0}" \
    LEON_LICENCA="${LEON_LICENCA:-}" \
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
    # GATE DA SAIDA (21/09/2026): nunca religar uma unit que aponta pra caminho
    # inexistente. O start so produziria 200/CHDIR e a casa ficaria "falhando
    # em silencio" em vez de honestamente parada. Melhor dizer a verdade.
    UNIT_RUNTIME_ROLLBACK="$(sed -n 's/^WorkingDirectory=//p' /etc/systemd/system/leon-agente.service | head -n1)"
    if [ -n "$UNIT_RUNTIME_ROLLBACK" ] && [ ! -e "$UNIT_RUNTIME_ROLLBACK/bridge.cjs" ]; then
      echo ">> instalacao abortada e o LEON antigo nao existe mais em '$UNIT_RUNTIME_ROLLBACK': nao religo o servico (ele so daria erro)." >&2
      echo "   rode a instalacao de novo. suporte: https://wa.me/5511988890934" >&2
      exit "$rc"
    fi
    if sudo -n /bin/systemctl start leon-agente.service >/dev/null 2>&1; then
      echo ">> instalacao abortada; o LEON antigo foi religado e continua no ar." >&2
    else
      echo ">> instalacao abortada e nao consegui religar o LEON antigo sozinho: rode 'sudo systemctl start leon-agente.service' como root. suporte: https://wa.me/5511988890934" >&2
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
      || { echo "ERRO: o Node dedicado $LEON_NODE_VERSION nao ficou pronto. suporte: https://wa.me/5511988890934" >&2; exit 1; }
    ensure_codex_cli \
      || { echo "ERRO: o Codex CLI $LEON_CODEX_CLI_VERSION nao ficou pronto. suporte: https://wa.me/5511988890934" >&2; exit 1; }
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
    # pasta do dono (~/.codex que o bridge ja usa): so cria se faltar, sem mexer no modo dela
    if [ "$LEON_CODEX_HOME" = "$LEON_DATA_DIR/codex" ]; then
      mkdir -p "$LEON_CODEX_HOME" && chmod 0700 "$LEON_CODEX_HOME"
    else
      [ -d "$LEON_CODEX_HOME" ] || { mkdir -p "$LEON_CODEX_HOME" && chmod 0700 "$LEON_CODEX_HOME"; }
    fi
    codex_login_unificado || { echo "ERRO: login do Codex falhou. suporte: https://wa.me/5511988890934" >&2; exit 1; }
    provar_modelo_codex || exit 1
    echo ""
  # a pasta de login do Claude que o bridge usa HOJE (homeDoMotor: CLAUDE_CONFIG_DIR do .env, o
  # ~/.claude com credencial ou <LEON_DATA_DIR>/claude): casa ja logada la nao pede login a mais
  elif [ ! -f "$HOME/.claude/.credentials.json" ] \
       && [ ! -f "$(leon_preserva home-do-motor "$INSTALL_DIR/.env" claude "$LEON_DATA_DIR/claude")/.credentials.json" ]; then
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

# LEON_LICENCA (o documento leon1.... que a central emitiu na compra) vira o arquivo de estado
# da casa, FORA da pasta do programa, 0600. So grava o que confere com a chave pinada.
grava_licenca_assinada() {
  [ "${LEON_LICENCA_ASSINADA:-0}" = 1 ] && [ -n "${LEON_LICENCA:-}" ] || return 0
  local tmp
  ( umask 077; mkdir -p -- "$LEON_STATE_DIR" ) || return 0
  tmp="$(mktemp "$LEON_STATE_DIR/.licenca.XXXXXX")" || return 0
  python3 -c 'import json,sys; print(json.dumps({"token": sys.argv[1].strip()}))' "$LEON_LICENCA" > "$tmp" 2>/dev/null
  if licenca_confere "$tmp" >/dev/null; then
    chmod 0600 "$tmp" && mv -f -- "$tmp" "$LEON_STATE_DIR/licenca-assinada.json"
    echo ">> licenca assinada conferida offline e guardada."
  else
    rm -f -- "$tmp"
    echo "ATENCAO: a licenca assinada informada nao confere (documento incompleto, adulterado ou sem chave pinada nesta versao); sigo pelo caminho da central." >&2
  fi
}

# (01/10, caso Delano) casa vinda de 2.7.x por atualizacao tem os arquivos do pacote 0400/0444 do dono
# (o bundle vem 0444 e o atualizador tira go-rwx) e o cp -a por cima abortava com "Permissao negada".
# Devolve a escrita SO no que o cp vai sobrescrever: caminho da casa sem escrita que a origem tambem traz
# (arquivo: u+w; diretorio: u+wx). Varre so a casa, sem seguir link nem sair do disco; o que e so do dono
# fica com o modo que tinha.
libera_escrita_do_pacote() {  # libera_escrita_do_pacote <origem> <casa>
  local _rel
  [ -d "$1" ] && [ -d "$2" ] && [ ! -L "$2" ] || return 0
  while IFS= read -r -d '' _rel; do
    if [ -f "$1/$_rel" ] && [ ! -L "$1/$_rel" ] && [ -f "$2/$_rel" ] && [ ! -L "$2/$_rel" ]; then
      chmod u+w -- "$2/$_rel" 2>/dev/null || true
    elif [ -d "$1/$_rel" ] && [ ! -L "$1/$_rel" ] && [ -d "$2/$_rel" ] && [ ! -L "$2/$_rel" ]; then
      chmod u+wx -- "$2/$_rel" 2>/dev/null || true
    fi
  done < <(find -P "$2" -xdev \( \( -type f ! -perm -u+w \) -o \( -type d \( ! -perm -u+w -o ! -perm -u+x \) \) \) -printf '%P\0' 2>/dev/null)
}

baixa_runtime_codex() {
  echo ""
  echo ">> validando compra e baixando motor Codex (release assinada)..."
  local RELEASE_MANIFEST RELEASE_SIGNATURE RELEASE_PUBLIC_KEY RELEASE_METADATA
  RELEASE_MANIFEST=$(mktemp)
  RELEASE_SIGNATURE=$(mktemp)
  RELEASE_PUBLIC_KEY=$(mktemp)
  RELEASE_METADATA=$(mktemp)
  baixa_manifesto_assinado release-manifest.json release-manifest.sig "$RELEASE_MANIFEST" "$RELEASE_SIGNATURE" 524288 \
    || { echo "ERRO: nem o espelho no GitHub nem a central entregaram o manifesto assinado da release. Confira a internet desta maquina e tente de novo em alguns minutos." >&2; exit 1; }
  echo ">> manifesto assinado baixado (origem: $MANIFESTO_ORIGEM)${MANIFESTO_NOTA:+ ($MANIFESTO_NOTA)}"
  [ "$MANIFESTO_ORIGEM" != central ] || [ -n "$MANIFESTO_NOTA" ] || echo "   (o GitHub nao respondeu; peguei o manifesto da central e confiro a assinatura igual)"
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
if data["codexCliVersion"]!="0.154.0" or data["nodeVersion"]!="22.22.0": raise SystemExit(1)
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
  _LEON_MANIFESTO_VERSAO="$version"
  _LEON_MANIFESTO_SHA="$(sha256sum "$RELEASE_MANIFEST" | awk '{print $1}')"
  rm -f -- "$RELEASE_MANIFEST" "$RELEASE_SIGNATURE" "$RELEASE_PUBLIC_KEY" "$RELEASE_METADATA"

  # Gate de compra: o pacote-base e pago. 23/09 (cliente sem VPS): com licenca assinada
  # (LEON_LICENCA_ASSINADA=1 e LEON_LICENCA com o documento que a central emitiu na compra),
  # a casa confere a licenca OFFLINE (chave pinada), consulta a lista de revogacao assinada
  # (GitHub primeiro) e abre o pacote CIFRADO do espelho com a chave que so a licenca carrega.
  # Sem licenca assinada, ou se esse caminho falhar: /download-codex?email= na central, como hoje.
  echo ">> validando compra..."
  grava_licenca_assinada
  local TARBALL EMAIL_ENC HTTP_CODE BASE_ORIGEM="" _LIC_INFO _LIC_RC _LIC_REV _LIC_ID _LIC_ATE _LIC_VENC _LIC_CP
  TARBALL=$(mktemp --suffix=.tar.gz)
  if [ "${LEON_LICENCA_ASSINADA:-0}" = 1 ] && [ -f "$LEON_STATE_DIR/licenca-assinada.json" ]; then
    _LIC_REV=$(mktemp)
    baixa_revogacao "$CENTRAL" "$_LIC_REV"
    _LIC_RC=0; _LIC_INFO="$(licenca_confere "$LEON_STATE_DIR/licenca-assinada.json" "$_LIC_REV" "$LEON_STATE_DIR")" || _LIC_RC=$?
    rm -f -- "$_LIC_REV"
    if [ "$_LIC_RC" = 3 ]; then
      echo "ERRO: esta licenca foi cancelada (lista de revogacao assinada da central). suporte: https://wa.me/5511988890934" >&2
      rm -f -- "$TARBALL"; exit 1
    fi
    if [ "$_LIC_RC" = 0 ]; then
      IFS=$'\t' read -r _LIC_ID _LIC_ATE _LIC_VENC _LIC_CP <<< "$_LIC_INFO"
      if [ "$_LIC_VENC" = 1 ]; then
        echo ">> licenca assinada $_LIC_ID vencida em $_LIC_ATE; confiro a compra pela central"
      elif pacote_cifrado_do_espelho leon-base-curated.tar.gz "$base_sha256" "$base_bytes" "$TARBALL" "$_LIC_CP"; then
        BASE_ORIGEM=espelho-cifrado
        echo ">> licenca assinada conferida offline ($_LIC_ID, valida ate $_LIC_ATE); pacote-base do espelho no GitHub"
      else
        echo ">> licenca assinada ok, mas o pacote cifrado do espelho nao veio; confiro a compra pela central"
      fi
    else
      echo ">> licenca assinada invalida ou sem chave pinada; confiro a compra pela central"
    fi
  fi
  if [ -z "$BASE_ORIGEM" ]; then
  EMAIL_ENC=$(printf %s "$EMAIL" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))" 2>/dev/null || printf %s "$EMAIL")
  # sem codigo (000) o curl sai != 0; o "|| true" deixa a mensagem clara sair em vez do set -e.
  HTTP_CODE=$(curl -sS --max-filesize "$base_bytes" --retry 3 --retry-delay 2 --retry-connrefused --connect-timeout 10 \
    -w "%{http_code}" -o "$TARBALL" "$CENTRAL$base_url?email=$EMAIL_ENC") || true
  BASE_ORIGEM=central
  if [ "$HTTP_CODE" != "200" ]; then
    echo "ERRO: nao consegui validar a compra (HTTP $HTTP_CODE)." >&2
    echo "possiveis causas:" >&2
    echo "  · email diferente do que voce usou na compra (Cakto/Hubla)" >&2
    echo "  · compra ainda nao processada (aguarde 1min e tente de novo)" >&2
    echo "  · reembolso/cancelamento (licenca bloqueada)" >&2
    # Cloudflare na frente da VPS: com ela fora vem 520 a 530, nao 000 (23/09 noite).
    case "${HTTP_CODE:-000}" in
      000|408|429|5[0-9][0-9]) echo "  · a central nao respondeu (fora do ar): com licenca assinada (LEON_LICENCA_ASSINADA=1 LEON_LICENCA=...) a instalacao sai so do GitHub" >&2 ;;
    esac
    echo "suporte: https://wa.me/5511988890934" >&2
    rm -f -- "$TARBALL"
    exit 1
  fi
  fi
  verify_signed_artifact "$TARBALL" "$base_sha256" "$base_bytes" "pacote-base" \
    || { rm -f -- "$TARBALL"; exit 1; }
  echo "   pacote-base: origem=$BASE_ORIGEM"
  # copia guardada pro /atualiza nao precisar da central enquanto o pacote nao mudar
  LEON_CACHE_PACOTES="${LEON_CACHE_PACOTES:-$LEON_DATA_DIR/cache/pacotes}" guarda_pacote_no_cache "$TARBALL" "$base_sha256"
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
  libera_escrita_do_pacote "$INNER" "$INSTALL_DIR"
  cp -a "$INNER"/. "$INSTALL_DIR"/
  # 17/09: "cp -a INNER/." carrega o MODO do diretorio de origem pro destino, e INNER
  # sai do tar --no-same-permissions sob o umask de login (022) de um tarball cuja raiz
  # e 755. Medido na bancada: a casa do cliente passava de 700 pra 755 na reinstalacao,
  # ou seja, legivel por qualquer outro usuario da VPS. So o diretorio de cima, nunca -R:
  # os scripts continuam +x logo abaixo e os .leon/* ja recebem 700 no passo do .env.
  chmod 700 "$INSTALL_DIR"
  normalizar_agent_base "$INSTALL_DIR/AGENT-BASE.md"
  # NUCLEO UNICO (23/08): a alma do agente e a MESMA nos dois motores; o que muda e o
  # bloco _MOTOR-<motor>. As pecas vem PRONTAS no pacote (o cliente nao gera doutrina) e
  # moram na persona, ao lado do que o bridge ja le. Placeholders resolvidos igual ao
  # AGENT-BASE, senao o agente le "@@LEON_TMPDIR@@" no lugar do caminho de verdade.
  mkdir -p "$PERSONA_DIR_LOCAL"
  for _peca in NUCLEO-LEON.md _MOTOR-CLAUDE.md _MOTOR-CODEX.md _REGRAS-DURAS.md; do
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
  if ! baixa_artefato_verificado "$bundle_url" "$BUNDLE_TMP" "$bundle_sha256" "$bundle_bytes"; then
    echo "ERRO: nao consegui baixar o runtime Codex completo (nem do GitHub nem da central, ou nao bateu com o manifesto)." >&2
    rm -f -- "$BUNDLE_TMP"
    exit 1
  fi
  echo "   runtime: origem=$ARTEFATO_ORIGEM"
  verify_signed_artifact "$BUNDLE_TMP" "$bundle_sha256" "$bundle_bytes" "runtime Codex" \
    || { rm -f -- "$BUNDLE_TMP"; exit 1; }
  if ! python3 - "$BUNDLE_TMP" <<'PY'
import posixpath, sys, tarfile

# 21/09/2026 (2a rodada): a 1a correcao de hoje trocou a igualdade exata da lista de
# ARQUIVOS por "exige o nucleo", mas deixou de pe a lista nominal de PASTAS
# (directories) e a regra "arquivo solto na raiz so se for do nucleo". Medido na
# bancada: um build futuro que criasse uma pasta nova (ex.: lib-skills/) ou um
# arquivo novo na raiz derrubaria TODA instalacao nova de novo, exatamente o bug do
# Bruno/Well em outra dimensao. Agora o criterio e por PERIGO, nao por lista:
# recusa o que escapa da casa, o que e oculto, o que nao e arquivo comum, o que e
# grande demais, o que e fundo demais e o que colide com DADO DO CLIENTE
# (contrato de preservacao). Pasta nova e arquivo novo do nosso proprio build passam.
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
    "lib/integracoes.cjs",
    "lib/subagentes.cjs",
    "lib-motores/codex-appserver.cjs",
    "lib-motores/claude.cjs",
    "lib-motores/index.cjs",
    "lib-motores/limite.cjs",
    "smoke/appserver-smoke.cjs",
    "workers/piper.js",
}
# Nomes que NUNCA podem vir dentro de um pacote de codigo: sao dado/config do
# cliente e seriam sobrescritos pelo cp -a. Contrato de preservacao virando trava.
protegidos = {
    ".env",
    "brain",
    "memoria",
    "promises",
    "missoes",
    "logs",
    "sessoes",
    "node_modules",
    "personas",
}
extensoes_de_dado = (".db", ".sqlite", ".sqlite3", ".db-wal", ".db-shm", ".key", ".pem")
PROFUNDIDADE_MAXIMA = 4  # 2.7.0: leon2/nucleo/papeis/<arquivo> (LEON 2.0)
TAMANHO_MAXIMO = 8_000_000  # 22/09 (2.6.7): bridge passou de 2 MB


def recusa(motivo):
    sys.stderr.write("   motivo: %s\n" % motivo)
    raise SystemExit(1)


def confere_componentes(name, original):
    partes = name.split("/")
    if len(partes) > PROFUNDIDADE_MAXIMA:
        recusa("caminho fundo demais no pacote: %r" % original)
    for parte in partes:
        if parte in ("", ".", ".."):
            recusa("caminho invalido no pacote: %r" % original)
        if parte.startswith("."):
            recusa("entrada oculta no pacote: %r" % original)
        if parte.lower() in protegidos:
            recusa("o pacote traz %r, que e dado do cliente e nao pode ser sobrescrito" % original)
        if parte.lower().endswith(extensoes_de_dado):
            recusa("o pacote traz %r, que e dado/credencial e nao pode vir em pacote de codigo" % original)


try:
    members = tarfile.open(sys.argv[1], "r:gz").getmembers()
except (OSError, tarfile.TarError) as erro:
    recusa("o pacote nao abriu como tar.gz (%s)" % erro)
seen = set()
for member in members:
    original = member.name
    if "\\" in original:
        recusa("caminho com barra invertida no pacote: %r" % original)
    name = posixpath.normpath(original)
    if name == ".":
        if original not in (".", "./") or not member.isdir():
            recusa("raiz do pacote em formato inesperado: %r" % original)
        continue
    if original.startswith("/") or name in ("", "..") or name.startswith("../"):
        recusa("caminho inseguro no pacote: %r" % original)
    confere_componentes(name, original)
    if member.isdir():
        continue
    if member.issym() or member.islnk():
        recusa("link dentro do pacote: %r" % original)
    if not member.isfile():
        recusa("entrada que nao e arquivo comum: %r" % original)
    if member.size > TAMANHO_MAXIMO:
        recusa("arquivo acima de %d bytes: %r (%d bytes)" % (TAMANHO_MAXIMO, name, member.size))
    seen.add(name)
faltando = sorted(required - seen)
if faltando:
    recusa("faltam pecas do nucleo no pacote: %s" % ", ".join(faltando))
raise SystemExit(0)
PY
  then
    echo "ERRO: bundle Codex incompleto ou com caminho inseguro." >&2
    rm -f -- "$BUNDLE_TMP"
    exit 1
  fi
  BUNDLE_EXTRACT=$(mktemp -d)
  tar --no-same-owner --no-same-permissions -xzf "$BUNDLE_TMP" -C "$BUNDLE_EXTRACT"
  libera_escrita_do_pacote "$BUNDLE_EXTRACT" "$INSTALL_DIR"
  cp -a "$BUNDLE_EXTRACT"/. "$INSTALL_DIR"/
  # 17/09 (medido na bancada): este e o TERCEIRO cp -a para a casa e era o unico sem chmod.
  # O tarball do bundle traz um membro "./", entao o tar sobe o diretorio de extracao para 755
  # e o cp -a carrega esse 755 para a casa, que nasceu 700. Numa VPS com mais de um usuario a
  # casa do cliente ficava legivel por qualquer um depois de reinstalar.
  chmod 700 "$INSTALL_DIR"
  chmod 0700 "$INSTALL_DIR/bridge.cjs" "$INSTALL_DIR/smoke/appserver-smoke.cjs" "$INSTALL_DIR/workers/piper.js" 2>/dev/null || true
  chmod 0600 "$INSTALL_DIR/capabilities.json" 2>/dev/null || true
  chmod 0600 "$INSTALL_DIR/appserver"/*.cjs "$INSTALL_DIR/appserver/package.json" "$INSTALL_DIR/lib"/*.js "$INSTALL_DIR/lib-motores"/*.cjs 2>/dev/null || true
  rm -rf -- "$BUNDLE_EXTRACT"
  rm -f -- "$BUNDLE_TMP"
  write_runtime_files_manifest "$INSTALL_DIR"
  echo "   runtime app-server validado e aplicado."

  # Atualizador assinado que preserva o motor Codex: baixado do GitHub, central de reserva (updater_url
  # / updater_sha256 / updater_bytes ja vieram do release-manifest sourced acima),
  # conferido por verify_signed_artifact, bash -n, e um triplo gate de conteudo
  # (sem o flag perigoso, com o alvo appserver-v2 e com verify_release_manifest).
  # O chmod +x fica no bloco compartilhado adiante (nao duplicar aqui).
  echo ">> instalando atualizador que preserva o motor Codex..."
  local DANGEROUS_FLAG UPDATE_TMP
  DANGEROUS_FLAG="--dangerously-bypass-approvals-and-"'sandbox'
  UPDATE_TMP=$(mktemp)
  if ! baixa_artefato_verificado "$updater_url" "$UPDATE_TMP" "$updater_sha256" "$updater_bytes"; then
    rm -f -- "$UPDATE_TMP"
    echo "ERRO: nao consegui baixar o atualizador da versao Codex." >&2
    echo "sem ele uma atualizacao futura poderia reverter o motor. tente de novo em 1min." >&2
    exit 1
  fi
  echo "   atualizador: origem=$ARTEFATO_ORIGEM"
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
  # FASE B: os DOIS motores recebem a MESMA base e o MESMO bundle assinados. Antes o
  # ramo do segundo motor caia no /download antigo, sem manifesto assinado nem
  # conferencia de artefato, entao a mesma casa tinha duas historias de integridade.
  # A unica diferenca real entre os ramos e o CLI do fabricante, que ja foi instalado
  # la em cima. O manifest-claude e o /download deixam de ser usados por este ramo.
  if [ "$LEON_ENGINE" = codex ] || [ "$LEON_ENGINE" = claude ]; then
    baixa_runtime_codex
    # 23/09 (prova de preservacao, fim do falso verde): o runtime instalado e o da release que
    # o manifesto assinado acabou de trazer. Sem gravar a identidade, reinstalar por cima deixava
    # o marcador da versao ANTIGA: a casa rodava a nova e dizia a velha (e a prova "passava").
    if [ -n "${_LEON_MANIFESTO_VERSAO:-}" ] && [ -n "${_LEON_MANIFESTO_SHA:-}" ]; then
      printf '{"manifestSha256":"%s","version":"%s"}\n' "$_LEON_MANIFESTO_SHA" "$_LEON_MANIFESTO_VERSAO" > "$INSTALL_DIR/.leon-release.json"
      printf '%s\n' "$_LEON_MANIFESTO_VERSAO" > "$INSTALL_DIR/.leon-release-version"
      chmod 0600 "$INSTALL_DIR/.leon-release.json" "$INSTALL_DIR/.leon-release-version"
    fi
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
      echo "suporte: https://wa.me/5511988890934" >&2
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
    if ! baixa_manifesto_assinado release-manifest-claude.json release-manifest-claude.sig "$MOTOR_MANIFEST" "$MOTOR_SIG" 65536; then
      echo "ERRO: nem o espelho no GitHub nem a central entregaram o manifesto assinado do motor." >&2
      rm -f -- "$MOTOR_MANIFEST" "$MOTOR_SIG" "$MOTOR_PUBKEY" "$TARBALL"; exit 1
    fi
    echo ">> manifesto do motor baixado (origem: $MANIFESTO_ORIGEM)${MANIFESTO_NOTA:+ ($MANIFESTO_NOTA)}"
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
    libera_escrita_do_pacote "$INNER" "$INSTALL_DIR"
    cp -a "$INNER"/. "$INSTALL_DIR"/
    # 17/09: mesmo motivo do outro cp -a, o modo 755 do diretorio raiz do tarball
    # vazava pra casa do cliente. So o diretorio de cima, nunca -R.
    chmod 700 "$INSTALL_DIR"
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
        # 24/09 (rodada 2): o tar escreve POR CIMA. Skill do produto que o dono editou (ou o
        # LEON ate a 2.4.48) sumia sem copia nenhuma. Antes: foto do catalogo inteiro. Depois:
        # skills-do-dono leva o que for do dono pra skills-pessoais; a foto so sai quando nada
        # nela foi sobrescrito com conteudo diferente. Senao fica ao lado e o dono e avisado.
        SKILLS_FOTO=""
        if [ -n "$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
          SKILLS_FOTO="$SKILLS_DIR.leon-antes-$(date -u +%Y%m%dT%H%M%SZ)"
          mkdir -m 700 -p -- "$SKILLS_FOTO" && cp -a -- "$SKILLS_DIR/." "$SKILLS_FOTO/" \
            || { echo "   (aviso) nao consegui guardar uma copia de $SKILLS_DIR; mantive as habilidades como estao."; SKILLS_FOTO=ERRO; }
        fi
        if [ "$SKILLS_FOTO" != ERRO ] \
           && ( cd "$FU_SRC" && tar -c --exclude=.git --exclude=README.md --exclude=.claude-plugin --exclude="LICENSE*" . ) | ( cd "$SKILLS_DIR" && tar -x ); then
          git -C "$FU_TMP/r" rev-parse HEAD 2>/dev/null > "$SKILLS_DIR/.fonte-unica-sha" || true; FONTE_UNICA_OK=1; echo "   habilidades instaladas da fonte unica (molinateston/soft)."
        fi
        if [ -n "$SKILLS_FOTO" ] && [ "$SKILLS_FOTO" != ERRO ]; then
          SKILLS_REGISTRO="$(dirname "$SKILLS_DIR")/.skills-catalogo-instalado"
          SKILLS_FOTO_RC=0
          leon_preserva skills-do-dono "$SKILLS_FOTO" "$SKILLS_DIR" "$LEON_SKILLS_PESSOAIS_DIR" "$SKILLS_REGISTRO" >/dev/null 2>&1 || SKILLS_FOTO_RC=$?
          # Sobrescrito = arquivo da foto que no catalogo agora tem outro conteudo (ou sumiu).
          SKILLS_SOBRESCRITAS="$(cd "$SKILLS_FOTO" && find . ! -type d -print 2>/dev/null | while IFS= read -r f; do
              [ "$f" = ./.fonte-unica-sha ] && continue
              if [ -L "$f" ]; then [ -L "$SKILLS_DIR/$f" ] && [ "$(readlink -- "$f")" = "$(readlink -- "$SKILLS_DIR/$f")" ] && continue
              else [ -f "$SKILLS_DIR/$f" ] && [ ! -L "$SKILLS_DIR/$f" ] && cmp -s -- "$f" "$SKILLS_DIR/$f" && continue; fi
              f="${f#./}"; printf '%s\n' "${f%%/*}"
            done | sort -u | tr '\n' ' ')"
          if [ "$SKILLS_FOTO_RC" = 0 ] || { [ "$SKILLS_FOTO_RC" = 10 ] && [ -z "$SKILLS_SOBRESCRITAS" ]; }; then
            rm -rf -- "$SKILLS_FOTO"
          else
            echo "   (aviso) habilidades tuas com conteudo diferente do produto: ${SKILLS_SOBRESCRITAS:-ver a copia}"
            echo "   a versao que estava aqui ficou INTEIRA em $SKILLS_FOTO (nada foi apagado)."
          fi
        fi
        # O registro diz "isto e SO o que o produto instalou" (o /atualiza apaga backup igual a
        # ele sem procurar skill do dono). So registra catalogo que era vazio ou igual ao registro.
        if [ "$FONTE_UNICA_OK" -eq 1 ] && { [ -z "$SKILLS_FOTO" ] || [ "${SKILLS_FOTO_RC:-1}" = 0 ]; }; then
          leon_preserva skills-registra "$SKILLS_DIR" "$(dirname "$SKILLS_DIR")/.skills-catalogo-instalado" >/dev/null 2>&1 || true
        fi
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
      # MENSAGEM MENTIROSA (medido 17/09): quando o clone falhava, o instalador dizia
      # "sem rede?" e mandava o dono olhar a internet. O erro real capturado em
      # /tmp/skills-clone.err era "destination path already exists and is not an empty
      # directory". Agora a condicao de pasta cheia e testada ANTES, e o que sobra do
      # git e classificado pela primeira linha do erro, sem chutar a causa.
      SKILLS_N_ITENS=0
      [ -d "$SKILLS_DIR" ] && SKILLS_N_ITENS="$(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
      if [ -d "$SKILLS_DIR" ] && [ "$SKILLS_N_ITENS" -gt 0 ]; then
        echo "   (aviso) ja existe uma pasta de habilidades aqui sem controle de versao ($SKILLS_N_ITENS itens);"
        echo "   mantive como esta e nao baixei por cima."
      else
        # Erro do git fora do /tmp compartilhado (nome fixo la era arquivo de todo
        # mundo). Sai num temp da propria casa, apagado assim que a linha e lida.
        mkdir -p "$LEON_TMPDIR" 2>/dev/null || true
        SKILLS_ERR="$(mktemp "$LEON_TMPDIR/skills-clone.XXXXXX" 2>/dev/null || mktemp)"
        if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$SKILLS_SSH" git clone -q git@github.com:molinateston/soft.git "$SKILLS_DIR" 2>"$SKILLS_ERR"; then
          echo "   habilidades instaladas ($(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d ! -name '.git' | wc -l) no total)."
        else
          SKILLS_LINHA="$(sed -n '1p' "$SKILLS_ERR" 2>/dev/null | tr -d '\r' | cut -c1-160)"
          case "$SKILLS_LINHA" in
            *"Could not resolve host"*|*"Connection timed out"*|*"Network is unreachable"*|*"connect to host"*)
              echo "   (aviso) sem rede ate o GitHub, nao baixei as habilidades. O proximo /atualiza tenta de novo." ;;
            *"Permission denied (publickey)"*|*"Host key verification failed"*)
              echo "   (aviso) o GitHub nao aceitou a chave SSH desta casa, nao baixei as habilidades."
              echo "   O proximo /atualiza tenta de novo." ;;
            *"already exists and is not an empty directory"*)
              echo "   (aviso) a pasta ja existe e nao esta vazia; nao baixei as habilidades por cima." ;;
            "")
              echo "   (aviso) o git nao baixou as habilidades e nao disse por que." ;;
            *)
              echo "   (aviso) o git nao baixou as habilidades: $SKILLS_LINHA" ;;
          esac
        fi
        rm -f -- "$SKILLS_ERR"
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
  # 23/09: lidos como o bridge le (aspas e comentario no fim sao do dono e valem).
  _dono_antigo="$(leon_preserva env-valor "$INSTALL_DIR/.env" OWNER_CHAT_ID 2>/dev/null || true)"
  _bot_antigo="$(leon_preserva env-valor "$INSTALL_DIR/.env" TELEGRAM_BOT_TOKEN 2>/dev/null || leon_preserva env-valor "$INSTALL_DIR/.env" BOT_TOKEN 2>/dev/null || true)"
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
# 2.5 .env do cliente (escrita que PRESERVA o que e do cliente)
# ------------------------------------------------------------
# CAUSA MEDIDA 17/09: este passo era "cat > .env", e o sinal de maior TRUNCA o
# arquivo. Nada no instalador inteiro relia o .env anterior, entao toda
# reinstalacao apagava CALADA as chaves que o instalador nao conhece: na bancada,
# das 10 chaves de integracao semeadas, 10 sumiram (o .env caiu de 47 para 35
# linhas) e nenhuma mensagem avisou o dono.
# A regra agora: o instalador reescreve SO as chaves que ele mesmo escreve (as 40
# dos quatro blocos abaixo) e devolve TODA outra linha do .env antigo verbatim e
# na ordem antiga. Nao e lista branca: o conjunto preservado e o COMPLEMENTO do
# que o instalador escreve, derivado dos proprios blocos. A unica pergunta "o
# bridge aceita esta chave?" e feita ao lib/integracoes.cjs do runtime que acabou
# de ser desempacotado, nunca a uma lista dentro do instalador; o que o bridge
# recusa nao e apagado, vira linha de quarentena "#LEON-GUARDADO" na MESMA
# posicao do arquivo (o bridge pula comentario, entao a casa sobe).

_env_bloco_a() {
cat <<EOF
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
OWNER_CHAT_ID=$OWNER_CHAT_ID
LEON_LICENSE_EMAIL=$EMAIL
LEON_LICENSE_CENTRAL=$CENTRAL
LEON_MACHINE_ID=$MACHINE_ID
AGENT_NAME=$NOME
AGENT_GENDER=$GENDER
ENGINE=$LEON_ENGINE
ENGINE_DEFAULT=$LEON_ENGINE
TTS_PROVIDER=disabled
VOICE_REPLY=mirror
VOICE_PY=$LEON_DATA_DIR/whisper-venv/bin/python3
DRAIN_SEG=300
EOF
}

# RAMO C: as chaves de CAMINHO valem pros DOIS motores. O agente e o mesmo em
# qualquer motor, e ele le brain, persona, skills, area de trabalho e saida de
# missao pelos mesmos caminhos. Enquanto este bloco era so do Codex, uma casa no
# outro motor subia sem BRAIN_DIR e sem PERSONA_DIR, ou seja, sem a memoria e sem a
# persona do dono, e ninguem avisava.
_env_bloco_b() {
cat <<EOF
LEON_DATA_DIR=$LEON_DATA_DIR
BRAIN_DIR=$BRAIN_DIR
PERSONA_DIR=$PERSONA_DIR
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
MEMVIVA_FILE=$MEMVIVA_FILE
ASSUNTOS_FILE=$ASSUNTOS_FILE
EOF
}

# Chaves do segundo motor: a casa dele (onde moram transcript de sessao e o arquivo do
# dossie) e o modelo padrao. O CLI do fabricante ja foi instalado la em cima; aqui so
# apontamos onde ele guarda estado, fora do HOME do usuario que roda o servico.
# CLAUDE_CONFIG_DIR / CODEX_HOME (24/09, rodada 3): so entram quando faltam, e numa casa que ja
# existe entra a pasta que o bridge JA usa (homeDoMotor: ~/.claude ou ~/.codex com credencial).
# A pasta do LEON so vale na instalacao do zero: gravar ela por cima trocava a casa do login e
# dos MCPs do dono.
_env_bloco_c() {
cat <<EOF
CLAUDE_CONFIG_DIR=$(leon_preserva home-do-motor "$INSTALL_DIR/.env" claude "$LEON_DATA_DIR/claude")
CODEX_MODEL=$LEON_CLAUDE_MODEL
CODEX_REASONING_EFFORT=high
EOF
}

# Daqui pra baixo e so do motor Codex: o binario PINADO (unico caminho que o bridge
# aceita), a versao cravada do CLI, o modelo que respondeu na prova (A8) e o
# config.toml do proprio Codex. O outro motor nao tem nada disso.
_env_bloco_d() {
cat <<EOF
LEON_CODEX_ONLY=1
CODEX_APP_SERVER=1
CODEX_HOME=$(leon_preserva home-do-motor "$INSTALL_DIR/.env" codex "$LEON_CODEX_HOME")
CODEX_BIN=$CODEX_BIN_ENV
CODEX_MODEL=$CODEX_MODEL
CODEX_REASONING_EFFORT=high
LEON_CODEX_CLI_VERSION=$LEON_CODEX_CLI_VERSION
EOF
}

# escreve_env_do_dono PADROES [TROCAS]
# O .ENV E DO DONO (23/09, desenho estrutural, igual ao /atualiza): reinstalar por cima NUNCA
# reescreve nem comenta linha que ja existe. Toda linha do .env anterior sai byte a byte; so
# entram no FIM as chaves que faltam, com o valor de PADROES (a resposta desta instalacao ou o
# padrao do produto). TROCAS e so da lista PRODUTO_ENV do preserva-casa.py e so com o valor
# atual provado invalido aqui (id de outra maquina, token que o Telegram recusa, chave de
# licenca que a central nao devolveu). Fim do #LEON-GUARDADO e do filtro por allowlist.
# .env que o bridge recusaria (linha fora do formato, chave repetida): o instalador para sem
# escrever nada e diz a linha; consertar seria reescrever o arquivo do dono.
_ENV_RELATORIO=""
escreve_env_do_dono() {
  local PADROES="$1" TROCAS="${2:-}"
  local ENVF="$INSTALL_DIR/.env"
  local OBRA BKP CARIMBO INFO TIPO NLINK TAM DONO MEU RC
  _ENV_BACKUP=""

  OBRA="$(mktemp -d "$INSTALL_DIR/.env-obra.XXXXXX")" \
    || { echo "ERRO: nao consegui criar area temporaria dentro de $INSTALL_DIR." >&2; exit 1; }
  printf '%s' "$PADROES" > "$OBRA/padroes"
  printf '%s' "$TROCAS" > "$OBRA/trocas"

  if [ -e "$ENVF" ] || [ -L "$ENVF" ]; then
    # MESMAS checagens de ARQUIVO que o bridge faz antes de ler o .env. Symlink, nlink>1,
    # dono diferente ou arquivo acima de 256 KiB nao e estado de casa viva: alguem precisa
    # olhar. Aborta sem escrever nem renomear nada (o trap de EXIT religa o LEON antigo).
    INFO="$(stat -c '%F|%h|%s|%u' -- "$ENVF" 2>/dev/null || echo '')"
    TIPO="${INFO%%|*}"; INFO="${INFO#*|}"
    NLINK="${INFO%%|*}"; INFO="${INFO#*|}"
    TAM="${INFO%%|*}"; DONO="${INFO##*|}"
    MEU="$(id -u)"
    if [ "$TIPO" != "regular file" ] && [ "$TIPO" != "regular empty file" ]; then
      echo "ERRO: $ENVF nao e arquivo comum (e '$TIPO'). O bridge tambem recusa isso." >&2
      echo "Nada foi escrito e nada foi renomeado. Olhe esse caminho e rode o instalador de novo." >&2
      rm -rf -- "$OBRA"; exit 1
    fi
    if [ "${NLINK:-1}" != "1" ]; then
      echo "ERRO: $ENVF tem mais de um nome no disco (hard link, nlink=$NLINK)." >&2
      echo "Nada foi escrito e nada foi renomeado. Olhe esse caminho e rode o instalador de novo." >&2
      rm -rf -- "$OBRA"; exit 1
    fi
    if [ "${TAM:-0}" -gt 262144 ]; then
      echo "ERRO: $ENVF tem $TAM bytes e o limite que o bridge le e 256 KiB." >&2
      echo "Nada foi escrito e nada foi renomeado. Olhe esse caminho e rode o instalador de novo." >&2
      rm -rf -- "$OBRA"; exit 1
    fi
    if [ "${DONO:-$MEU}" != "$MEU" ]; then
      echo "ERRO: $ENVF pertence ao uid $DONO e esta fase roda como uid $MEU." >&2
      echo "Nada foi escrito e nada foi renomeado. Olhe esse caminho e rode o instalador de novo." >&2
      rm -rf -- "$OBRA"; exit 1
    fi
  fi

  RC=0
  leon_preserva env-acrescenta "$ENVF" "$OBRA/padroes" "$OBRA/trocas" "$OBRA/saida" "$OBRA/relatorio" "$LEON_DATA_DIR" || RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "ERRO: o .env desta casa tem linha que o LEON recusaria: $(sed -n 's/^recusa //p' "$OBRA/relatorio" 2>/dev/null | tr '\n' ' ')" >&2
    echo "Nada foi escrito: o .env e teu e eu nao reescrevo linha tua. Corrija essa linha e rode o instalador de novo." >&2
    rm -rf -- "$OBRA"; exit 1
  fi
  if [ -e "$ENVF" ] && cmp -s -- "$ENVF" "$OBRA/saida"; then
    _ENV_RELATORIO="$(cat -- "$OBRA/relatorio")"
    rm -rf -- "$OBRA"
    return 0
  fi
  if [ -e "$ENVF" ]; then
    # Copia de seguranca do .env que estava no disco (inerte: o bridge so le ".env").
    CARIMBO="$(date -u +%Y%m%dT%H%M%SZ)"
    BKP="$(mktemp "$INSTALL_DIR/.env.bkp.XXXXXX")" \
      || { echo "ERRO: nao consegui criar a copia de seguranca do .env." >&2; rm -rf -- "$OBRA"; exit 1; }
    cat -- "$ENVF" > "$BKP" || { rm -f -- "$BKP"; rm -rf -- "$OBRA"; exit 1; }
    chmod 600 "$BKP"
    mv -f -- "$BKP" "$INSTALL_DIR/.env.anterior-$CARIMBO"
    _ENV_BACKUP="$INSTALL_DIR/.env.anterior-$CARIMBO"
    { ls -1t "$INSTALL_DIR"/.env.anterior-* 2>/dev/null | tail -n +4 | while IFS= read -r _velho; do
      rm -f -- "$_velho"
    done ; } || true
  fi
  chmod 600 "$OBRA/saida"
  mv -f -- "$OBRA/saida" "$ENVF"
  chmod 600 "$ENVF"
  _ENV_RELATORIO="$(cat -- "$OBRA/relatorio")"
  rm -rf -- "$OBRA"
}

# resumo_env_preservado: so NOMES de chave, NUNCA valor.
resumo_env_preservado() {
  local NOVAS RELIG TROC DONO
  NOVAS="$(printf '%s\n' "$_ENV_RELATORIO" | sed -n 's/^nova //p' | tr '\n' ' ')"
  RELIG="$(printf '%s\n' "$_ENV_RELATORIO" | sed -n 's/^religada //p' | tr '\n' ' ')"
  TROC="$(printf '%s\n' "$_ENV_RELATORIO" | sed -n 's/^trocada //p' | tr '\n' ' ')"
  DONO="$(printf '%s\n' "$_ENV_RELATORIO" | sed -n 's/^escolha-do-dono //p' | tr '\n' ' ')"
  echo ">> .env: nenhuma linha que ja existia foi mudada."
  [ -z "$NOVAS" ] || echo "   acrescentadas no fim (faltavam): $NOVAS"
  [ -z "$RELIG" ] || echo "   voltaram a valer (uma versao antiga tinha comentado): $RELIG"
  [ -z "$TROC" ] || echo "   chaves do produto com valor invalido, corrigidas: $TROC"
  [ -z "$DONO" ] || echo "   mantive a tua escolha (a instalacao sugeria outro valor): $DONO"
  printf '%s\n' "$_ENV_RELATORIO" | grep -q '^binario-do-dono ' \
    && echo "   CODEX_BIN aponta pra binario teu, fora da pasta do produto: mantive."
  return 0
}

# CONFIG.TOML (23/09, desenho estrutural, igual ao /atualiza). CODEX_HOME do dono (fora de
# <LEON_DATA_DIR>/codex no .env): o instalador nao escreve config.toml nenhum ali. CODEX_HOME do
# LEON: o texto do dono e a base, o molde so acrescenta o que falta (leon_preserva toml-funde).
# Do dono tambem quando <LEON_DATA_DIR>/codex e link (ou passa por link) pro ~/.codex pessoal,
# ou quando o config.toml dela e link: o merge escreveria ATRAVES do link no config do dono.
codex_home_do_dono_instalador() {
  leon_preserva codex-home-do-dono "$INSTALL_DIR/.env" "$LEON_DATA_DIR" >/dev/null 2>&1
}

# Rodizio das copias .anterior-*: as 3 mais novas ficam; das outras so sai a que tem o MESMO
# conteudo do config vivo ou de uma copia que fica. Copia que e a unica com aquele conteudo
# nunca e apagada (reinstalar 4 vezes nao pode levar o unico config antigo do dono).
rodizio_config_anterior() {  # rodizio_config_anterior <destino>
  local DEST="$1" _arq _h _n=0 _vistos=" "
  [ ! -f "$DEST" ] || _vistos=" $(sha256sum < "$DEST" | cut -d' ' -f1) "
  while IFS= read -r _arq; do
    [ -n "$_arq" ] && [ -f "$_arq" ] || continue
    _h="$(sha256sum < "$_arq" | cut -d' ' -f1)"
    _n=$((_n + 1))
    if [ "$_n" -gt 3 ]; then
      case "$_vistos" in *" $_h "*) rm -f -- "$_arq"; continue ;; esac
    fi
    _vistos="$_vistos$_h "
  done < <(ls -1t -- "$DEST".anterior-* 2>/dev/null)
}

grava_config_do_dono() {  # grava_config_do_dono <molde> <destino>
  local MOLDE="$1" DEST="$2" REL RC ANT TS
  REL="$(mktemp "${TMPDIR:-/tmp}/leon-cfg-rel.XXXXXX")"
  ANT=""
  TS="$(date -u +%Y%m%dT%H%M%SZ)"
  if [ -f "$DEST" ] && [ ! -L "$DEST" ]; then
    ANT="$DEST.anterior-$TS"
    cp -p -- "$DEST" "$ANT" && chmod 600 "$ANT" || ANT=""
  fi
  RC=0
  LEON_PRESERVA_CODEX="${CODEX_BIN_ENV:-}" \
  LEON_PRESERVA_PATH="$(dirname "${LEON_NODE_BIN_RESOLVED:-$LEON_DATA_DIR/node/releases/$LEON_NODE_VERSION/bin/node}"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    leon_preserva toml-funde "$DEST" "$MOLDE" "$DEST.leon-novo" "$REL" "$INSTALL_DIR" || RC=$?
  case "$RC" in
    0)
      mv -f -- "$DEST.leon-novo" "$DEST"; chmod 600 "$DEST"
      if grep -q '^acrescentada ' "$REL"; then
        echo "   config.toml: nada teu mudou; acrescentei do molde: $(sed -n 's/^acrescentada //p' "$REL" | tr '\n' ' ')"
      else
        echo "   config.toml: nada teu mudou."
      fi
      if grep -q '^\(seguranca\|removida\) ' "$REL"; then
        echo "   config.toml: ajuste de seguranca do produto: $(sed -n 's/^\(seguranca\|removida\) //p' "$REL" | tr '\n' ' ')"
      fi
      ;;
    2)
      # Fora do rodizio: a copia do config que o Codex tambem recusou nunca e apagada.
      ANT="$DEST.ilegivel-$TS"
      cp -p -- "$DEST" "$ANT" 2>/dev/null && chmod 600 "$ANT" 2>/dev/null || true
      install -m 600 -- "$MOLDE" "$DEST"
      echo "   config.toml anterior ilegivel ($(head -1 "$REL")): gravei o molde; o teu esta em $ANT."
      ;;
    *)
      rm -f -- "$DEST.leon-novo"
      echo "   config.toml: mantido INTACTO ($(head -1 "$REL")); o LEON segue pelos parametros do app-server."
      ;;
  esac
  rm -f -- "$REL"
  rodizio_config_anterior "$DEST"
  return 0
}

_ENV_BLOCO_NOVO="$(_env_bloco_a)
"
if [ "$LEON_ENGINE" = codex ] || [ "$LEON_ENGINE" = claude ]; then
  _ENV_BLOCO_NOVO="$_ENV_BLOCO_NOVO$(_env_bloco_b)
"
  mkdir -p "$LEON_TMPDIR" "$BRAIN_DIR" \
    "$PERSONA_DIR" "$LEON_WORK_AREA" "$LEON_STATE_DIR" "$LEON_MISSIONS_DIR" \
    "$LEON_PROMISES_DIR" "$LEON_MISSION_OUTPUT_DIR"
  chmod 700 "$LEON_DATA_DIR" "$LEON_TMPDIR" "$LEON_STATE_DIR" "$LEON_MISSION_OUTPUT_DIR"
fi

if [ "$LEON_ENGINE" = claude ]; then
  # CASA QUE JA EXISTE MANTEM O MODELO (lei: instalacao nao sobrescreve o que e do cliente).
  # CODEX_MODEL e chave gerenciada, entao sem isto reinstalar por cima trocaria em silencio o
  # modelo que a casa ja usa pelo padrao novo. So quando ninguem passou LEON_CLAUDE_MODEL
  # explicito e so se o valor antigo e um nome de modelo do Claude bem formado.
  if [ -z "${_LEON_CLAUDE_MODEL_DADO:-}" ] && [ -f "$INSTALL_DIR/.env" ]; then
    _modelo_antigo="$(leon_preserva env-valor "$INSTALL_DIR/.env" CODEX_MODEL 2>/dev/null || true)"
    if printf '%s' "$_modelo_antigo" | grep -qE '^claude-[A-Za-z0-9._-]+$'; then
      LEON_CLAUDE_MODEL="$_modelo_antigo"
      echo ">> casa ja existente: mantenho o modelo dela ($LEON_CLAUDE_MODEL)"
    fi
    unset _modelo_antigo
  fi
  _ENV_BLOCO_NOVO="$_ENV_BLOCO_NOVO$(_env_bloco_c)
"
  mkdir -p "$LEON_DATA_DIR/claude"
  chmod 700 "$LEON_DATA_DIR/claude"
fi

if [ "$LEON_ENGINE" = codex ]; then
  CODEX_BIN_ENV="${LEON_CODEX_BIN_RESOLVED:-$LEON_DATA_DIR/codex-cli/releases/$LEON_CODEX_CLI_VERSION/bin/codex}"
  _ENV_BLOCO_NOVO="$_ENV_BLOCO_NOVO$(_env_bloco_d)
"
  if [ "$LEON_CODEX_HOME" = "$LEON_DATA_DIR/codex" ]; then
    mkdir -p "$LEON_CODEX_HOME"
    chmod 700 "$LEON_CODEX_HOME"
  fi
fi

# TROCAS (so a lista PRODUTO_ENV, so com valor atual invalido provado aqui).
_ENV_TROCAS=""
_env_atual() { leon_preserva env-valor "$INSTALL_DIR/.env" "$1" 2>/dev/null || true; }
if [ -f "$INSTALL_DIR/.env" ]; then
  # id da maquina: derivado de MAC + hostname desta VPS; o da casa que nao bate e de outra maquina.
  _v="$(_env_atual LEON_MACHINE_ID)"
  if [ -n "$_v" ] && [ "$_v" != "$MACHINE_ID" ]; then
    _ENV_TROCAS="${_ENV_TROCAS}LEON_MACHINE_ID=$MACHINE_ID
"
  fi
  # token do bot: so quando o Telegram recusa o da casa e aceita o informado agora.
  _v="$(_env_atual TELEGRAM_BOT_TOKEN)"
  if [ "$MOCK_MODE" != "1" ] && [ -n "$_v" ] && [ "$_v" != "$BOT_TOKEN" ]; then
    _tg="$(mktemp)"
    if ! telegram_api_get_file "$_v" getMe "$_tg" 15 >/dev/null 2>&1 || ! grep -q '"ok":true' "$_tg"; then
      _ENV_TROCAS="${_ENV_TROCAS}TELEGRAM_BOT_TOKEN=$BOT_TOKEN
"
    else
      echo ">> o bot desta casa continua valido no Telegram: mantive o token dela (o informado agora nao foi aplicado)."
    fi
    rm -f -- "$_tg"
  fi
  # Codex CLI: so quando o binario que a casa aponta nao executa.
  if [ "$LEON_ENGINE" = codex ] && [ "$MOCK_MODE" != "1" ]; then
    _v="$(_env_atual CODEX_BIN)"
    if [ -n "$_v" ] && [ ! -x "$_v" ]; then
      _ENV_TROCAS="${_ENV_TROCAS}CODEX_BIN=$CODEX_BIN_ENV
LEON_CODEX_CLI_VERSION=$LEON_CODEX_CLI_VERSION
"
    fi
  fi
  unset _v
fi
escreve_env_do_dono "$_ENV_BLOCO_NOVO" "$_ENV_TROCAS"
resumo_env_preservado

if [ "$LEON_ENGINE" = codex ]; then
  # Decisão do dono 04/09: mesmo modo do mestre, acesso total. Provado no 99: com
  # default_permissions = "leon" + seções [permissions.leon.*] o Codex mantém o
  # isolamento ligado mesmo sob sandbox_mode = "danger-full-access" (cai em
  # "bwrap: setting up uid map: Permission denied"); o modo só vale quando o perfil
  # NÃO existe. Por isso o perfil e o [sandbox_workspace_write] saíram do config.
  # ESFORÇO POR TAREFA (2.4.31): o config nasce em "medium". O bridge roteia o esforço por
  # fala (low no trivial, high na missão e no pedido de raciocínio), então este valor é só o
  # piso de quem roda o Codex fora da ponte. "high" cravado aqui era raciocínio invisível
  # cobrado em todo turno, e é o que estourava a cota do dono no plano Plus.
  # 23/09 (desenho estrutural): o molde nasce num arquivo a parte e se junta ao config do
  # dono (grava_config_do_dono); CODEX_HOME do dono nao recebe config nenhum.
  _CFG_MOLDE="$(mktemp "${TMPDIR:-/tmp}/leon-cfg-molde.XXXXXX")"
  cat > "$_CFG_MOLDE" <<EOF
model = "$CODEX_MODEL"
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
  # meta-ads e do produto: o molde o traz no modo filtro quando a casa tem o .meta-token.json.
  # O token mora onde o bridge grava (24/09, rodada 3): tokenPath(WORKDIR), WORKDIR = WORK_DIR do
  # .env ou o runtime. Olhar so no runtime tirava o meta-ads da casa com WORK_DIR proprio.
  _meta_wd="$(leon_preserva env-valor "$INSTALL_DIR/.env" WORK_DIR 2>/dev/null)" || _meta_wd=""
  case "$_meta_wd" in /*) ;; '') _meta_wd="$INSTALL_DIR" ;; *) _meta_wd="$INSTALL_DIR/$_meta_wd" ;; esac
  if [ -f "$_meta_wd/.meta-token.json" ] || [ -f "$INSTALL_DIR/.meta-token.json" ]; then
    cat >> "$_CFG_MOLDE" <<METAEOF

[mcp_servers.meta-ads]
command = "node"
args = ["$INSTALL_DIR/lib/meta-mcp-codex-filter.cjs"]
startup_timeout_sec = 20
tool_timeout_sec = 30
METAEOF
  fi
  if codex_home_do_dono_instalador; then
    echo "   config.toml: o CODEX_HOME desta casa e do dono; nao escrevo config.toml nenhum."
  else
    grava_config_do_dono "$_CFG_MOLDE" "$LEON_CODEX_HOME/config.toml"
  fi
  rm -f -- "$_CFG_MOLDE"
fi

# ------------------------------------------------------------
# 2.6 Ativa licenca no central
# ------------------------------------------------------------
if [ "$MOCK_MODE" != "1" ]; then
  echo ""
  echo ">> ativando licenca..."
  RESP=$(curl -fsS --connect-timeout 10 --max-time 30 -X POST "$CENTRAL/activate" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"machine_id\":\"$MACHINE_ID\"}" || echo '{"ok":false,"code":"sem_conexao"}')
  echo "$RESP"
  if ! printf %s "$RESP" | grep -q '"ok":true'; then
    echo "ATENCAO: ativacao no central falhou. motor instalado mas nao ativou."
    echo "se for machine_mismatch: essa chave ja foi ativada em outra VPS."
    echo "suporte: https://wa.me/5511988890934"
  else
    # A chave da licenca vem NA RESPOSTA do /activate (campo "key"). Ate a 2.4.48 ela
    # era descartada e o .env saia sem LEON_LICENSE_KEY, entao o gate KEY_PRESENT do
    # bridge nunca ligava. Gravamos aqui, depois do ok. O cliente nao digita nada a
    # mais: a chave e a que a central ja tem no cadastro do email dele.
    LICENSE_KEY=$(printf %s "$RESP" | python3 -c '
import json, re, sys
try:
    key = str(json.load(sys.stdin).get("key") or "").strip()
except Exception:
    key = ""
print(key if re.fullmatch(r"[A-Za-z0-9_-]{8,128}", key) else "")
')
    if [ -n "$LICENSE_KEY" ]; then
      # 17/09: este passo tinha o mesmo furo do 2.5 em miniatura. O ".env.key-new"
      # nascia sob o umask de login (022), ou seja, 644 com a chave dentro por um
      # instante, e o grep -v jogava fora a linha antiga sem motivo. Agora passa
      # pela mesma funcao, com GERENCIADAS={LEON_LICENSE_KEY}: substitui se existe,
      # acrescenta no fim se nao existe, e todo o resto do arquivo volta verbatim.
      _ENV_BLOCO_LIC="LEON_LICENSE_KEY=$LICENSE_KEY
"
      # a central e a fonte da chave: a da casa que falta, esta malformada ou difere e invalida.
      escreve_env_do_dono "" "$_ENV_BLOCO_LIC"
      echo ">> licenca ativa e chave gravada no .env."
    elif leon_preserva env-valor "$INSTALL_DIR/.env" LEON_LICENSE_KEY >/dev/null 2>&1; then
      # 17/09: com a escrita que preserva, a chave que ja estava no .env continua
      # la quando a central nao devolve nada. Mandar pedir ao suporte aqui seria
      # mensagem falsa, igual a das habilidades.
      echo "ATENCAO: a central ativou mas nao devolveu a chave da licenca."
      echo "Mantive a LEON_LICENSE_KEY que ja estava nesta casa, entao o controle de"
      echo "licenca do agente continua ligado. Nada a fazer."
    else
      echo "ATENCAO: a central ativou mas nao devolveu a chave da licenca."
      echo "O agente sobe e funciona, porem sem LEON_LICENSE_KEY no .env o controle de"
      echo "licenca do proprio agente fica desligado (so o email identifica esta casa)."
      echo "Peca a chave no suporte e acrescente a linha LEON_LICENSE_KEY=<chave> no .env."
    fi
  fi
fi
# 23/09 (G3): licenca assinada ligada na instalacao fica ligada na casa (o bridge e o /atualiza
# leem a flag do .env). A licenca em si ja esta em $LEON_STATE_DIR/licenca-assinada.json.
if [ "$MOCK_MODE" != "1" ] && [ "${LEON_LICENCA_ASSINADA:-0}" = 1 ] && [ -f "$LEON_STATE_DIR/licenca-assinada.json" ]; then
  escreve_env_do_dono "LEON_LICENCA_ASSINADA=1
"
  echo ">> licenca assinada ligada (a casa confere a licenca sozinha, sem depender da central)."
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

  # GATE DO RUNTIME (21/09/2026): a unit so vira servico depois que o alvo dela
  # EXISTE e compila NO LUGAR FINAL. Sem esta trava, uma fase user que nao
  # chegou ao fim (rede caiu no meio da extracao, disco cheio) deixava /etc
  # apontando pra um dir vazio e todo systemctl restart falhava com
  # status=200/CHDIR — com o processo antigo ainda respondendo no Telegram, o
  # cliente so descobria no proximo reboot.
  UNIT_RUNTIME_FINAL="$(sed -n 's/^WorkingDirectory=//p' /etc/systemd/system/$SERVICE_NAME | head -n1)"
  [ -z "$UNIT_RUNTIME_FINAL" ] && UNIT_RUNTIME_FINAL="$INSTALL_DIR"
  if [ ! -d "$UNIT_RUNTIME_FINAL" ] || [ ! -f "$UNIT_RUNTIME_FINAL/bridge.cjs" ]; then
    echo "ERRO: o runtime nao esta em '$UNIT_RUNTIME_FINAL'; o servico nao vai subir assim." >&2
    echo "Nada foi ligado. Rode a instalacao de novo. suporte: https://wa.me/5511988890934" >&2
    exit 1
  fi
  # O node do check e o MESMO que a unit vai usar (sai do ExecStart dela), nao
  # o do PATH: no Codex o servico roda no Node dedicado da home do leon, e
  # checar com outro binario provaria a coisa errada.
  UNIT_NODE_FINAL="$(sed -n 's/^ExecStart=\([^ ]*\) .*/\1/p' /etc/systemd/system/$SERVICE_NAME | head -n1)"
  [ -x "$UNIT_NODE_FINAL" ] || UNIT_NODE_FINAL="$(command -v node 2>/dev/null || true)"
  if [ -n "$UNIT_NODE_FINAL" ] && ! "$UNIT_NODE_FINAL" --check "$UNIT_RUNTIME_FINAL/bridge.cjs" >/dev/null 2>&1; then
    echo "ERRO: o bridge em '$UNIT_RUNTIME_FINAL' nao passou no node --check." >&2
    echo "Nada foi ligado. Rode a instalacao de novo. suporte: https://wa.me/5511988890934" >&2
    exit 1
  fi

  # Guarda a unit boa ANTES de mexer: se o servico nao subir, e ela que volta.
  UNIT_PRE_START="$(mktemp)"
  cp -p -- /etc/systemd/system/$SERVICE_NAME "$UNIT_PRE_START" 2>/dev/null || true

  sudo -n /bin/systemctl enable --now $SERVICE_NAME

  # ESPERA ATE 20s pelo is-active (o 'sleep 3' antigo julgava cedo demais: um
  # bridge que demora pra abrir o Telegram era dado como morto, e um bridge que
  # morre no segundo 5 era dado como vivo).
  LEON_SUBIU=0
  for _i in $(seq 1 20); do
    if sudo -n /bin/systemctl is-active $SERVICE_NAME >/dev/null 2>&1; then LEON_SUBIU=1; break; fi
    sleep 1
  done

  if [ "$LEON_SUBIU" != "1" ]; then
    # Nao deixa /etc com uma unit que so produz erro: devolve a que estava
    # antes, com o motivo em portugues simples.
    echo "" >&2
    echo "O LEON nao subiu em 20 segundos." >&2
    echo "Motivo provavel (ultimas linhas do log):" >&2
    sudo -n /usr/bin/journalctl -u $SERVICE_NAME -n 200 --no-pager 2>/dev/null | tail -n 12 >&2 || true
    if [ -s "$UNIT_PRE_START" ]; then
      cp -p -- "$UNIT_PRE_START" /etc/systemd/system/$SERVICE_NAME 2>/dev/null \
        || sudo -n /bin/systemctl stop $SERVICE_NAME >/dev/null 2>&1 || true
    fi
    rm -f -- "$UNIT_PRE_START"
    echo "" >&2
    echo "Teus arquivos estao em $INSTALL_DIR (nada foi apagado)." >&2
    echo "Rode: sudo journalctl -u $SERVICE_NAME -n 50   ·   suporte: https://wa.me/5511988890934" >&2
    exit 1
  fi
  rm -f -- "$UNIT_PRE_START"

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
