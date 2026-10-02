#!/usr/bin/env bash
# Projeto LEON · Socio IA 24x7 — instalador VERSAO CODEX (motor OpenAI Codex CLI)
#
# Irmao do install-leon.sh: mesmo fluxo, mesmo motor LEON, mesma licenca. A UNICA
# diferenca e o cerebro por baixo: esta edição roda somente o Codex CLI da OpenAI.
# O install-leon.sh original NAO e tocado por este arquivo.
#
# Uso oficial (tudo por env var, ZERO paste travando no Browser Terminal):
#
#   LEON_INSTALLER="$(mktemp)" &&
#   curl -fsSL https://licenca.leonardomolina.com.br/install-codex.sh -o "$LEON_INSTALLER" &&
#   bash -n "$LEON_INSTALLER" &&
#   IFS= read -rsp 'Token do BotFather: ' LEON_BOT_TOKEN; printf '\n'
#   printf '%s\n' "$LEON_BOT_TOKEN" | EMAIL='cliente@exemplo.com' \
#     NOME='LEON' GENDER='male' LEON_TOKEN_STDIN=1 bash "$LEON_INSTALLER"
#   unset LEON_BOT_TOKEN
#
# Sem chave de API da OpenAI em lugar nenhum: o instalador abre o login por
# codigo de dispositivo, espera a autorizacao com a assinatura do ChatGPT e
# continua na mesma execucao.
#
# Env vars OPCIONAIS pra teste E2E:
#   MOCK_MODE=1        → pula tudo que exige rede/interativo (codex, telegram, licenca)
#   LEON_USER=<nome>   → override do usuario nao-root (default: leon)
#   LEON_DIR=<path>    → override do diretorio de instalacao (default: ~/socio-ia)
#   LEON_CENTRAL=<url> → override do central (default: https://licenca.leonardomolina.com.br)
#
# Este script tem 2 fases:
#   ROOT: instala pre-reqs, cria user nao-root, pivota pra ele preservando env vars.
#   USER: baixa motor, valida licenca, captura chat_id via Telegram getUpdates, sobe systemd.
set -euo pipefail
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
    "TTS_PROVIDER": "so disabled -> edgetts, e so quando o disabled foi o padrao que o produto acrescentou de 26/09 a 01/10 (bloco # LEON <data>: chaves que faltavam, data >= 2026-09-26, com VOICE_REPLY=mirror e sem EDGE_TTS_VOICE)",
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

# REINSTALAR NAO TROCA O MOTOR (23/09, lei do dono). Esta pagina instala o motor Codex. Casa
# que ja existe e roda o motor Claude (ENGINE_DEFAULT no .env) nao e convertida em silencio:
# o instalador para ANTES de mexer em qualquer coisa. Trocar de motor e escolha do dono,
# feita com LEON_TROCA_MOTOR=1 (ou pelo /codex no Telegram).
recusa_troca_de_motor() {  # recusa_troca_de_motor <.env da casa>
  local envf="$1" motor
  [ -f "$envf" ] || return 0
  motor="$(leon_preserva env-valor "$envf" ENGINE_DEFAULT 2>/dev/null || true)"
  [ -n "$motor" ] || motor="$(leon_preserva env-valor "$envf" ENGINE 2>/dev/null || true)"
  [ "$motor" = claude ] || return 0
  [ "${LEON_TROCA_MOTOR:-0}" = 1 ] && return 0
  echo "ERRO: esta casa roda o motor Claude e esta pagina instala o motor Codex." >&2
  echo "Reinstalar nao troca o motor do dono. Nada foi mexido." >&2
  echo "Pra reinstalar mantendo o Claude: use a pagina de instalacao do Claude (install-leon.sh)." >&2
  echo "Pra TROCAR pro Codex de proposito: rode com LEON_TROCA_MOTOR=1." >&2
  exit 1
}

# SKILLS DO DONO no backup do catalogo (23/09): antes de apagar, o que nao e do produto vai
# pra skills-pessoais (inclusive arquivo do dono dentro de pasta com nome do produto); backup
# com coisa do dono nunca e apagado. O backup so sai quando e IGUAL ao catalogo que o produto
# instalou (registro .skills-catalogo-instalado ao lado do catalogo, regravado aqui).
apaga_backup_de_catalogo() {  # apaga_backup_de_catalogo <backup> <catalogo novo> <pessoais> [usuario]
  local backup="$1" novo="$2" pessoais="$3" dono="${4:-}" rc=0 reg
  reg="$(dirname "$novo")/.skills-catalogo-instalado"
  if [ -n "$backup" ] && [ -d "$backup" ]; then
    leon_preserva skills-do-dono "$backup" "$novo" "$pessoais" "$reg" || rc=$?
  fi
  if [ -d "$novo" ] && [ ! -L "$novo" ] && leon_preserva skills-registra "$novo" "$reg"; then
    if [ -n "$dono" ] && [ "$(id -u)" -eq 0 ]; then chown "$dono:$dono" "$reg" 2>/dev/null || true; fi
  fi
  [ -n "$backup" ] && [ -d "$backup" ] || return 0
  if [ -n "$dono" ] && [ "$(id -u)" -eq 0 ] && [ -d "$pessoais" ]; then chown -R "$dono:$dono" "$pessoais" 2>/dev/null || true; fi
  if [ "$rc" = 0 ]; then
    chmod -R u+w -- "$backup" 2>/dev/null || true
    rm -rf -- "$backup"
  else
    echo ">> catalogo anterior mantido em $backup: tinha coisa do dono (copiada pra $pessoais)."
  fi
}

INSTALLER_SOURCE_EPHEMERAL=0
if [ -n "${BASH_SOURCE[0]-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  INSTALLER_SOURCE="$(readlink -f "${BASH_SOURCE[0]}")"
else
  # Compatibilidade com o comando antigo `curl ... | env ... bash`. O Bash
  # executado por stdin não oferece BASH_SOURCE e o processo root precisa de
  # uma cópia completa para a fase não-root. Baixamos novamente por HTTPS,
  # validamos a sintaxe e seguimos; a página atual evita o pipe por padrão.
  PIPE_BOOTSTRAP_CENTRAL="${LEON_CENTRAL:-https://licenca.leonardomolina.com.br}"
  case "$PIPE_BOOTSTRAP_CENTRAL" in
    https://*) PIPE_BOOTSTRAP_PROTO=(--proto '=https' --tlsv1.2) ;;
    http://127.0.0.1:*|http://localhost:*)
      [ "${MOCK_MODE:-}" = 1 ] || { echo "ERRO: central sem HTTPS recusada." >&2; exit 1; }
      PIPE_BOOTSTRAP_PROTO=(--proto '=http') ;;
    *) echo "ERRO: endereço da central inválido." >&2; exit 1 ;;
  esac
  INSTALLER_SOURCE="$(mktemp)"
  INSTALLER_SOURCE_EPHEMERAL=1
  if ! curl "${PIPE_BOOTSTRAP_PROTO[@]}" -fsSL --max-filesize 524288 --retry 3 \
      "$PIPE_BOOTSTRAP_CENTRAL/install-codex.sh" -o "$INSTALLER_SOURCE" \
      || [ ! -s "$INSTALLER_SOURCE" ] || ! bash -n "$INSTALLER_SOURCE"; then
    rm -f -- "$INSTALLER_SOURCE"
    echo "ERRO: não consegui materializar o instalador recebido por pipe." >&2
    exit 1
  fi
  chmod 0700 "$INSTALLER_SOURCE"
  echo "AVISO: comando antigo por pipe detectado; use o bloco atual da página de instalação." >&2
fi

# ============================================================
# 0. VALIDA ENV VARS OBRIGATORIAS (falha ANTES de instalar nada)
# ============================================================
usage() {
  cat >&2 <<'USAGE'

ERRO: falta variavel de ambiente obrigatoria.

Uso oficial:

  LEON_INSTALLER="$(mktemp)" &&
  curl -fsSL https://licenca.leonardomolina.com.br/install-codex.sh -o "$LEON_INSTALLER" &&
  bash -n "$LEON_INSTALLER" &&
  IFS= read -rsp 'Token do BotFather: ' LEON_BOT_TOKEN; printf '\n'
  printf '%s\n' "$LEON_BOT_TOKEN" | EMAIL='cliente@exemplo.com' \
    NOME='LEON' GENDER='male' LEON_TOKEN_STDIN=1 bash "$LEON_INSTALLER"
  unset LEON_BOT_TOKEN

Gere o comando pronto em:
  https://licenca.leonardomolina.com.br/instalacao-codex

USAGE
  exit 1
}

: "${EMAIL:=}"
: "${NOME:=}"
: "${GENDER:=}"
: "${BOT_TOKEN:=}"
: "${LEON_TOKEN_STDIN:=}"
: "${MOCK_MODE:=}"
: "${OWNER_CHAT_ID:=}"
: "${LEON_FORCE_USER_PHASE:=}"
: "${LEON_ROOT_ORCHESTRATED:=}"
: "${LEON_TEST_FAIL_AT:=}"
: "${LEON_CODEX_BUNDLE_FILE:=}"
: "${LEON_BASE_PACKAGE_FILE:=}"
: "${LEON_BASE_PACKAGE_HASH_FILE:=}"
: "${LEON_CODEX_CLI_VERSION:=0.154.0}"
: "${LEON_CODEX_CLI_ROOT:=}"
: "${LEON_CODEX_BIN_RESOLVED:=}"
: "${LEON_NODE_VERSION:=22.22.0}"
: "${LEON_NODE_ROOT:=}"
: "${LEON_NODE_BIN_RESOLVED:=}"
: "${LEON_TEST_NODE_ONLY:=}"
: "${LEON_TEST_NODE_ARCH:=}"
: "${LEON_TEST_NODE_TGZ:=}"
: "${LEON_TEST_NODE_SHA256:=}"
: "${LEON_TEST_CODEX_CLI_ONLY:=}"
: "${LEON_TEST_PREFIX_REPAIR_ONLY:=}"
: "${LEON_TEST_PREFIX_TARGET_USER:=}"
: "${LEON_TEST_CODEX_LOGIN_ONLY:=}"
: "${LEON_TEST_CODEX_LOGIN_USER:=}"
: "${LEON_TEST_CODEX_LOGIN_HOME:=}"
: "${LEON_TEST_CODEX_LOGIN_BIN:=}"
: "${LEON_TEST_CODEX_MAIN_TGZ:=}"
: "${LEON_TEST_CODEX_PLATFORM_TGZ:=}"
: "${LEON_TEST_CODEX_MAIN_SHA512:=}"
: "${LEON_TEST_CODEX_PLATFORM_SHA512:=}"
: "${LEON_TEST_CODEX_ARCH:=}"
: "${LEON_TEST_ROOT_HOME:=}"
: "${LEON_TEST_ROOT_USER_PHASE:=}"
: "${LEON_TX_READY:=}"
: "${LEON_TX_GO:=}"
: "${LEON_TX_ABORT:=}"
if [ "$LEON_TOKEN_STDIN" = "1" ]; then
  # Handoff root -> user: o segredo viaja somente no stdin do processo filho.
  # Ele nunca integra argv do sudo/env/bash e é consumido antes de qualquer log.
  IFS= read -r BOT_TOKEN \
    || { echo "ERRO: não recebi o token no canal privado da instalação." >&2; exit 1; }
  [ -n "$BOT_TOKEN" ] \
    || { echo "ERRO: token vazio no canal privado da instalação." >&2; exit 1; }
fi
# Base curada da 2.4.33: regerada da doutrina F3+F4 (era 4483615a na 2.4.30). O instalador
# exige que o manifesto assinado referencie exatamente esta sha. FABLE: re-confira contra a
# base do build FINAL antes de servir (mesmo pin de build-release-production.sh e do teste).
LEON_BASE_CURATED_SHA256='e2ef14fd99c37bebf3d7b96604f0bffe462d0c1f9f2f68a66d377e08e9b1042c'
LEON_RELEASE_TRUST_FINGERPRINT='eb70521f5e4dd9bb1cd11e6ceb0b2bddd65596558322908a2d04fd3dec5cbe08'
LEON_RELEASE_STAGING_FINGERPRINT="$LEON_RELEASE_TRUST_FINGERPRINT"
DANGEROUS_FLAG="--dangerously-bypass-approvals-and-"'sandbox'

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
  python3 - "$1" "$2" <<'PY'
import re, sys
def parse(value):
    if not re.fullmatch(r"0|[1-9]\d*(?:\.(?:0|[1-9]\d*)){2}", value): raise SystemExit(2)
    return tuple(map(int,value.split(".")))
raise SystemExit(0 if parse(sys.argv[1]) >= parse(sys.argv[2]) else 1)
PY
}

read_installed_release_version() {
  local marker="$1"
  python3 - "$marker" <<'PY'
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
    fd=os.open(path, os.O_RDONLY | getattr(os,"O_NOFOLLOW",0))
    try:
        before=os.fstat(fd); raw=os.read(fd,65); after=os.fstat(fd)
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
  python3 - "$1" <<'PY'
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
  python3 - "$marker" <<'PY'
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
  python3 - "$1" "$2" "$3" "$4" <<'PY'
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
# proprio codigo"). Grava o sha256 de cada arquivo do motor na instalacao. O bridge
# confere no boot e avisa o dono se algo divergir. Cobre o codigo que EXECUTA e so ele:
# arquivo de estado que muda em uso legitimo (.env, sessions, topics, brain) fica de
# fora, senao o alarme dispara sozinho todo boot e o dono aprende a ignorar o alarme.
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
    lib/meta-mcp-codex-filter.cjs lib/meta-account-guard.cjs \
    workers/piper.js workers/edge-tts.js workers/hostinger-health.cjs; do
    [ -f "$stage/$rel" ] && [ ! -L "$stage/$rel" ] || continue
    printf '%s  %s\n' "$(sha256sum "$stage/$rel" | awk '{print $1}')" "$rel" >> "$destination"
  done
  chmod 0600 "$destination"
}

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

validate_download_file() {
  local artifact="$1" max_bytes="$2" exact_bytes="${3:-}"
  python3 - "$artifact" "$max_bytes" "$exact_bytes" <<'PY'
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

telegram_api_get_file() {
  local token="$1" endpoint="$2" output="$3" timeout="${4:-15}"
  printf %s "$token" | grep -qE '^[0-9]+:[A-Za-z0-9_-]{20,}$' || return 2
  case "$endpoint" in getMe|getUpdates\?timeout=5) ;; *) return 2 ;; esac
  printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$token" "$endpoint" \
    | curl -fsS --max-time "$timeout" --config - --output "$output" 2>/dev/null
}

verify_release_manifest() {
  local manifest="$1" signature="$2" public_key="$3" metadata="$4"
  write_release_public_key "$public_key" || return 1
  openssl pkeyutl -verify -rawin -pubin -inkey "$public_key" \
    -in "$manifest" -sigfile "$signature" >/dev/null 2>&1 || return 1
  python3 - "$manifest" "$LEON_RELEASE_TRUST_FINGERPRINT" > "$metadata" <<'PY'
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
}

if [ "${LEON_TEST_RELEASE_HELPERS_ONLY:-0}" = "1" ]; then
  # O helper pode encerrar antes de o produtor do pipe terminar. Drenar o
  # restante evita o falso `curl: (23)` na regressão de compatibilidade.
  [ "$INSTALLER_SOURCE_EPHEMERAL" -eq 0 ] || cat >/dev/null || true
  helper_status=0
  case "${1:-}" in
    identity-read) read_installed_release_identity "$2" || helper_status=$? ;;
    identity-accept) release_identity_acceptable "$2" "$3" "$4" "$5" || helper_status=$? ;;
    identity-write) write_release_identity "$2" "$3" "$4" || helper_status=$? ;;
    manifest-verify) verify_release_manifest "$2" "$3" "$4" "$5" || helper_status=$? ;;
    download-validate) validate_download_file "$2" "$3" "${4:-}" || helper_status=$? ;;
    *) helper_status=64 ;;
  esac
  [ "$INSTALLER_SOURCE_EPHEMERAL" -eq 0 ] || rm -f -- "$INSTALLER_SOURCE"
  exit "$helper_status"
fi

if ! printf %s "$LEON_CODEX_CLI_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([_-][A-Za-z0-9.-]+)?$'; then
  echo "ERRO: LEON_CODEX_CLI_VERSION invalida." >&2
  exit 1
fi

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
  node_root="${LEON_NODE_ROOT:-$target_home/.leon/node}"
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
  cli_root="${LEON_CODEX_CLI_ROOT:-$target_home/.leon/codex-cli}"
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

# Le auth.json direto do disco e valida estrutura, sem invocar o binario codex
# (o "login status" falha em ambiente restrito/clean-PATH mesmo com auth bom).
# Retorna 0 se existe um auth parseavel com refresh_token OU api key. Secret-safe:
# nunca ecoa conteudo; toda a saida vai pra /dev/null.
codex_auth_looks_valid() {
  local codex_home="$1" auth_file="$1/auth.json"
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

run_codex_login_as_user() {
  local target_user="$1" target_home="$2" codex_home="$3" node_bin="$4" codex_bin="$5"
  shift 5
  local target_uid target_gid clean_path term_value
  target_uid="$(id -u "$target_user")" || return 1
  target_gid="$(id -g "$target_user")" || return 1
  case "$target_home:$codex_home:$node_bin:$codex_bin" in
    /*:/*:/*:/*) ;;
    *) echo "ERRO: caminhos do login Codex precisam ser absolutos." >&2; return 1 ;;
  esac
  case "$codex_home/" in "$target_home"/*) ;; *) return 1 ;; esac
  [ -d "$target_home" ] && [ ! -L "$target_home" ] && [ -x "$node_bin" ] && [ -x "$codex_bin" ] \
    || return 1
  repair_managed_prefix_dirs "$target_home" "$codex_home" "$target_user" || return 1
  if [ "$(id -u)" -eq 0 ] && [ "$target_user" != root ]; then
    install -d -m 0700 -o "$target_uid" -g "$target_gid" "$codex_home"
  else
    mkdir -p -- "$codex_home"
    chmod 0700 "$codex_home"
  fi
  python3 - "$target_home" "$codex_home" "$target_uid" <<'PY' || return 1
import os,stat,sys
home,target,uid=os.path.abspath(sys.argv[1]),os.path.abspath(sys.argv[2]),int(sys.argv[3])
if os.path.commonpath([home,target])!=home or target==home: raise SystemExit(1)
cursor=home
for part in os.path.relpath(target,home).split(os.sep):
    cursor=os.path.join(cursor,part); info=os.lstat(cursor)
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode): raise SystemExit(1)
    if info.st_uid!=uid or stat.S_IMODE(info.st_mode)&0o077: raise SystemExit(1)
PY
  clean_path="$(dirname "$node_bin"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  term_value="${TERM:-dumb}"

  # O auth.json e o unico artefato secreto que a chamada externa do codex pode
  # sobrescrever/truncar. Antes de QUALQUER subcomando que mexe em sessao,
  # tiramos uma copia 0600 do dono; se a chamada falhar e o auth sumir/encolher,
  # restauramos. "login status" (read-only) nao precisa disso.
  local auth_file="$codex_home/auth.json" auth_bak="" auth_guard=0
  case " $* " in
    *" logout "*|*" --device-auth "*|*" login "*) auth_guard=1 ;;
  esac
  if [ "$auth_guard" -eq 1 ] && [ -f "$auth_file" ]; then
    auth_bak="$codex_home/.auth.json.leon-preserva-$$"
    if [ "$(id -u)" -eq 0 ] && [ "$target_user" != root ]; then
      install -m 0600 -o "$target_uid" -g "$target_gid" "$auth_file" "$auth_bak" || auth_bak=""
    else
      cp -p -- "$auth_file" "$auth_bak" && chmod 0600 "$auth_bak" || auth_bak=""
    fi
  fi

  local rc=0
  if [ "$(id -u)" -eq 0 ] && [ "$target_user" != root ]; then
    runuser -u "$target_user" -- env -i \
      HOME="$target_home" USER="$target_user" LOGNAME="$target_user" \
      PATH="$clean_path" CODEX_HOME="$codex_home" LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM="$term_value" \
      "$codex_bin" "$@"
    rc=$?
  elif [ "$(id -u)" -eq "$target_uid" ]; then
    env -i HOME="$target_home" USER="$target_user" LOGNAME="$target_user" \
      PATH="$clean_path" CODEX_HOME="$codex_home" LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM="$term_value" \
      "$codex_bin" "$@"
    rc=$?
  else
    echo "ERRO: somente root ou o usuario LEON pode iniciar o login Codex." >&2
    return 1
  fi

  # Restaura se o auth bom foi apagado ou truncado pela chamada que falhou.
  if [ -n "$auth_bak" ]; then
    if [ "$rc" -ne 0 ] && { [ ! -f "$auth_file" ] || [ ! -s "$auth_file" ]; }; then
      if [ "$(id -u)" -eq 0 ] && [ "$target_user" != root ]; then
        install -m 0600 -o "$target_uid" -g "$target_gid" "$auth_bak" "$auth_file" || true
      else
        cp -p -- "$auth_bak" "$auth_file" && chmod 0600 "$auth_file" || true
      fi
    fi
    rm -f -- "$auth_bak" 2>/dev/null || true
  fi
  return $rc
}

ensure_codex_login() {
  local target_user="$1" target_home="$2" codex_home="$3" node_bin="$4" codex_bin="$5"

  # 1) Caminho feliz: o proprio codex confirma a sessao.
  if run_codex_login_as_user "$target_user" "$target_home" "$codex_home" "$node_bin" "$codex_bin" \
       login status >/dev/null 2>&1; then
    echo ">> Codex ja esta autenticado nesta VPS."
    return 0
  fi

  # 2) "login status" falhou. Pode ser ambiente (clean PATH/env -i), nao auth ruim.
  #    Se existe um auth.json parseavel com credencial, PRESERVA e NUNCA dispara
  #    device-auth (que apagaria o auth existente sem poder completar sem tty).
  #    O /login pelo Telegram (2.4.4) faz o relogin depois se o refresh expirou.
  if codex_auth_looks_valid "$codex_home"; then
    echo ">> Codex ja tem credencial nesta VPS (login preservado; relogin pelo /login se precisar)."
    return 0
  fi

  # 3) Sem auth utilizavel: device-auth. Ele NAO precisa de tty — imprime a URL + o
  #    codigo de uso unico no stdout, o dono autoriza no navegador e o CLI faz polling
  #    ate completar. Isso e o que faz a instalacao em UM passo (curl|bash) funcionar:
  #    o dono ve o link, autoriza, e a instalacao segue sozinha. (03/09: a guarda de tty
  #    daqui abortava o curl|bash e quebrou o um-passo; provado no 99 que device-auth
  #    imprime a URL sem tty. O passo 2 acima ja protege um auth.json valido de ser
  #    apagado; aqui nao ha auth util, entao device-auth e seguro.)
  echo ""
  echo "========================================"
  echo "  LOGIN DO CODEX"
  echo "========================================"
  echo "O terminal vai mostrar uma URL e um codigo de uso unico."
  echo "Abra a URL no navegador, entre na sua conta do ChatGPT e informe o codigo."
  echo "Nao feche este terminal: a instalacao continua sozinha depois do login."
  echo ""
  if ! run_codex_login_as_user "$target_user" "$target_home" "$codex_home" "$node_bin" "$codex_bin" \
       login --device-auth; then
    echo "ERRO: o login Codex nao foi concluido. Nenhum runtime LEON foi trocado." >&2
    return 1
  fi
  if ! run_codex_login_as_user "$target_user" "$target_home" "$codex_home" "$node_bin" "$codex_bin" \
       login status >/dev/null 2>&1; then
    echo "ERRO: o Codex encerrou o login sem uma sessao valida. Nenhum runtime LEON foi trocado." >&2
    return 1
  fi
  echo ">> Login Codex confirmado. Continuando a mesma instalacao."
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

if [ "$LEON_TEST_NODE_ONLY" = "1" ]; then
  ensure_node_runtime
  exit $?
fi

if [ "$LEON_TEST_CODEX_CLI_ONLY" = "1" ]; then
  ensure_codex_cli
  exit $?
fi

if [ "$LEON_TEST_CODEX_LOGIN_ONLY" = "1" ]; then
  [ -n "$LEON_TEST_CODEX_LOGIN_USER" ] && [ -n "$LEON_TEST_CODEX_LOGIN_HOME" ] \
    && [ -n "$LEON_TEST_CODEX_LOGIN_BIN" ] && [ -n "$LEON_NODE_BIN_RESOLVED" ] || exit 64
  ensure_codex_login "$LEON_TEST_CODEX_LOGIN_USER" "$LEON_TEST_CODEX_LOGIN_HOME" \
    "$LEON_TEST_CODEX_LOGIN_HOME/.leon/codex" "$LEON_NODE_BIN_RESOLVED" "$LEON_TEST_CODEX_LOGIN_BIN"
  exit $?
fi

if [ "$LEON_TEST_PREFIX_REPAIR_ONLY" = "1" ]; then
  [ -n "$LEON_TEST_PREFIX_TARGET_USER" ] || exit 64
  repair_managed_prefix_dirs "$HOME" "$HOME/.leon/codex-cli" "$LEON_TEST_PREFIX_TARGET_USER"
  exit $?
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
LEON_USER_REQUESTED="${LEON_USER:-}"
LEON_DIR_REQUESTED="${LEON_DIR:-}"
LEON_USER="$LEON_USER_REQUESTED"

# Reinstalacao segura: se o servico ja existe e o operador nao escolheu outro
# usuario, preserva o User e o WorkingDirectory atuais. Sem isso, uma pagina
# generica com default "leon" abandona instalacoes antigas em outro usuario.
SERVICE_UNIT_DISCOVERY="${LEON_UNIT_PATH:-/etc/systemd/system/leon-agente.service}"
if [ "$(id -u)" = "0" ] && [ "$LEON_FORCE_USER_PHASE" != "1" ] && [ -f "$SERVICE_UNIT_DISCOVERY" ]; then
  EXISTING_USER="$(awk -F= '$1 == "User" { print substr($0, index($0, "=") + 1); exit }' "$SERVICE_UNIT_DISCOVERY")"
  EXISTING_DIR="$(awk -F= '$1 == "WorkingDirectory" { print substr($0, index($0, "=") + 1); exit }' "$SERVICE_UNIT_DISCOVERY")"
  if [ -z "$LEON_USER" ] && printf %s "$EXISTING_USER" | grep -qE '^[a-z_][a-z0-9_-]*[$]?$' && id "$EXISTING_USER" >/dev/null 2>&1; then
    LEON_USER="$EXISTING_USER"
    echo ">> reinstalacao detectada: preservando usuario '$LEON_USER'."
  fi
  if [ -z "$LEON_DIR_REQUESTED" ] && [ -n "$EXISTING_DIR" ] && [ "$LEON_USER" = "$EXISTING_USER" ]; then
    LEON_DIR="$EXISTING_DIR"
    echo ">> reinstalacao detectada: preservando diretorio '$LEON_DIR'."
  fi
  if [ -n "$LEON_USER_REQUESTED" ] && [ -n "$EXISTING_USER" ] && [ "$LEON_USER_REQUESTED" != "$EXISTING_USER" ] && [ "${LEON_REPLACE_EXISTING:-}" != "1" ]; then
    echo "ERRO: o servico existente roda como '$EXISTING_USER', mas LEON_USER pediu '$LEON_USER_REQUESTED'." >&2
    echo "Para uma migracao intencional, faca backup e repita com LEON_REPLACE_EXISTING=1." >&2
    exit 1
  fi
fi
LEON_USER="${LEON_USER:-leon}"

if ! printf %s "$LEON_USER" | grep -qE '^[a-z_][a-z0-9_-]*[$]?$'; then
  echo "ERRO: LEON_USER invalido: '$LEON_USER'." >&2
  exit 1
fi
if [ -n "${LEON_DIR:-}" ]; then
  if ! printf %s "$LEON_DIR" | grep -qE '^/[A-Za-z0-9._/-]+$' \
     || printf %s "$LEON_DIR" | grep -qE '(^|/)\.\.(/|$)|//'; then
    echo "ERRO: LEON_DIR precisa ser um caminho absoluto simples, sem '..', espacos nem controles." >&2
    exit 1
  fi
fi
if [ "${#NOME}" -gt 40 ] || printf %s "$NOME" | LC_ALL=C grep -q '[[:cntrl:]=]'; then
  echo "ERRO: NOME precisa ter de 1 a 40 caracteres e nao pode conter '=' nem controles." >&2
  exit 1
fi

echo ""
echo "========================================"
echo "  PROJETO LEON · Socio IA 24x7"
LEON_INSTALLER_STAMP="2026-09-21 10:52"
echo "  instalador oficial · VERSAO CODEX"
echo "  revisao do instalador: $LEON_INSTALLER_STAMP"
echo "========================================"
echo "  email:  $EMAIL"
echo "  nome:   $NOME"
echo "  identidade: $([ "$GENDER" = "male" ] && echo "masculina" || echo "feminina") (voz não provisionada neste core)"
echo "  motor:  Codex CLI (OpenAI)"
echo "========================================"
echo ""

# ============================================================
# 1. FASE ROOT: pre-reqs + cria user nao-root + pivota
# ============================================================
if [ "$(id -u)" = "0" ] && [ "$LEON_FORCE_USER_PHASE" != "1" ]; then
  # antes de qualquer pacote, usuario ou servico: casa Claude nao vira casa Codex sem pedir
  _casa_home="$(getent passwd "${LEON_USER:-leon}" 2>/dev/null | cut -d: -f6 || true)"
  [ -z "$_casa_home" ] || recusa_troca_de_motor "${LEON_DIR:-$_casa_home/socio-ia}/.env"
  echo ">> voce esta como root. vou criar '$LEON_USER' e reinstalar como ele."
  echo ""
  USER_CREATED=0
  ROOT_KEEP_BOOTSTRAP=0
  LINGER_WAS_ENABLED=0
  [ -e "/var/lib/systemd/linger/$LEON_USER" ] && LINGER_WAS_ENABLED=1
  cleanup_root_identity() {
    local status="${1:-$?}"
    if [ "$status" -ne 0 ] && [ "$ROOT_KEEP_BOOTSTRAP" -eq 0 ]; then
      if [ "$LINGER_WAS_ENABLED" -eq 0 ] && id "$LEON_USER" >/dev/null 2>&1; then
        loginctl disable-linger "$LEON_USER" >/dev/null 2>&1 || true
      fi
      if [ "$USER_CREATED" -eq 1 ] && id "$LEON_USER" >/dev/null 2>&1; then
        deluser --remove-home "$LEON_USER" >/dev/null 2>&1 || true
      fi
    fi
    return "$status"
  }
  trap 'cleanup_root_identity $?' EXIT

  # Uma reinstalacao valida os arquivos novos antes de reiniciar o serviço.
  # O processo atual continua atendendo durante download e configuracao.
  if systemctl is-active leon-agente.service >/dev/null 2>&1; then
    echo ">> LEON ja esta ativo; vou atualizar sem derruba-lo durante a preparacao."
  fi

  export DEBIAN_FRONTEND=noninteractive

  # MOCK: pula apt+node+codex quando o teste E2E ja subiu tudo no container base
  if [ "$MOCK_MODE" != "1" ]; then
    apt-get update -qq
    # cron: o agente instala sozinho as rotinas de backup, saude e a rede de
    # seguranca do update. Sem o cron rodando, essas redes nao existem.
    apt-get install -y -qq \
      git curl ca-certificates tar cron openssl bubblewrap \
      python3 python3-venv python3-pip \
      dbus-user-session locales sudo >/dev/null

    # bubblewrap e o mecanismo que a jaula do Codex (permissionProfile leon) usa
    # pra isolar cada sessao. O apt acima LISTA o pacote, mas em algumas VPS ele
    # falha silencioso; sem o bwrap o motor sai exit 1 e NADA roda. Verificamos.
    if ! command -v bwrap >/dev/null 2>&1; then
      echo ">> bubblewrap nao apareceu no PATH; tentando reinstalar uma vez..."
      apt-get install -y -qq --reinstall bubblewrap >/dev/null 2>&1 || true
    fi
    if ! command -v bwrap >/dev/null 2>&1; then
      echo "ERRO: bubblewrap (bwrap) nao instalou. A jaula do Codex depende dele." >&2
      echo "      Rode manualmente: apt-get install -y bubblewrap  e reinstale." >&2
      exit 1
    fi

    # Ubuntu 24.04 (noble) vem com o AppArmor barrando user-namespace nao-privilegiado
    # (kernel.apparmor_restrict_unprivileged_userns=1). O bwrap PRECISA desse namespace;
    # com o knob em 1 o sandbox da "setting up uid map: Permission denied" e o motor
    # nao sobe. Liberamos SO esse mecanismo (a jaula continua intacta), de forma
    # idempotente, e so onde o knob existe (kernel antigo/nao-Ubuntu nao tem, nao e erro).
    USERNS_KNOB="kernel.apparmor_restrict_unprivileged_userns"
    if [ "$(sysctl -n "$USERNS_KNOB" 2>/dev/null)" = "1" ]; then
      echo ">> liberando user-namespace pro sandbox do Codex (AppArmor estava barrando)..."
      # o > sobrescreve: rodar o install 2x nao duplica linha nem quebra
      printf '# LEON: o sandbox do Codex (bwrap) precisa de user-namespace nao-privilegiado.\n%s=0\n' \
        "$USERNS_KNOB" > /etc/sysctl.d/99-leon-userns.conf
      if sysctl --system >/dev/null 2>&1 || sysctl -w "$USERNS_KNOB=0" >/dev/null 2>&1; then
        echo ">> user-namespace liberado ($USERNS_KNOB=0), persistido em /etc/sysctl.d/99-leon-userns.conf."
      else
        echo ">> AVISO: nao consegui aplicar $USERNS_KNOB=0 agora (host restrito/container?)." >&2
        echo "         O arquivo ficou gravado pro proximo boot; o teste do sandbox mais a frente decide." >&2
      fi
    fi

    systemctl enable --now cron >/dev/null 2>&1 || true
    locale-gen C.UTF-8 2>/dev/null || true

    apt-get install -y -qq ffmpeg >/dev/null 2>&1 || true
  else
    echo ">> MOCK_MODE=1: pulando apt/node/codex (assumindo pre-instalados)."
  fi

  # Cria usuario '$LEON_USER' (sem sudo, blast radius pequeno)
  if ! id "$LEON_USER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$LEON_USER" >/dev/null
    USER_CREATED=1
  fi

  loginctl enable-linger "$LEON_USER" >/dev/null 2>&1 || true

  # Prepara a unit fora de /etc. Ela so entra no lugar depois de arquivos,
  # licenca, perfil e modelo passarem nos smokes da fase sem privilegio.
  LEON_HOME_TMP=$(getent passwd "$LEON_USER" | cut -d: -f6)
  if [ "$MOCK_MODE" = 1 ] && [ -n "$LEON_TEST_ROOT_HOME" ]; then LEON_HOME_TMP="$LEON_TEST_ROOT_HOME"; fi
  INSTALL_DIR_TMP="${LEON_DIR:-$LEON_HOME_TMP/socio-ia}"
  recusa_troca_de_motor "$INSTALL_DIR_TMP/.env"
  # LEITOR UNICO DAS PASTAS (24/09, rodada 5): a LEON_DATA_DIR e as pastas derivadas saem do .env
  # da casa (leon_bases_do_dono), antes de qualquer padrao. A fase root conferia o login e fazia a
  # transacao em ~/.leon cravado, e passava LEON_DATA_DIR=~/.leon pra fase do usuario: numa casa
  # com LEON_DATA_DIR proprio o login "sumia" (pedia device-auth) e o .env ganhava ~/.leon/brain.
  leon_bases_do_dono "$INSTALL_DIR_TMP/.env" "$LEON_HOME_TMP" \
    || { echo "ERRO: nao consegui ler as pastas do .env da casa." >&2; exit 1; }
  # a pasta do LEON (config.toml do produto, backup e volta da transacao) e a pasta de login que o
  # bridge usa HOJE (homeDoMotor): o ~/.codex do dono quando e ele, sem login a mais
  LEON_CODEX_HOME_TMP="$LEON_DATA_DIR/codex"
  LEON_CODEX_LOGIN_TMP="$(HOME="$LEON_HOME_TMP" leon_preserva home-do-motor "$INSTALL_DIR_TMP/.env" codex "$LEON_CODEX_HOME_TMP")"
  # runtime dedicado na MESMA LEON_DATA_DIR que a fase do usuario confere (EXPECTED_*_BIN) e que o
  # bridge procura (codexBin: <LEON_DATA_DIR>/codex-cli/releases/<versao>)
  [ -n "$LEON_NODE_ROOT" ] || LEON_NODE_ROOT="$LEON_DATA_DIR/node"
  [ -n "$LEON_CODEX_CLI_ROOT" ] || LEON_CODEX_CLI_ROOT="$LEON_DATA_DIR/codex-cli"
  NODE_RELEASE_DIR="$LEON_NODE_ROOT/releases/$LEON_NODE_VERSION"
  CODEX_RELEASE_DIR="$LEON_CODEX_CLI_ROOT/releases/$LEON_CODEX_CLI_VERSION"
  NODE_RELEASE_CREATED=0
  PRESERVE_NODE_RELEASE=0
  CODEX_RELEASE_CREATED=0
  PRESERVE_CODEX_RELEASE=0
  cleanup_prereq_releases() {
    local status=$?
    if [ "$CODEX_RELEASE_CREATED" -eq 1 ] && [ "$PRESERVE_CODEX_RELEASE" -eq 0 ]; then
      rm -rf -- "$CODEX_RELEASE_DIR"
    fi
    if [ "$NODE_RELEASE_CREATED" -eq 1 ] && [ "$PRESERVE_NODE_RELEASE" -eq 0 ]; then
      rm -rf -- "$NODE_RELEASE_DIR"
    fi
    cleanup_root_identity "$status" || true
    return "$status"
  }
  trap cleanup_prereq_releases EXIT
  case "$INSTALL_DIR_TMP/" in
    "$LEON_HOME_TMP"/*) ;;
    *)
      echo "ERRO: LEON_DIR precisa ficar dentro de $LEON_HOME_TMP." >&2
      echo "Uma migracao para fora da home exige acompanhamento do suporte." >&2
      exit 1 ;;
  esac
  if [ -L "$INSTALL_DIR_TMP" ] || { [ -e "$INSTALL_DIR_TMP" ] && [ ! -d "$INSTALL_DIR_TMP" ]; }; then
    echo "ERRO: o destino '$INSTALL_DIR_TMP' existe, mas nao e um diretorio real." >&2
    exit 1
  fi

  # Node e Codex ficam em prefixos privados, com versões e hashes homologados.
  # Nenhum pacote global da VPS é criado, atualizado ou rebaixado.
  if [ "$MOCK_MODE" != "1" ]; then
    NODE_RELEASE_WAS_PRESENT=0
    [ ! -e "$NODE_RELEASE_DIR" ] || NODE_RELEASE_WAS_PRESENT=1
    ensure_node_runtime "$LEON_USER" "$LEON_HOME_TMP" \
      || { echo "abortando. suporte: https://wa.me/5511988890934" >&2; exit 1; }
    [ "$NODE_RELEASE_WAS_PRESENT" -eq 1 ] || NODE_RELEASE_CREATED=1
    CODEX_RELEASE_WAS_PRESENT=0
    [ ! -e "$CODEX_RELEASE_DIR" ] || CODEX_RELEASE_WAS_PRESENT=1
    ensure_codex_cli "$LEON_USER" "$LEON_HOME_TMP" \
      || { echo "abortando. suporte: https://wa.me/5511988890934" >&2; exit 1; }
    [ "$CODEX_RELEASE_WAS_PRESENT" -eq 1 ] || CODEX_RELEASE_CREATED=1

    ensure_codex_login "$LEON_USER" "$LEON_HOME_TMP" "$LEON_CODEX_LOGIN_TMP" \
      "$LEON_NODE_BIN_RESOLVED" "$LEON_CODEX_BIN_RESOLVED" \
      || { echo "abortando. suporte: https://wa.me/5511988890934" >&2; exit 1; }
  fi

  INSTALL_PARENT_TMP=$(dirname "$INSTALL_DIR_TMP")
  INSTALL_BASE_TMP=$(basename "$INSTALL_DIR_TMP")
  install -d -m 0700 -o "$LEON_USER" -g "$LEON_USER" "$INSTALL_PARENT_TMP"

  TX_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  TX_STAGE="$INSTALL_PARENT_TMP/.${INSTALL_BASE_TMP}.leon-stage-$TX_ID"
  TX_BACKUP="$INSTALL_PARENT_TMP/.${INSTALL_BASE_TMP}.leon-backup-$TX_ID"
  TX_FAILED="$INSTALL_PARENT_TMP/.${INSTALL_BASE_TMP}.leon-failed-$TX_ID"
  TX_CONFIG_BACKUP="$LEON_CODEX_HOME_TMP/config.toml.leon-backup-$TX_ID"
  # o mesmo catalogo e as mesmas quarentenas que a fase do usuario usa (LEON_SKILLS_DIR do .env,
  # senao <LEON_DATA_DIR>/skills; <LEON_DATA_DIR>/.skills-backup-<tx>)
  TX_SKILLS_LIVE="$LEON_SKILLS_DIR"
  [ -n "$TX_SKILLS_LIVE" ] || TX_SKILLS_LIVE="$LEON_DATA_DIR/skills"
  TX_SKILLS_BACKUP="$LEON_DATA_DIR/.skills-backup-$TX_ID"
  TX_SKILLS_FAILED="$LEON_DATA_DIR/.skills-failed-$TX_ID"
  if [ -e "$TX_STAGE" ] || [ -e "$TX_BACKUP" ]; then
    echo "ERRO: colisao ao criar a transacao $TX_ID." >&2
    exit 1
  fi

  UNIT_PATH=/etc/systemd/system/leon-agente.service
  SUDOERS_PATH=/etc/sudoers.d/leon-agente
  if [ "$MOCK_MODE" = 1 ]; then
    [ -z "${LEON_UNIT_PATH:-}" ] || UNIT_PATH="$LEON_UNIT_PATH"
    [ -z "${LEON_SUDOERS_PATH:-}" ] || SUDOERS_PATH="$LEON_SUDOERS_PATH"
  fi
  TX_RUN_DIR=/run
  if [ "$MOCK_MODE" = 1 ]; then
    # Fixtures não devem depender de escrita no /run real. O override só
    # existe no modo de teste e fica preso ao diretório da unit simulada.
    TX_RUN_DIR="${LEON_TX_RUN_DIR:-$(dirname -- "$UNIT_PATH")}"
    if [ ! -d "$TX_RUN_DIR" ] || [ -L "$TX_RUN_DIR" ]; then
      echo "ERRO: diretório transacional de teste inválido." >&2
      exit 1
    fi
  fi
  # ----------------------------------------------------------------
  # GUARDA DA UNIT ORFA (21/09/2026). Medido na bancada
  # leon-inst-ubuntu2404-18set: a unit ficou em /etc apontando para
  # /home/leon/socio-ia/bridge.cjs, mas o diretorio nao existia. Resultado:
  # "Job for leon-agente.service failed because the control process exited
  # with error code" (status=200/CHDIR) em TODO systemctl restart, enquanto
  # o processo antigo ainda vivo seguia respondendo no Telegram.
  #
  # POR QUE ACONTECE: rollback_install cobre saida normal e INT/TERM, mas
  # morte nao-interceptavel (SIGKILL, OOM, queda de SSH, reboot do provedor)
  # pula o trap e deixa unit + sudoers no disco apontando pra um runtime que
  # o rollback da fase user ja tinha removido. Provado em
  # scratchpad/prova-sigkill.sh: exit=137 e a unit sobrevive.
  #
  # A REGRA: reinstalar por cima NUNCA deixa a casa pior. Antes de abrir a
  # transacao nova, uma unit que aponta para um bridge.cjs inexistente e
  # tratada como entulho de uma transacao morta: sai da frente (com copia
  # guardada), o servico para de falhar, e a instalacao segue do zero.
  if [ -f "$UNIT_PATH" ] && [ ! -L "$UNIT_PATH" ]; then
    UNIT_RUNTIME_ATUAL="$(sed -n 's/^WorkingDirectory=//p' "$UNIT_PATH" | head -n1)"
    if [ -n "$UNIT_RUNTIME_ATUAL" ] && [ ! -e "$UNIT_RUNTIME_ATUAL/bridge.cjs" ]; then
      UNIT_ORFA_BACKUP="${UNIT_PATH}.orfa-$(date -u +%Y%m%dT%H%M%SZ)"
      echo ">> a casa anterior ficou sem runtime em '$UNIT_RUNTIME_ATUAL'."
      echo "   (uma instalacao anterior foi interrompida antes de terminar)"
      echo "   guardando a unit quebrada em $UNIT_ORFA_BACKUP e recomecando limpo."
      systemctl stop leon-agente.service >/dev/null 2>&1 || true
      systemctl disable leon-agente.service >/dev/null 2>&1 || true
      cp -p -- "$UNIT_PATH" "$UNIT_ORFA_BACKUP" 2>/dev/null || true
      rm -f -- "$UNIT_PATH"
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl reset-failed leon-agente.service >/dev/null 2>&1 || true
    fi
    unset UNIT_RUNTIME_ATUAL
  fi

  UNIT_CANDIDATE=$(mktemp --suffix=.service "$TX_RUN_DIR/leon-agente.candidate.XXXXXX")
  UNIT_OLD=$(mktemp "$TX_RUN_DIR/leon-agente.service.old.XXXXXX")
  SUDOERS_CANDIDATE=$(mktemp "$TX_RUN_DIR/leon-agente.sudoers.candidate.XXXXXX")
  SUDOERS_OLD=$(mktemp "$TX_RUN_DIR/leon-agente.sudoers.old.XXXXXX")
  CRONTAB_CANDIDATE=$(mktemp "$TX_RUN_DIR/leon-agente.crontab.candidate.XXXXXX")
  CRONTAB_OLD=$(mktemp "$TX_RUN_DIR/leon-agente.crontab.old.XXXXXX")
  USER_PHASE_STATUS_FILE=$(mktemp "$TX_RUN_DIR/leon-agente.user-status.XXXXXX")
  : > "$USER_PHASE_STATUS_FILE"
  # o canal root/usuario mora na LEON_DATA_DIR da casa (a fase do usuario so aceita la dentro)
  install -d -m 0700 -o "$LEON_USER" -g "$LEON_USER" "$LEON_DATA_DIR"
  TX_READY="$LEON_DATA_DIR/.install-ready-$TX_ID"
  TX_GO="$LEON_DATA_DIR/.install-go-$TX_ID"
  TX_ABORT="$LEON_DATA_DIR/.install-abort-$TX_ID"
  rm -f -- "$TX_READY" "$TX_GO" "$TX_ABORT"
  INSTALLER_TMP=""
  HAD_UNIT=0
  HAD_SUDOERS=0
  HAD_CRONTAB=0
  HAD_LIVE=0
  HAD_SKILLS=0
  HAD_CODEX_CONFIG=0
  WAS_ACTIVE=0
  WAS_ENABLED=0
  ROOT_NEEDS_ROLLBACK=0
  SUDOERS_APPLIED=0
  CRONTAB_APPLIED=0
  UNIT_APPLIED=0
  SERVICE_STOPPED_FOR_COMMIT=0
  USER_PHASE_PID=""
  [ -f "$UNIT_PATH" ] && { cp -p "$UNIT_PATH" "$UNIT_OLD"; HAD_UNIT=1; }
  if [ -e "$SUDOERS_PATH" ]; then
    [ -f "$SUDOERS_PATH" ] && [ ! -L "$SUDOERS_PATH" ] \
      || { echo "ERRO: sudoers LEON existente não é arquivo regular." >&2; exit 1; }
    cp -p -- "$SUDOERS_PATH" "$SUDOERS_OLD"
    HAD_SUDOERS=1
  fi
  if crontab -u "$LEON_USER" -l > "$CRONTAB_OLD" 2>/dev/null; then HAD_CRONTAB=1; else : > "$CRONTAB_OLD"; fi
  [ ! -d "$INSTALL_DIR_TMP" ] || HAD_LIVE=1
  [ ! -d "$TX_SKILLS_LIVE" ] || HAD_SKILLS=1
  [ -f "$LEON_CODEX_HOME_TMP/config.toml" ] && HAD_CODEX_CONFIG=1
  if systemctl is-active leon-agente.service >/dev/null 2>&1; then WAS_ACTIVE=1; fi
  if systemctl is-enabled leon-agente.service >/dev/null 2>&1; then WAS_ENABLED=1; fi
  NODE_BIN="$NODE_RELEASE_DIR/bin/node"
  if [ "$MOCK_MODE" != "1" ]; then
    [ "$LEON_NODE_BIN_RESOLVED" = "$NODE_BIN" ] \
      && validate_dedicated_node "$NODE_BIN" "$(dirname "$LEON_NODE_ROOT")" "$LEON_NODE_VERSION" "$(id -u "$LEON_USER")" \
      || { echo "ERRO: runtime Node dedicado ausente ou inseguro." >&2; exit 1; }
  elif [ ! -x "$NODE_BIN" ]; then
    NODE_BIN="$(command -v node || true)"
  fi
  [ -x "$NODE_BIN" ] || { echo "ERRO: executavel do Node nao encontrado." >&2; exit 1; }

  cleanup_root_tmp() {
    local status=$?
    if [ -n "$USER_PHASE_PID" ] && kill -0 "$USER_PHASE_PID" 2>/dev/null; then
      : > "$TX_ABORT" 2>/dev/null || true
      chmod 0644 "$TX_ABORT" 2>/dev/null || true
      kill "$USER_PHASE_PID" 2>/dev/null || true
      wait "$USER_PHASE_PID" 2>/dev/null || true
    fi
    if [ "$ROOT_NEEDS_ROLLBACK" -eq 1 ] && declare -F rollback_install >/dev/null 2>&1; then
      rollback_install
    fi
    [ -z "$INSTALLER_TMP" ] || rm -f -- "$INSTALLER_TMP"
    if [ "$CODEX_RELEASE_CREATED" -eq 1 ] && [ "$PRESERVE_CODEX_RELEASE" -eq 0 ]; then
      rm -rf -- "$CODEX_RELEASE_DIR"
    fi
    if [ "$NODE_RELEASE_CREATED" -eq 1 ] && [ "$PRESERVE_NODE_RELEASE" -eq 0 ]; then
      rm -rf -- "$NODE_RELEASE_DIR"
    fi
    rm -f -- "$UNIT_CANDIDATE" "$UNIT_OLD" "$SUDOERS_CANDIDATE" "$SUDOERS_OLD" \
      "$CRONTAB_CANDIDATE" "$CRONTAB_OLD" "$USER_PHASE_STATUS_FILE" \
      "$TX_READY" "$TX_GO" "$TX_ABORT" "$SUDOERS_PATH.new" "$UNIT_PATH.new"
    cleanup_root_identity "$status" || true
    return "$status"
  }
  trap cleanup_root_tmp EXIT
  trap 'exit 130' INT TERM

  # CONTENCAO DE MEMORIA (25/09, prova no mestre): um script fujao de skill chegou a 17 GB.
  # MemoryHigh estrangula TODO processo da unit enquanto o uso fica entre High e Max, e
  # com swap sem teto o fujao nunca chega ao Max: o LEON congelou 2 h sem OOM. Sem High,
  # com swap limitado e OOMPolicy=continue, o kernel mata so o fujao e a unit segue viva.
  cat > "$UNIT_CANDIDATE" <<EOF
[Unit]
Description=Projeto LEON · Socio IA 24x7
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=120
StartLimitBurst=8

[Service]
Type=simple
User=$LEON_USER
Group=$LEON_USER
WorkingDirectory=$INSTALL_DIR_TMP
ExecStartPre=$NODE_BIN --check $INSTALL_DIR_TMP/bridge.cjs
ExecStart=$NODE_BIN $INSTALL_DIR_TMP/bridge.cjs
Environment="PATH=$(dirname "$NODE_BIN"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
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
MemoryHigh=infinity
MemoryMax=90%
MemorySwapMax=1G
OOMPolicy=continue

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$UNIT_CANDIDATE"

  # Candidato apenas: entra em /etc somente depois do stage user concluir.
  cat > "$SUDOERS_CANDIDATE" <<EOF
$LEON_USER ALL=(root) NOPASSWD: /bin/systemctl start leon-agente.service, /bin/systemctl stop leon-agente.service, /bin/systemctl restart leon-agente.service, /bin/systemctl enable leon-agente.service, /bin/systemctl disable leon-agente.service, /bin/systemctl is-active leon-agente.service, /bin/systemctl enable --now leon-agente.service, /usr/bin/journalctl -u leon-agente.service -n 200 --no-pager
EOF
  chmod 0440 "$SUDOERS_CANDIDATE"
  visudo -c -f "$SUDOERS_CANDIDATE" >/dev/null

  # Voz e transcrição são extensões opcionais. O instalador de release não
  # baixa pip/modelos mutáveis; elas só serão ativadas por artefato assinado.

  # Baixa uma copia validada deste instalador e executa a preparacao como o
  # usuario final. O processo root fica vivo para fazer commit ou rollback.
  LEON_HOME=$(getent passwd "$LEON_USER" | cut -d: -f6)
  if [ -z "$LEON_HOME" ] || [ ! -d "$LEON_HOME" ]; then
    echo "ERRO: home do usuario '$LEON_USER' nao encontrada ('$LEON_HOME')." >&2
    exit 1
  fi

  INSTALLER_TMP=$(mktemp "$LEON_HOME/.install-codex.XXXXXX")
  # Continua exatamente com o bootstrap já baixado pelo operador. Baixar uma
  # segunda cópia aqui abriria uma janela TOCTOU entre a revisão e a fase user.
  cp -- "$INSTALLER_SOURCE" "$INSTALLER_TMP"
  if [ "$INSTALLER_SOURCE_EPHEMERAL" -eq 1 ]; then
    rm -f -- "$INSTALLER_SOURCE"
    INSTALLER_SOURCE_EPHEMERAL=0
  fi
  chown "$LEON_USER:$LEON_USER" "$INSTALLER_TMP"
  chmod 0700 "$INSTALLER_TMP"
  if [ ! -s "$INSTALLER_TMP" ] || ! bash -n "$INSTALLER_TMP"; then
    echo "ERRO: a central entregou um instalador vazio ou com sintaxe invalida." >&2
    exit 1
  fi

  rollback_install() {
    ROOT_NEEDS_ROLLBACK=0
    set +e
    echo "ERRO: transação incompleta; restaurando todos os artefatos LEON." >&2
    if [ "$SERVICE_STOPPED_FOR_COMMIT" -eq 1 ] || [ "$UNIT_APPLIED" -eq 1 ] \
       || [ -d "$TX_BACKUP" ]; then
      systemctl stop leon-agente.service >/dev/null 2>&1 || true
    fi
    if [ "$UNIT_APPLIED" -eq 1 ]; then
      if [ "$HAD_UNIT" -eq 1 ]; then install -m 0644 "$UNIT_OLD" "$UNIT_PATH"; else rm -f -- "$UNIT_PATH"; fi
    fi
    if [ -d "$TX_BACKUP" ]; then
      if [ -e "$INSTALL_DIR_TMP" ]; then
        [ ! -e "$TX_FAILED" ] || TX_FAILED="${TX_FAILED}-$(date -u +%s)"
        mv -- "$INSTALL_DIR_TMP" "$TX_FAILED" || true
      fi
      mv -- "$TX_BACKUP" "$INSTALL_DIR_TMP" || true
      # 23/09: o .env do runtime velho volta byte a byte (veio dentro do backup); o que estava
      # ativo na hora da volta fica ao lado, com sufixo. Nada e fundido.
      if [ -f "$TX_FAILED/.env" ] && ! cmp -s -- "$TX_FAILED/.env" "$INSTALL_DIR_TMP/.env"; then
        install -m 0600 -o "$LEON_USER" -g "$LEON_USER" -- "$TX_FAILED/.env" "$INSTALL_DIR_TMP/.env.pos-atualiza-$TX_ID" 2>/dev/null || true
      fi
    elif [ "$HAD_LIVE" -eq 0 ] && [ ! -e "$TX_STAGE" ] && [ -d "$INSTALL_DIR_TMP" ]; then
      [ ! -e "$TX_FAILED" ] || TX_FAILED="${TX_FAILED}-$(date -u +%s)"
      mv -- "$INSTALL_DIR_TMP" "$TX_FAILED" || true
    fi
    if [ -f "$LEON_CODEX_HOME_TMP/config.toml" ] && [ ! -L "$LEON_CODEX_HOME_TMP/config.toml" ] \
       && ! { [ -f "$TX_CONFIG_BACKUP" ] && cmp -s -- "$TX_CONFIG_BACKUP" "$LEON_CODEX_HOME_TMP/config.toml"; }; then
      cp -p -- "$LEON_CODEX_HOME_TMP/config.toml" "$LEON_CODEX_HOME_TMP/config.toml.pos-atualiza-$TX_ID" 2>/dev/null || true
    fi
    if [ "$HAD_CODEX_CONFIG" -eq 1 ] && [ -f "$TX_CONFIG_BACKUP" ]; then
      mv -f -- "$TX_CONFIG_BACKUP" "$LEON_CODEX_HOME_TMP/config.toml" || true
    elif [ "$HAD_CODEX_CONFIG" -eq 0 ]; then
      rm -f -- "$LEON_CODEX_HOME_TMP/config.toml"
    fi
    if [ -d "$TX_SKILLS_BACKUP" ]; then
      if [ -e "$TX_SKILLS_LIVE" ]; then
        [ ! -e "$TX_SKILLS_FAILED" ] || TX_SKILLS_FAILED="${TX_SKILLS_FAILED}-$(date -u +%s)"
        mv -- "$TX_SKILLS_LIVE" "$TX_SKILLS_FAILED" || true
      fi
      mv -- "$TX_SKILLS_BACKUP" "$TX_SKILLS_LIVE" || true
    elif [ "$HAD_SKILLS" -eq 0 ] && [ ! -e "$LEON_DATA_DIR/.skills-stage-$TX_ID" ] \
         && [ -d "$TX_SKILLS_LIVE" ]; then
      [ ! -e "$TX_SKILLS_FAILED" ] || TX_SKILLS_FAILED="${TX_SKILLS_FAILED}-$(date -u +%s)"
      mv -- "$TX_SKILLS_LIVE" "$TX_SKILLS_FAILED" || true
    fi
    if [ "$SUDOERS_APPLIED" -eq 1 ]; then
      if [ "$HAD_SUDOERS" -eq 1 ]; then install -m 0440 "$SUDOERS_OLD" "$SUDOERS_PATH"; else rm -f -- "$SUDOERS_PATH"; fi
    fi
    if [ "$CRONTAB_APPLIED" -eq 1 ]; then
      if [ "$HAD_CRONTAB" -eq 1 ]; then crontab -u "$LEON_USER" "$CRONTAB_OLD" >/dev/null 2>&1 || true
      else crontab -u "$LEON_USER" -r >/dev/null 2>&1 || true; fi
    fi
    # Ultima conferencia do rollback: a unit que fica em /etc precisa apontar
    # pra um runtime que EXISTE. Se o caminho sumiu, a unit e entulho e so
    # produziria 200/CHDIR em todo restart: melhor nenhuma unit do que uma
    # unit quebrada, porque o cliente ve o erro e a casa fica honestamente
    # parada em vez de falhar em silencio.
    if [ -f "$UNIT_PATH" ] && [ ! -L "$UNIT_PATH" ]; then
      UNIT_RUNTIME_ROLLBACK="$(sed -n 's/^WorkingDirectory=//p' "$UNIT_PATH" | head -n1)"
      if [ -n "$UNIT_RUNTIME_ROLLBACK" ] && [ ! -e "$UNIT_RUNTIME_ROLLBACK/bridge.cjs" ]; then
        echo "AVISO: a unit apontava para '$UNIT_RUNTIME_ROLLBACK', que nao existe mais; removendo." >&2
        rm -f -- "$UNIT_PATH"
        WAS_ACTIVE=0
        WAS_ENABLED=0
      fi
      unset UNIT_RUNTIME_ROLLBACK
    fi
    systemctl daemon-reload >/dev/null 2>&1 || true
    if [ "$WAS_ENABLED" -eq 1 ]; then systemctl enable leon-agente.service >/dev/null 2>&1 || true
    else systemctl disable leon-agente.service >/dev/null 2>&1 || true; fi
    if [ "$WAS_ACTIVE" -eq 1 ]; then systemctl start leon-agente.service >/dev/null 2>&1 || true
    else systemctl stop leon-agente.service >/dev/null 2>&1 || true; fi
    systemctl reset-failed leon-agente.service >/dev/null 2>&1 || true
    echo "A versão que falhou ficou em: $TX_FAILED" >&2
  }

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

  ROOT_NEEDS_ROLLBACK=1
  (
  set +e
  printf '%s\n' "$BOT_TOKEN" | sudo -iu "$LEON_USER" env -u BOT_TOKEN \
    HOME="$LEON_HOME_TMP" \
    EMAIL="$EMAIL" \
    NOME="$NOME" \
    GENDER="$GENDER" \
    LEON_TOKEN_STDIN=1 \
    OWNER_CHAT_ID="$OWNER_CHAT_ID" \
    MOCK_MODE="$MOCK_MODE" \
    LEON_DIR="$INSTALL_DIR_TMP" \
    LEON_DATA_DIR="$LEON_DATA_DIR" \
    LEON_WORK_AREA="$LEON_WORK_AREA" \
    LEON_FORCE_USER_PHASE="$LEON_TEST_ROOT_USER_PHASE" \
    LEON_REPLACE_EXISTING="${LEON_REPLACE_EXISTING:-}" \
    LEON_CENTRAL="$CENTRAL" \
    LEON_ROOT_ORCHESTRATED=1 \
    LEON_TROCA_MOTOR="${LEON_TROCA_MOTOR:-0}" \
    LEON_TX_ID="$TX_ID" \
    LEON_TX_STAGE="$TX_STAGE" \
    LEON_TX_BACKUP="$TX_BACKUP" \
    LEON_TX_CONFIG_BACKUP="$TX_CONFIG_BACKUP" \
    LEON_TX_READY="$TX_READY" \
    LEON_TX_GO="$TX_GO" \
    LEON_TX_ABORT="$TX_ABORT" \
    LEON_CODEX_HOME="$LEON_CODEX_HOME_TMP" \
    LEON_CODEX_CLI_VERSION="$LEON_CODEX_CLI_VERSION" \
    LEON_CODEX_BIN_RESOLVED="$LEON_CODEX_BIN_RESOLVED" \
    LEON_NODE_VERSION="$LEON_NODE_VERSION" \
    LEON_NODE_BIN_RESOLVED="$LEON_NODE_BIN_RESOLVED" \
    LEON_CODEX_BUNDLE_FILE="$LEON_CODEX_BUNDLE_FILE" \
    LEON_BASE_PACKAGE_FILE="$LEON_BASE_PACKAGE_FILE" \
    LEON_BASE_PACKAGE_HASH_FILE="$LEON_BASE_PACKAGE_HASH_FILE" \
    bash "$INSTALLER_TMP"
  USER_PHASE_STATUS=${PIPESTATUS[1]}
  printf '%s\n' "$USER_PHASE_STATUS" > "$USER_PHASE_STATUS_FILE"
  ) &
  USER_PHASE_PID=$!
  set -e

  while kill -0 "$USER_PHASE_PID" 2>/dev/null; do
    if [ -f "$TX_READY" ]; then
      if [ "$WAS_ACTIVE" -eq 1 ]; then
        echo ">> stage validado; pausando o serviço somente para o commit atômico..."
        if ! systemctl stop leon-agente.service; then
          : > "$TX_ABORT"; chmod 0644 "$TX_ABORT"
          break
        fi
        SERVICE_STOPPED_FOR_COMMIT=1
      fi
      : > "$TX_GO"
      chmod 0644 "$TX_GO"
      break
    fi
    [ ! -s "$USER_PHASE_STATUS_FILE" ] || break
    sleep 0.2
  done
  set +e
  wait "$USER_PHASE_PID"
  set -e
  USER_PHASE_PID=""
  USER_PHASE_STATUS="$(cat "$USER_PHASE_STATUS_FILE" 2>/dev/null || echo 1)"
  printf %s "$USER_PHASE_STATUS" | grep -qE '^[0-9]+$' || USER_PHASE_STATUS=1

  if [ "$USER_PHASE_STATUS" -ne 0 ]; then
    echo "ERRO: a preparacao falhou. O servico anterior continua intacto." >&2
    exit "$USER_PHASE_STATUS"
  fi

  # Commit privilegiado da unit. Os arquivos ja foram trocados atomicamente
  # pela fase user e ainda possuem backup para este rollback.
  python3 - "$CRONTAB_OLD" "$CRONTAB_CANDIDATE" "$INSTALL_DIR_TMP" <<'PY'
import os,shlex,sys
old,candidate,runtime=sys.argv[1:]
jobs=[
 ("*/5 * * * *","scripts/update-guard.sh"),
 ("* * * * *","scripts/update-verdict.sh"),
 ("13 * * * *","scripts/update-auto.sh"),
 ("21 * * * *","scripts/aviso-manha.sh"),
]
targets=[os.path.join(runtime,rel) for _,rel in jobs]
lines=open(old,encoding="utf-8",errors="strict").read().splitlines()
lines=[line for line in lines if not any(target in line for target in targets)]
for schedule,rel in jobs:
    target=os.path.join(runtime,rel)
    if os.path.isfile(target) and not os.path.islink(target):
        lines.append(f"{schedule} {shlex.quote(target)} >/dev/null 2>&1")
open(candidate,"w",encoding="utf-8").write("\n".join(lines)+( "\n" if lines else ""))
PY
  SUDOERS_APPLIED=1
  install -m 0440 "$SUDOERS_CANDIDATE" "$SUDOERS_PATH.new"
  mv -f -- "$SUDOERS_PATH.new" "$SUDOERS_PATH"
  CRONTAB_APPLIED=1
  crontab -u "$LEON_USER" "$CRONTAB_CANDIDATE"
  if [ "$MOCK_MODE" != 1 ] && command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify "$UNIT_CANDIDATE" >/dev/null 2>&1 || {
      rollback_install
      exit 1
    }
  fi
  # A unit so entra em /etc depois que o alvo dela existe e compila NO LUGAR
  # FINAL. Sem esta trava, um commit da fase user que nao chegou ao fim deixa
  # /etc apontando pra um caminho vazio e todo systemctl restart falha com
  # status=200/CHDIR, mesmo com o processo antigo ainda respondendo.
  if [ ! -d "$INSTALL_DIR_TMP" ] || [ ! -f "$INSTALL_DIR_TMP/bridge.cjs" ]; then
    echo "ERRO: runtime ausente em '$INSTALL_DIR_TMP'; a unit nao sera trocada." >&2
    rollback_install
    exit 1
  fi
  if ! "$NODE_BIN" --check "$INSTALL_DIR_TMP/bridge.cjs" >/dev/null 2>&1; then
    echo "ERRO: o bridge no lugar final nao passou no node --check." >&2
    rollback_install
    exit 1
  fi
  UNIT_APPLIED=1
  install -m 0644 "$UNIT_CANDIDATE" "$UNIT_PATH.new"
  mv -f -- "$UNIT_PATH.new" "$UNIT_PATH"
  systemctl daemon-reload
  systemctl enable leon-agente.service >/dev/null
  if ! systemctl restart leon-agente.service; then
    rollback_install
    exit 1
  fi

  SERVICE_OK=0
  for _ in $(seq 1 15); do
    if systemctl is-active leon-agente.service >/dev/null 2>&1 \
       && [ "$(systemctl show -p MainPID --value leon-agente.service 2>/dev/null || echo 0)" -gt 0 ]; then
      SERVICE_OK=1
      break
    fi
    sleep 1
  done
  if [ "$SERVICE_OK" -ne 1 ]; then
    rollback_install
    exit 1
  fi
  FIRST_PID=$(systemctl show -p MainPID --value leon-agente.service)
  sleep 3
  SECOND_PID=$(systemctl show -p MainPID --value leon-agente.service)
  if [ "$FIRST_PID" != "$SECOND_PID" ] || [ "$SECOND_PID" -le 0 ] \
     || ! systemctl is-active leon-agente.service >/dev/null 2>&1; then
    rollback_install
    exit 1
  fi

  if [ "$MOCK_MODE" != "1" ]; then
    TELEGRAM_SMOKE=$(mktemp)
    if ! telegram_api_get_file "$BOT_TOKEN" getMe "$TELEGRAM_SMOKE" 15 \
       || ! python3 - "$TELEGRAM_SMOKE" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    ok = data.get("ok") is True and isinstance(data.get("result", {}).get("id"), int)
except Exception:
    ok = False
raise SystemExit(0 if ok else 1)
PY
    then
      rm -f -- "$TELEGRAM_SMOKE"
      rollback_install
      exit 1
    fi
    rm -f -- "$TELEGRAM_SMOKE"
  fi

  ROOT_NEEDS_ROLLBACK=0
  apaga_backup_de_catalogo "$TX_SKILLS_BACKUP" "$TX_SKILLS_LIVE" "$LEON_SKILLS_PESSOAIS_DIR" "$LEON_USER"
  PRESERVE_CODEX_RELEASE=1
  PRESERVE_NODE_RELEASE=1
  ROOT_KEEP_BOOTSTRAP=1

  echo ""
  echo "========================================"
  echo "  MOTOR LEON INSTALADO E VALIDADO"
  echo "========================================"
  echo "Teu LEON esta rodando em $INSTALL_DIR_TMP com o motor Codex."
  echo "Servico: sudo systemctl is-active leon-agente.service"
  echo "Log: sudo journalctl -u leon-agente.service -n 200 --no-pager"
  [ -d "$TX_BACKUP" ] && echo "Backup recuperavel da versao anterior: $TX_BACKUP"
  exit 0
fi

# ============================================================
# 2. FASE USER (nao-root)
# ============================================================
if [ "$LEON_ROOT_ORCHESTRATED" != "1" ] && [ "$LEON_FORCE_USER_PHASE" != "1" ]; then
  echo "ERRO: inicie o instalador como root; a troca e o rollback dependem da fase coordenadora." >&2
  exit 1
fi

# A fase do usuário não pode herdar um diretório inacessível (por exemplo,
# /root) do coordenador. Além de quebrar utilitários como find, isso tornaria
# o comportamento dependente da implementação de sudo usada pela VPS.
if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ] || [ -L "$HOME" ]; then
  echo "ERRO: HOME da fase do usuário ausente, inválido ou simbólico." >&2
  exit 1
fi
cd -- "$HOME" || {
  echo "ERRO: não foi possível entrar no HOME da fase do usuário." >&2
  exit 1
}

# LEITOR TOML (23/09): Ubuntu 22.04 tem Python 3.10, sem tomllib. Sem tomllib/tomli o merge do
# config.toml nao consegue ler o do dono; ele fica INTACTO (leon_preserva sai 3), mas o molde
# do produto nao entra. Igual ao install-leon.sh: tomli no usuario, antes do merge.
if ! python3 -c 'import tomllib' >/dev/null 2>&1 && ! python3 -c 'import tomli' >/dev/null 2>&1; then
  echo ">> instalando leitor TOML (tomli) pro merge do config.toml..."
  python3 -m pip install --quiet --user tomli >/dev/null 2>"${TMPDIR:-/tmp}/pip-tomli-$$.err" || true
  if ! python3 -c 'import tomli' >/dev/null 2>&1; then
    echo "   (aviso) o python ficou sem leitor TOML: o teu config.toml fica intacto e o LEON segue pelos parametros do app-server."
  fi
  rm -f -- "${TMPDIR:-/tmp}/pip-tomli-$$.err"
fi

LIVE_DIR="${LEON_DIR:-$HOME/socio-ia}"
INSTALL_DIR="$LIVE_DIR"
# LEITOR UNICO DAS PASTAS (24/09, rodada 5): com .env na casa, toda pasta sai dele pelo leitor do
# bridge (leon_bases_do_dono): LEON_DATA_DIR; dele BRAIN_DIR, MEMVIVA_FILE, ASSUNTOS_FILE,
# LEON_STATE_DIR, LEON_MISSIONS_DIR, LEON_PROMISES_DIR, PERSONA_DIR, LEON_SKILLS_PESSOAIS_DIR (0.7:
# catalogo do dono, que o updater nunca toca). Sem .env (casa nova), as variaveis da fase root.
leon_bases_do_dono "$LIVE_DIR/.env" || { echo "ERRO: nao consegui ler as pastas do .env desta casa." >&2; exit 1; }
LEON_CODEX_HOME="$LEON_DATA_DIR/codex"
[ -n "$LEON_SKILLS_DIR" ] || LEON_SKILLS_DIR="$LEON_DATA_DIR/skills"
# a pasta de login que o bridge usa HOJE (homeDoMotor): e nela que o login e o smoke conferem
LEON_CODEX_HOME_MOTOR="$(leon_preserva home-do-motor "$LIVE_DIR/.env" codex "$LEON_CODEX_HOME")"
NODE_BIN="${LEON_NODE_BIN_RESOLVED:-$(command -v node || true)}"
validate_runtime_roots() {
  local require_exists="${1:-0}"
  python3 - "$require_exists" "$HOME" "$LIVE_DIR" "$LEON_DATA_DIR" "$LEON_CODEX_HOME" \
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
    if not contains(home, target) or target == home:
        raise SystemExit(f"{name} must be a strict descendant of home")
    cursor = home
    relative = os.path.relpath(target, home)
    for part in relative.split(os.sep):
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
        if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
            raise SystemExit(f"{name} is not a real directory")
        if os.path.realpath(target) != target:
            raise SystemExit(f"{name} resolves through a symlink")
    elif require_exists and name not in ("runtime", "skills", "ssh"):
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
validate_runtime_roots 0 || { echo "ERRO: caminhos de dados inseguros; nada foi criado." >&2; exit 1; }
CREATED_DATA_DIRS=()
for candidate_dir in "$LEON_DATA_DIR" "$LEON_CODEX_HOME" "$LEON_TMPDIR" "$BRAIN_DIR" \
  "$PERSONA_DIR" "$LEON_WORK_AREA" "$LEON_STATE_DIR" "$LEON_MISSIONS_DIR" \
  "$LEON_PROMISES_DIR" "$LEON_MISSION_OUTPUT_DIR"; do
  [ -e "$candidate_dir" ] || CREATED_DATA_DIRS+=("$candidate_dir")
done
PERSONA_CREATED=0
PERSONA_CREATED_SHA=""
mkdir -p "$LEON_CODEX_HOME" "$LEON_TMPDIR" "$BRAIN_DIR" \
  "$PERSONA_DIR" "$LEON_WORK_AREA" "$LEON_MISSIONS_DIR" "$LEON_PROMISES_DIR" "$LEON_MISSION_OUTPUT_DIR" \
  "$LEON_SKILLS_PESSOAIS_DIR"
chmod 700 "$LEON_DATA_DIR" "$LEON_CODEX_HOME" "$LEON_TMPDIR" "$LEON_STATE_DIR" \
  "$LEON_MISSIONS_DIR" "$LEON_PROMISES_DIR" "$LEON_MISSION_OUTPUT_DIR"
validate_runtime_roots 1 || { echo "ERRO: caminhos de dados mudaram durante a criação; instalação abortada." >&2; exit 1; }
if [ ! -s "$PERSONA_DIR/main.md" ]; then
  cat > "$PERSONA_DIR/main.md" <<'PERSONA'
# Persona principal

Fale com clareza, objetividade e honestidade. Use o nome configurado do agente.
Nunca invente execução, acesso, ferramenta ou resultado. Confira o artefato antes de declarar conclusão.
Nunca solicite senha, token, chave privada ou outro segredo pelo chat.
PERSONA
  chmod 0600 "$PERSONA_DIR/main.md"
  PERSONA_CREATED=1
  PERSONA_CREATED_SHA="$(sha256sum "$PERSONA_DIR/main.md" | awk '{print $1}')"
fi

TX_ID="${LEON_TX_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
LIVE_PARENT=$(dirname "$LIVE_DIR")
LIVE_BASE=$(basename "$LIVE_DIR")
DEPLOY_STAGE="${LEON_TX_STAGE:-$LIVE_PARENT/.${LIVE_BASE}.leon-stage-$TX_ID}"
DEPLOY_BACKUP="${LEON_TX_BACKUP:-$LIVE_PARENT/.${LIVE_BASE}.leon-backup-$TX_ID}"
CONFIG_BACKUP="${LEON_TX_CONFIG_BACKUP:-$LEON_CODEX_HOME/config.toml.leon-backup-$TX_ID}"
CONFIG_CANDIDATE="$LEON_CODEX_HOME/config.toml.leon-candidate-$TX_ID"
DEPLOY_COMMITTED=0
CONFIG_APPLIED=0
CONFIG_HAD_ORIGINAL=0
TARBALL=""
BASE_HASH_FILE=""
RELEASE_MANIFEST=""
RELEASE_SIGNATURE=""
RELEASE_PUBLIC_KEY=""
RELEASE_METADATA=""
EXTRACT_TMP=""
BUNDLE_TMP=""
BUNDLE_EXTRACT=""
SKILLS_TMP=""
SKILLS_EXTRACT=""
SKILLS_STAGE="$LEON_DATA_DIR/.skills-stage-$TX_ID"
SKILLS_BACKUP="$LEON_DATA_DIR/.skills-backup-$TX_ID"
SKILLS_FAILED="$LEON_DATA_DIR/.skills-failed-$TX_ID"
SKILLS_SWAPPED=0
SKILLS_HAD_ORIGINAL=0
SKILLS_EXPECTED_DIGEST=""
PROBE_DIR=""
SMOKE_OUT=""
SMOKE_DIR=""
PREV_ENV_SAFE=""

if [ -e "$SKILLS_STAGE" ] || [ -e "$SKILLS_BACKUP" ] || [ -e "$SKILLS_FAILED" ]; then
  echo "ERRO: colisão nos caminhos da transação do catálogo de skills." >&2
  exit 1
fi

normalizar_agent_base() {
  local agent_base="$1"
  [ -f "$agent_base" ] || return 0
  python3 - "$agent_base" "$LEON_SKILLS_DIR" "$LIVE_DIR" "$LEON_TMPDIR" "$LEON_CODEX_HOME" \
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

validate_curated_base_manifest() {
  local package_root="$1"
  python3 - "$package_root" <<'PY'
import hashlib, json, os, re, stat, sys
root = os.path.abspath(sys.argv[1])
try:
    raw = open(os.path.join(root, "base-manifest.json"), "rb").read()
    if len(raw) > 512_000: raise ValueError("manifest too large")
    manifest = json.loads(raw)
except Exception as exc: raise SystemExit(f"invalid base manifest: {exc}")
if manifest.get("schema") != 2 or manifest.get("kind") != "leon-codex-curated-base": raise SystemExit("identity")
if not re.fullmatch(r"[0-9a-f]{40}", str((manifest.get("source") or {}).get("commit", ""))): raise SystemExit("commit")
security = manifest.get("security") or {}
for key in ("devices_allowed", "external_symlinks_allowed", "hardlinks_allowed", "private_keys_allowed", "setuid_or_setgid_allowed"):
    if security.get(key) is not False: raise SystemExit(f"unsafe {key}")
files, allowlist = manifest.get("files"), manifest.get("allowlist")
if not isinstance(files, list) or not isinstance(allowlist, list) or not files: raise SystemExit("files")
if allowlist != sorted(allowlist, key=lambda p:p.encode()) or len(set(allowlist)) != len(allowlist): raise SystemExit("allowlist")
entries = {}
for item in files:
    if not isinstance(item, dict) or set(item) != {"path","sha256","bytes","mode"}: raise SystemExit("entry")
    rel = item.get("path")
    if not isinstance(rel,str) or not rel or not rel.isascii() or rel.startswith("/") or "\\" in rel: raise SystemExit("path")
    if any(part in ("",".","..") or part.casefold()=="keys" or part==".env" for part in rel.split("/")): raise SystemExit("unsafe path")
    if rel in entries or not re.fullmatch(r"[0-9a-f]{64}", str(item.get("sha256",""))): raise SystemExit("hash")
    if not isinstance(item.get("bytes"),int) or not 0 <= item["bytes"] <= 536_870_912: raise SystemExit("size")
    if item.get("mode") not in ("0600","0700"): raise SystemExit("mode")
    entries[rel]=item
if list(entries) != allowlist: raise SystemExit("order")
actual=[]
for base, dirs, names in os.walk(root, topdown=True, followlinks=False):
    for dirname in dirs:
        if stat.S_ISLNK(os.lstat(os.path.join(base,dirname)).st_mode): raise SystemExit("symlink")
    for name in names:
        rel=os.path.relpath(os.path.join(base,name),root).replace(os.sep,"/")
        if rel != "base-manifest.json": actual.append(rel)
if sorted(actual,key=lambda p:p.encode()) != allowlist: raise SystemExit("tree")
lines=[]
for rel in allowlist:
    full=os.path.join(root,*rel.split("/")); info=os.lstat(full)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1: raise SystemExit("not regular")
    content=open(full,"rb").read(); entry=entries[rel]; digest=hashlib.sha256(content).hexdigest(); mode=f"{stat.S_IMODE(info.st_mode):04o}"
    if len(content)!=entry["bytes"] or digest!=entry["sha256"] or mode!=entry["mode"]: raise SystemExit(f"mismatch {rel}")
    lines.append(f"{digest}\t{len(content)}\t{mode}\t{rel}\n".encode())
fmt="sha256<TAB>bytes<TAB>mode4<TAB>path<LF>; payload files only; path bytewise ascending"
if manifest.get("content_tree_format") != fmt or hashlib.sha256(b"".join(lines)).hexdigest() != manifest.get("content_tree_sha256"): raise SystemExit("tree hash")
PY
}

audit_skills_archive() {
  local archive="$1"
  python3 - "$archive" <<'PY'
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
for name,kind in seen.items():
    parts=name.split("/")
    for i in range(1,len(parts)):
        parent="/".join(parts[:i])
        if seen.get(parent)=="file": raise SystemExit(1)
if not root or not manifest: raise SystemExit(1)
PY
}

validate_skills_manifest() {
  local root="$1"
  python3 - "$root" <<'PY'
import hashlib,json,os,posixpath,re,stat,sys
root=os.path.abspath(sys.argv[1]); manifest_path=os.path.join(root,"skills-manifest.json")
try:
    info=os.lstat(manifest_path)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or info.st_size>512_000: raise ValueError()
    manifest=json.load(open(manifest_path,encoding="utf-8"))
except Exception: raise SystemExit(1)
top={"capabilities","content_tree_format","content_tree_sha256","excluded","files","kind","placeholders","schema","skill_count","skills","source"}
if set(manifest)!=top or manifest["schema"]!=2: raise SystemExit(1)
# Release A transicional: aceita o catálogo MINIMAL (2 fixas pinadas) OU o CURATED (>=30, validação estrutural).
if not isinstance(manifest["skills"],list) or manifest["skill_count"]!=len(manifest["skills"]): raise SystemExit(1)
if not all(isinstance(s,str) and re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}",s) and s not in (".","..") for s in manifest["skills"]) or len(set(manifest["skills"]))!=len(manifest["skills"]): raise SystemExit(1)
if manifest["kind"]=="leon-codex-minimal-skills":
    if manifest["skills"]!=["soft-critico-copy","soft-designer"] or manifest["skill_count"]!=2: raise SystemExit(1)
elif manifest["kind"]=="leon-codex-curated-skills":
    if manifest["skill_count"]<30: raise SystemExit(1)
else:
    raise SystemExit(1)
if manifest["placeholders"]!={"@@LEON_SKILLS_DIR@@":"absolute read-only skills directory","@@LEON_WORK_AREA@@":"absolute user work directory"}: raise SystemExit(1)
# capabilities: metadado declaratorio, nao gate de seguranca. Campo presente e do tipo objeto, sem pin de igualdade.
if not isinstance(manifest["capabilities"],dict): raise SystemExit(1)
# Sem pin de commit (o catálogo curado atualiza): valida só repositório esperado e árvore limpa.
if not isinstance(manifest["source"],dict) or set(manifest["source"])!={"commit","dirty","repository"}: raise SystemExit(1)
if manifest["source"]["repository"]!="https://github.com/molinateston/soft.git" or manifest["source"]["dirty"] is not False: raise SystemExit(1)
if not re.fullmatch(r"[0-9a-f]{40}",str(manifest["source"]["commit"])): raise SystemExit(1)
files=manifest["files"]
if not isinstance(files,list) or not files: raise SystemExit(1)
paths=[]; entries={}; lines=[]
for item in files:
    if not isinstance(item,dict) or set(item)!={"path","sha256","bytes","mode"}: raise SystemExit(1)
    rel=item["path"]
    if not isinstance(rel,str) or not rel or rel.startswith("/") or "\\" in rel or posixpath.normpath(rel)!=rel: raise SystemExit(1)
    if any(part in ("",".","..") or part.casefold()=="keys" or part==".env" for part in rel.split("/")): raise SystemExit(1)
    if rel.split("/",1)[0] not in manifest["skills"] or rel in entries: raise SystemExit(1)
    if not re.fullmatch(r"[0-9a-f]{64}",str(item["sha256"])) or not isinstance(item["bytes"],int) or not 0<=item["bytes"]<=64*1024*1024: raise SystemExit(1)
    if item["mode"] not in ("0400","0500"): raise SystemExit(1)
    entries[rel]=item; paths.append(rel)
if paths!=sorted(paths,key=lambda p:p.encode("utf-8")): raise SystemExit(1)
actual=[]
for base,dirs,names in os.walk(root,topdown=True,followlinks=False):
    for d in dirs:
        st=os.lstat(os.path.join(base,d))
        if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode): raise SystemExit(1)
    for name in names:
        rel=os.path.relpath(os.path.join(base,name),root).replace(os.sep,"/")
        if rel!="skills-manifest.json": actual.append(rel)
if sorted(actual,key=lambda p:p.encode("utf-8"))!=paths: raise SystemExit(1)
for rel in paths:
    full=os.path.join(root,*rel.split("/")); st=os.lstat(full); item=entries[rel]
    if not stat.S_ISREG(st.st_mode) or st.st_nlink!=1: raise SystemExit(1)
    raw=open(full,"rb").read(); digest=hashlib.sha256(raw).hexdigest(); mode=f"{stat.S_IMODE(st.st_mode):04o}"
    if len(raw)!=item["bytes"] or digest!=item["sha256"] or mode!=item["mode"]: raise SystemExit(1)
    lowered=raw.lower()
    # Frente D: veto ao literal "claude" saiu (motor legítimo do produto). "openclaw" (ferramenta
    # interna do dono), private key e bypasspermissions continuam; catálogo já é purgado deles.
    if (b"open"+b"claw") in lowered or b"bypasspermissions" in lowered or b"-----begin private key-----" in lowered: raise SystemExit(1)
    # veto por PREFIXO a caminho/identidade privados do dono que sobrevivam à sanitização.
    if b"/home/" in lowered or b"/root/" in lowered or b".openclaw" in lowered or b"leomolina" in lowered or b"leonardomolina" in lowered or b"raizonline" in lowered: raise SystemExit(1)
    lines.append(f"{digest}\t{len(raw)}\t{mode}\t{rel}\n".encode())
fmt="sha256<TAB>bytes<TAB>mode4<TAB>path<LF>; payload files only; path bytewise ascending"
if manifest["content_tree_format"]!=fmt or hashlib.sha256(b"".join(lines)).hexdigest()!=manifest["content_tree_sha256"]: raise SystemExit(1)
for skill in manifest["skills"]:
    if f"{skill}/SKILL.md" not in entries: raise SystemExit(1)
PY
}

normalize_skills_catalog() {
  local root="$1" canonical_skills="$2" work_area="$3"
  python3 - "$root" "$canonical_skills" "$work_area" <<'PY'
import json,os,stat,sys
root,skills_dir,work_area=map(os.path.abspath,sys.argv[1:])
manifest_path=os.path.join(root,"skills-manifest.json")
manifest=json.load(open(manifest_path,encoding="utf-8")); entries={x["path"]:x for x in manifest["files"]}
for base,dirs,_ in os.walk(root):
    os.chmod(base,0o700)
for rel,item in entries.items():
    full=os.path.join(root,*rel.split("/")); raw=open(full,"rb").read()
    if b"@@LEON_" in raw:
        text=raw.decode("utf-8")
        text=text.replace("@@LEON_SKILLS_DIR@@",skills_dir).replace("@@LEON_WORK_AREA@@",work_area)
        if "@@LEON_" in text: raise SystemExit(1)
        raw=text.encode()
    temp=full+".leon-new"
    fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,"O_NOFOLLOW",0),0o600)
    try: os.write(fd,raw); os.fsync(fd)
    finally: os.close(fd)
    os.replace(temp,full); os.chmod(full,int(item["mode"],8))
os.unlink(manifest_path)
for base,dirs,names in os.walk(root):
    for name in names:
        if b"@@LEON_" in open(os.path.join(base,name),"rb").read(): raise SystemExit(1)
for base,_,_ in sorted(os.walk(root),key=lambda x:x[0].count(os.sep),reverse=True): os.chmod(base,0o500)
PY
}

installed_skills_digest() {
  python3 - "$1" <<'PY'
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

safe_copy_state_file() {
  local source="$1" destination="$2" kind="$3"
  python3 - "$source" "$destination" "$kind" <<'PY'
import json, os, re, stat, sys
source, destination, kind = sys.argv[1:]
limits = {"env": 256 * 1024, "sessions": 16 * 1024 * 1024, "topics": 2 * 1024 * 1024, "onboarding": 64 * 1024, "meta": 64 * 1024}
if kind not in limits: raise SystemExit(1)
try:
    info = os.lstat(source)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > limits[kind]: raise SystemExit(1)
    fd = os.open(source, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        before = os.fstat(fd); raw = os.read(fd, before.st_size + 1); after = os.fstat(fd)
    finally: os.close(fd)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > limits[kind]: raise SystemExit(1)
    if info.st_dev != before.st_dev or info.st_ino != before.st_ino: raise SystemExit(1)
    if before.st_dev != after.st_dev or before.st_ino != after.st_ino or after.st_nlink != 1 or after.st_size != before.st_size or len(raw) != before.st_size: raise SystemExit(1)
    if re.search(br"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----", raw): raise SystemExit(1)
    if kind == "env":
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077: raise SystemExit(1)
        text = raw.decode("utf-8")
        if "\x00" in text: raise SystemExit(1)
        seen = set()
        for line in text.splitlines():
            if not line.strip() or line.lstrip().startswith("#"): continue
            match = re.fullmatch(r"\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*", line)
            if not match or match.group(1) in seen: raise SystemExit(1)
            seen.add(match.group(1))
    else:
        data = json.loads(raw)
        if not isinstance(data, dict): raise SystemExit(1)
        if kind == "topics" and len(data) > 1000: raise SystemExit(1)
        if kind == "sessions" and len(data) > 10000: raise SystemExit(1)
except Exception: raise SystemExit(1)
temp = destination + ".state-new"
flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
try:
    out = os.open(temp, flags, 0o600)
    try: os.write(out, raw); os.fsync(out)
    finally: os.close(out)
    os.replace(temp, destination)
finally:
    try: os.unlink(temp)
    except FileNotFoundError: pass
PY
}

cleanup_user_phase() {
  [ -z "$TARBALL" ] || rm -f -- "$TARBALL"
  [ -z "$BASE_HASH_FILE" ] || rm -f -- "$BASE_HASH_FILE"
  [ -z "$RELEASE_MANIFEST" ] || rm -f -- "$RELEASE_MANIFEST"
  [ -z "$RELEASE_SIGNATURE" ] || rm -f -- "$RELEASE_SIGNATURE"
  [ -z "$RELEASE_PUBLIC_KEY" ] || rm -f -- "$RELEASE_PUBLIC_KEY"
  [ -z "$RELEASE_METADATA" ] || rm -f -- "$RELEASE_METADATA"
  [ -z "$EXTRACT_TMP" ] || rm -rf -- "$EXTRACT_TMP"
  [ -z "$BUNDLE_TMP" ] || rm -f -- "$BUNDLE_TMP"
  [ -z "${BUNDLE_HASH_FILE:-}" ] || rm -f -- "$BUNDLE_HASH_FILE"
  [ -z "$BUNDLE_EXTRACT" ] || rm -rf -- "$BUNDLE_EXTRACT"
  [ -z "$SKILLS_TMP" ] || rm -f -- "$SKILLS_TMP"
  [ -z "$SKILLS_EXTRACT" ] || rm -rf -- "$SKILLS_EXTRACT"
  [ -z "$PROBE_DIR" ] || rm -rf -- "$PROBE_DIR"
  [ -z "$SMOKE_OUT" ] || rm -f -- "$SMOKE_OUT"
  [ -z "$SMOKE_DIR" ] || rm -rf -- "$SMOKE_DIR"
  [ -z "$PREV_ENV_SAFE" ] || rm -f -- "$PREV_ENV_SAFE"
  rm -f -- "$CONFIG_CANDIDATE"
  if [ "$DEPLOY_COMMITTED" -ne 1 ]; then
    [ ! -e "$DEPLOY_STAGE" ] || rm -rf -- "$DEPLOY_STAGE"
    # o stage do catalogo e selado (0500/0400): sem devolver +w o rm nao apaga e sobra lixo
    [ ! -e "$SKILLS_STAGE" ] || { chmod -R u+w -- "$SKILLS_STAGE" 2>/dev/null; rm -rf -- "$SKILLS_STAGE"; }
    if [ "$SKILLS_SWAPPED" -eq 1 ]; then
      [ ! -e "$LEON_SKILLS_DIR" ] || mv -- "$LEON_SKILLS_DIR" "$SKILLS_FAILED" 2>/dev/null || true
      if [ "$SKILLS_HAD_ORIGINAL" -eq 1 ] && [ -d "$SKILLS_BACKUP" ]; then
        mv -- "$SKILLS_BACKUP" "$LEON_SKILLS_DIR" 2>/dev/null || true
      fi
    fi
    if [ "$CONFIG_APPLIED" -eq 1 ]; then
      if [ "$CONFIG_HAD_ORIGINAL" -eq 1 ] && [ -f "$CONFIG_BACKUP" ]; then
        mv -f -- "$CONFIG_BACKUP" "$LEON_CODEX_HOME/config.toml"
      else
        rm -f -- "$LEON_CODEX_HOME/config.toml"
      fi
    fi
    if [ "$PERSONA_CREATED" -eq 1 ] && [ -f "$PERSONA_DIR/main.md" ] \
       && [ ! -L "$PERSONA_DIR/main.md" ] \
       && [ "$(sha256sum "$PERSONA_DIR/main.md" | awk '{print $1}')" = "$PERSONA_CREATED_SHA" ]; then
      rm -f -- "$PERSONA_DIR/main.md"
    fi
    local i
    for ((i=${#CREATED_DATA_DIRS[@]}-1; i>=0; i--)); do
      rmdir -- "${CREATED_DATA_DIRS[$i]}" 2>/dev/null || true
    done
  fi
}
trap cleanup_user_phase EXIT

command -v curl >/dev/null || { echo "ERRO: curl faltando." >&2; exit 1; }
command -v tar  >/dev/null || { echo "ERRO: tar faltando." >&2; exit 1; }
if [ "$MOCK_MODE" != "1" ]; then
  EXPECTED_NODE_BIN="$LEON_DATA_DIR/node/releases/$LEON_NODE_VERSION/bin/node"
  [ "$LEON_NODE_BIN_RESOLVED" = "$EXPECTED_NODE_BIN" ] \
    && validate_dedicated_node "$LEON_NODE_BIN_RESOLVED" "$LEON_DATA_DIR" "$LEON_NODE_VERSION" \
    || { echo "ERRO: runtime Node dedicado ausente ou inseguro." >&2; exit 1; }
  [ "$(node_runtime_version "$LEON_NODE_BIN_RESOLVED" || true)" = "$LEON_NODE_VERSION" ] \
    || { echo "ERRO: runtime Node dedicado não está na versão $LEON_NODE_VERSION." >&2; exit 1; }
  NODE_BIN="$LEON_NODE_BIN_RESOLVED"
  EXPECTED_CODEX_BIN="$LEON_DATA_DIR/codex-cli/releases/$LEON_CODEX_CLI_VERSION/bin/codex"
  [ "$LEON_CODEX_BIN_RESOLVED" = "$EXPECTED_CODEX_BIN" ] \
    && validate_dedicated_codex_cli "$LEON_CODEX_BIN_RESOLVED" "$LEON_DATA_DIR" "$LEON_CODEX_CLI_VERSION" \
    || { echo "ERRO: Codex CLI dedicado ausente ou inseguro." >&2; exit 1; }
  INSTALLED_CODEX_VERSION="$(codex_cli_version "$LEON_CODEX_BIN_RESOLVED" || true)"
  if [ "$INSTALLED_CODEX_VERSION" != "$LEON_CODEX_CLI_VERSION" ]; then
    echo "ERRO: codex-cli está em '${INSTALLED_CODEX_VERSION:-ausente}', esperado $LEON_CODEX_CLI_VERSION." >&2
    echo "Rode novamente este instalador como root para ajustar a versão antes de continuar." >&2
    exit 1
  fi
else
  [ -x "$NODE_BIN" ] || { echo "ERRO: fixture Node ausente." >&2; exit 1; }
fi

# Molde do config.toml, o MESMO do atualizador (decisao do dono 04/09: acesso total, sem perfil
# de permissoes nomeado; provado no 99 que default_permissions + [permissions.*] mantem o bwrap
# ligado sob danger-full-access e o Codex morre em "setting up uid map"). O molde nao vence o
# config do dono: ele so acrescenta o que falta (leon_preserva toml-funde, na hora de aplicar).
  # ESFORÇO POR TAREFA (2.4.31): o config nasce em "medium". O bridge roteia o esforço por
  # fala (low no trivial, high na missão e no pedido de raciocínio), então este valor é só o
  # piso de quem roda o Codex fora da ponte. "high" cravado aqui era raciocínio invisível
  # cobrado em todo turno, e é o que estourava a cota do dono no plano Plus.
cat > "$CONFIG_CANDIDATE" <<EOF
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"
preferred_auth_method = "chatgpt"
sandbox_mode = "danger-full-access"
approval_policy = "never"
allow_login_shell = false

[projects."$LIVE_DIR"]
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
# .env da casa ou o runtime. Olhar so no runtime tirava o meta-ads da casa com WORK_DIR proprio.
_META_WD=""
[ ! -f "$LIVE_DIR/.env" ] || [ -L "$LIVE_DIR/.env" ] || _META_WD="$(leon_preserva env-valor "$LIVE_DIR/.env" WORK_DIR 2>/dev/null)" || _META_WD=""
case "$_META_WD" in /*) ;; '') _META_WD="$LIVE_DIR" ;; *) _META_WD="$LIVE_DIR/$_META_WD" ;; esac
if [ -f "$_META_WD/.meta-token.json" ] || [ -f "$LIVE_DIR/.meta-token.json" ]; then
  cat >> "$CONFIG_CANDIDATE" <<METAEOF

[mcp_servers.meta-ads]
command = "node"
args = ["$LIVE_DIR/lib/meta-mcp-codex-filter.cjs"]
startup_timeout_sec = 20
tool_timeout_sec = 30
METAEOF
fi
chmod 600 "$CONFIG_CANDIDATE"

# ------------------------------------------------------------
# 2.1 Acesso do Codex. A fase root ja conduziu o login por codigo de
# dispositivo. Esta segunda leitura impede qualquer troca se a credencial
# desaparecer entre o checkpoint e a preparacao sem privilegio.
# ------------------------------------------------------------
CODEX_AUTENTICADO="nao"
if [ "$MOCK_MODE" != "1" ]; then
  if PATH="$(dirname "$NODE_BIN"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
       CODEX_HOME="$LEON_CODEX_HOME_MOTOR" "$LEON_CODEX_BIN_RESOLVED" login status >/dev/null 2>&1; then
    CODEX_AUTENTICADO="login"
    echo ">> Codex ja estava logado nesta VPS."
  else
    CODEX_AUTENTICADO="ausente"
  fi
fi

if [ "$CODEX_AUTENTICADO" = "ausente" ]; then
  echo "ERRO: a autenticacao Codex desapareceu depois do checkpoint seguro." >&2
  echo "Nenhum arquivo LEON sera trocado e o servico atual continua intacto." >&2
  exit 1
fi

# A nova versao nasce em um diretorio irmao do destino. O rename do commit
# acontece no mesmo filesystem; uma falha nunca mistura arquivos velhos e novos.
if [ -L "$LIVE_DIR" ] || { [ -e "$LIVE_DIR" ] && [ ! -d "$LIVE_DIR" ]; }; then
  echo "ERRO: o destino '$LIVE_DIR' nao e um diretorio real." >&2
  exit 1
fi
mkdir -p "$LIVE_PARENT"
if [ -e "$DEPLOY_STAGE" ] || [ -e "$DEPLOY_BACKUP" ]; then
  echo "ERRO: caminhos da transacao ja existem; abortando sem sobrescrever nada." >&2
  exit 1
fi
mkdir -m 0700 "$DEPLOY_STAGE"
INSTALL_DIR="$DEPLOY_STAGE"

# Falha cedo para token inexistente ou revogado. O retorno nao e exibido para
# que nenhum detalhe da credencial apareca no log do instalador.
if [ "$MOCK_MODE" != "1" ]; then
  TG_PREFLIGHT=$(mktemp)
  BOT_ID_PREFIX=$(printf %s "$BOT_TOKEN" | cut -d: -f1)
  if ! telegram_api_get_file "$BOT_TOKEN" getMe "$TG_PREFLIGHT" 15 \
     || ! python3 - "$TG_PREFLIGHT" "$BOT_ID_PREFIX" <<'PY'
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
    rm -f -- "$TG_PREFLIGHT"
    echo "ERRO: o Telegram recusou esse token. Confere no BotFather e tente de novo." >&2
    exit 1
  fi
  rm -f -- "$TG_PREFLIGHT"
  echo ">> token do bot validado pelo Telegram."
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
if [ "$MOCK_MODE" != "1" ] || [ -n "$LEON_BASE_PACKAGE_FILE" ]; then
  echo ""
  echo ">> validando compra e baixando motor..."
  RELEASE_MANIFEST=$(mktemp)
  RELEASE_SIGNATURE=$(mktemp)
  RELEASE_PUBLIC_KEY=$(mktemp)
  RELEASE_METADATA=$(mktemp)
  if [ -n "$LEON_BASE_PACKAGE_FILE" ] && [ "$MOCK_MODE" = "1" ]; then
    RELEASE_SOURCE_DIR="$(dirname "$LEON_BASE_PACKAGE_FILE")"
    [ -f "$RELEASE_SOURCE_DIR/release-manifest.json" ] \
      && [ -f "$RELEASE_SOURCE_DIR/release-manifest.sig" ] \
      || { echo "ERRO: fixture local exige release-manifest assinado." >&2; exit 1; }
    cp -- "$RELEASE_SOURCE_DIR/release-manifest.json" "$RELEASE_MANIFEST"
    cp -- "$RELEASE_SOURCE_DIR/release-manifest.sig" "$RELEASE_SIGNATURE"
  else
    curl -fsSL --max-filesize 524288 --retry 3 --retry-delay 2 --retry-connrefused "$CENTRAL/release-manifest.json" -o "$RELEASE_MANIFEST" \
      && curl -fsSL --max-filesize 64 --retry 3 --retry-delay 2 --retry-connrefused "$CENTRAL/release-manifest.sig" -o "$RELEASE_SIGNATURE" \
      || { echo "ERRO: a central não entregou o manifesto assinado da release." >&2; exit 1; }
  fi
  validate_download_file "$RELEASE_MANIFEST" 524288 \
    && validate_download_file "$RELEASE_SIGNATURE" 64 64 \
    || { echo "ERRO: manifesto ou assinatura excede o contrato de transporte." >&2; exit 1; }
  verify_release_manifest "$RELEASE_MANIFEST" "$RELEASE_SIGNATURE" "$RELEASE_PUBLIC_KEY" "$RELEASE_METADATA" \
    || { echo "ERRO: assinatura ou contrato da release inválido." >&2; exit 1; }
  RELEASE_MANIFEST_SHA256="$(sha256sum "$RELEASE_MANIFEST" | awk '{print $1}')"
  # shellcheck disable=SC1090
  . "$RELEASE_METADATA"
  semver_ge "$version" "$minVersion" || { echo "ERRO: release abaixo da versão mínima assinada." >&2; exit 1; }
  [ "$codexCliVersion" = "$LEON_CODEX_CLI_VERSION" ] \
    || { echo "ERRO: release exige Codex CLI incompatível." >&2; exit 1; }
  [ "$nodeVersion" = "$LEON_NODE_VERSION" ] \
    || { echo "ERRO: release exige runtime Node incompatível." >&2; exit 1; }
  INSTALLED_RELEASE_IDENTITY="$(read_installed_release_identity "$LIVE_DIR")" \
    || { echo "ERRO: marcador da release instalada é inseguro ou inválido." >&2; exit 1; }
  IFS=$'\t' read -r INSTALLED_RELEASE_VERSION INSTALLED_RELEASE_DIGEST <<< "$INSTALLED_RELEASE_IDENTITY"
  release_identity_acceptable "$version" "$RELEASE_MANIFEST_SHA256" "$INSTALLED_RELEASE_VERSION" "${INSTALLED_RELEASE_DIGEST:-}" \
    || { echo "ERRO: manifesto assinado é downgrade, replay ambíguo ou equivoca a release $INSTALLED_RELEASE_VERSION." >&2; exit 1; }
  [ "$base_sha256" = "$LEON_BASE_CURATED_SHA256" ] \
    || { echo "ERRO: a release assinada não referencia o base curado esperado." >&2; exit 1; }
  TARBALL=$(mktemp --suffix=.tar.gz)
  if [ -n "$LEON_BASE_PACKAGE_FILE" ]; then
    if [ ! -f "$LEON_BASE_PACKAGE_FILE" ] || [ -L "$LEON_BASE_PACKAGE_FILE" ]; then
      echo "ERRO: LEON_BASE_PACKAGE_FILE precisa apontar para um arquivo regular." >&2
      exit 1
    fi
    cp -- "$LEON_BASE_PACKAGE_FILE" "$TARBALL"
    HTTP_CODE=200
  else
    EMAIL_ENC=$(printf %s "$EMAIL" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))")
    if ! HTTP_CODE=$(curl -sS --max-filesize "$base_bytes" --retry 3 --retry-delay 2 --retry-connrefused \
        -w "%{http_code}" -o "$TARBALL" "$CENTRAL/download-codex?email=$EMAIL_ENC"); then
      echo "ERRO: a central nao respondeu ao download. Nenhum arquivo foi trocado." >&2
      exit 1
    fi
  fi
  if [ "$HTTP_CODE" != "200" ]; then
    echo "ERRO: nao consegui validar a compra (HTTP $HTTP_CODE)." >&2
    echo "possiveis causas:" >&2
    echo "  · email diferente do que voce usou na compra (Cakto/Hubla)" >&2
    echo "  · compra ainda nao processada (aguarde 1min e tente de novo)" >&2
    echo "  · reembolso/cancelamento (licenca bloqueada)" >&2
    echo "suporte: https://wa.me/5511988890934" >&2
    exit 1
  fi
  ACTUAL_BASE_HASH=$(sha256sum "$TARBALL" | awk '{print $1}')
  if [ "$ACTUAL_BASE_HASH" != "$LEON_BASE_CURATED_SHA256" ]; then
    echo "ERRO: o pacote-base não corresponde ao artefato curado desta versão. Nada foi trocado." >&2
    exit 1
  fi
  verify_signed_artifact "$TARBALL" "$base_sha256" "$base_bytes" "pacote-base" || exit 1
  if ! python3 - "$TARBALL" <<'PY'
import posixpath, re, sys, tarfile

archive = sys.argv[1]
try:
    source = tarfile.open(archive, "r:gz")
    members = source.getmembers()
except (OSError, tarfile.TarError):
    raise SystemExit(1)
if not members or len(members) > 200000:
    raise SystemExit(1)
private_marker = re.compile(br"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----")
total = 0
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
    echo "ERRO: pacote invalido ou com caminho inseguro. Nada foi extraido." >&2
    exit 1
  fi
  echo ">> motor baixado. preparando versao isolada..."
  EXTRACT_TMP=$(mktemp -d)
  tar --no-same-owner --no-same-permissions -xzf "$TARBALL" -C "$EXTRACT_TMP"
  TOP_COUNT=$(find "$EXTRACT_TMP" -mindepth 1 -maxdepth 1 -printf x | wc -c)
  FIRST_TOP=$(find "$EXTRACT_TMP" -mindepth 1 -maxdepth 1 -print -quit)
  if [ "$TOP_COUNT" -eq 1 ] && [ -d "$FIRST_TOP" ]; then
    PACKAGE_ROOT="$FIRST_TOP"
  else
    PACKAGE_ROOT="$EXTRACT_TMP"
  fi
  if [ -z "$(find "$PACKAGE_ROOT" -mindepth 1 -print -quit)" ]; then
    echo "ERRO: pacote sem conteudo." >&2
    exit 1
  fi
  if find "$PACKAGE_ROOT" -xdev -name keys -print -quit 2>/dev/null | grep -q . \
     || find "$PACKAGE_ROOT" -xdev -name .env -print -quit 2>/dev/null | grep -q . \
     || LC_ALL=C grep -R -l --binary-files=text -E -- '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' "$PACKAGE_ROOT" >/dev/null 2>&1; then
    echo "ERRO: pacote-base contem credencial ou material de chave privada. Nada foi instalado." >&2
    exit 1
  fi
  if [ "$(basename "$PACKAGE_ROOT")" != "leon-base" ] \
     || ! validate_curated_base_manifest "$PACKAGE_ROOT"; then
    echo "ERRO: o manifesto interno do pacote-base curado não confere. Nada foi instalado." >&2
    exit 1
  fi
  cp -a "$PACKAGE_ROOT"/. "$INSTALL_DIR"/
  rm -f -- "$INSTALL_DIR/base-manifest.json"
  normalizar_agent_base "$INSTALL_DIR/AGENT-BASE.md"
  rm -rf -- "$EXTRACT_TMP"
  EXTRACT_TMP=""
  rm -f -- "$TARBALL"
  TARBALL=""

  echo ">> instalando atualizador que preserva o motor Codex..."
  UPDATE_TMP=$(mktemp)
  if [ -n "$LEON_BASE_PACKAGE_FILE" ] && [ "$MOCK_MODE" = "1" ]; then
    [ -f "$RELEASE_SOURCE_DIR/update-pago-codex.sh" ] \
      && [ ! -L "$RELEASE_SOURCE_DIR/update-pago-codex.sh" ] \
      || { echo "ERRO: fixture local não contém updater regular assinado." >&2; exit 1; }
    cp -- "$RELEASE_SOURCE_DIR/update-pago-codex.sh" "$UPDATE_TMP"
  else
    curl -fsSL --max-filesize "$updater_bytes" --retry 3 --retry-delay 2 --retry-connrefused "$CENTRAL$updater_url" -o "$UPDATE_TMP"
  fi
  if verify_signed_artifact "$UPDATE_TMP" "$updater_sha256" "$updater_bytes" "atualizador" \
     && bash -n "$UPDATE_TMP" 2>/dev/null \
     && ! grep -q -- "$DANGEROUS_FLAG" "$UPDATE_TMP" \
     && grep -q 'leon-codex-appserver-v2.tar.gz' "$UPDATE_TMP" \
     && grep -q 'verify_release_manifest' "$UPDATE_TMP"; then
    cp -f "$UPDATE_TMP" "$INSTALL_DIR/update-pago.sh"
    rm -f "$UPDATE_TMP"
  else
    rm -f "$UPDATE_TMP"
    echo "ERRO: nao consegui instalar o atualizador da versao Codex." >&2
    echo "sem ele uma atualizacao futura poderia reverter o motor. tente de novo em 1min." >&2
    exit 1
  fi
  # Atualizador e redes de seguranca precisam ser executaveis (o cron chama direto).
  chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
  chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true

  # ------------------------------------------------------------
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

# O runtime Codex v2 viaja como bundle completo. Bridge, adapter e shim precisam
# entrar juntos; trocar somente um deles pode deixar a instalacao sintaticamente
# valida e funcionalmente muda. O bundle e validado antes de tocar no stage.
echo ">> instalando runtime Codex persistente..."
BUNDLE_TMP=$(mktemp)
if [ -n "$LEON_CODEX_BUNDLE_FILE" ]; then
  if [ ! -f "$LEON_CODEX_BUNDLE_FILE" ] || [ -L "$LEON_CODEX_BUNDLE_FILE" ]; then
    echo "ERRO: LEON_CODEX_BUNDLE_FILE precisa apontar para um arquivo regular." >&2
    exit 1
  fi
  cp -- "$LEON_CODEX_BUNDLE_FILE" "$BUNDLE_TMP"
else
  if ! curl -fsSL --max-filesize "$bundle_bytes" --retry 3 --retry-delay 2 --retry-connrefused \
      "$CENTRAL$bundle_url" -o "$BUNDLE_TMP"; then
    echo "ERRO: nao consegui baixar o runtime Codex completo." >&2
    exit 1
  fi
fi
verify_signed_artifact "$BUNDLE_TMP" "$bundle_sha256" "$bundle_bytes" "runtime Codex" || exit 1

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
  exit 1
fi

BUNDLE_EXTRACT=$(mktemp -d)
tar --no-same-owner --no-same-permissions -xzf "$BUNDLE_TMP" -C "$BUNDLE_EXTRACT"
python3 - "$BUNDLE_EXTRACT/capabilities.json" <<'PY' || {
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
if d.get("schema")!=1 or d.get("kind")!="leon-codex-capabilities": raise SystemExit(1)
if d.get("attachments",{}).get("curatedOfficePreconversion") is not False: raise SystemExit(1)
if d.get("optionalNotProvisionedByCore",{}).get("googleWorkspace") is not False: raise SystemExit(1)
PY
  echo "ERRO: matriz de capacidades do runtime é inválida." >&2; exit 1;
}
for JS_FILE in bridge.cjs appserver/adapter.cjs lib/onboarding.js lib/inbound.js lib/meta-connect.js lib/meta-mcp-codex-filter.cjs lib/meta-account-guard.cjs lib-motores/codex-appserver.cjs lib-motores/claude.cjs lib-motores/index.cjs smoke/appserver-smoke.cjs workers/piper.js; do
  if ! "$NODE_BIN" --check "$BUNDLE_EXTRACT/$JS_FILE" >/dev/null 2>&1; then
    echo "ERRO: runtime Codex contem JavaScript invalido em $JS_FILE." >&2
    exit 1
  fi
done
LEGACY_NAME='open''claw'
if grep -Rqi -- "$LEGACY_NAME" "$BUNDLE_EXTRACT" \
   || grep -Rq --exclude='claude.cjs' --exclude='motor-claude.cjs' -- 'bypassPermissions' "$BUNDLE_EXTRACT" \
   || grep -Rq -- "$DANGEROUS_FLAG" "$BUNDLE_EXTRACT" \
   || { ! grep -q "^require('./leon2/leon.cjs');\$" "$BUNDLE_EXTRACT/bridge.cjs" \
        && { ! grep -q 'const LEON_CODEX_ONLY = true' "$BUNDLE_EXTRACT/bridge.cjs" || ! grep -q 'criaMotor' "$BUNDLE_EXTRACT/bridge.cjs"; }; } \
   || { grep -q "^require('./leon2/leon.cjs');\$" "$BUNDLE_EXTRACT/bridge.cjs" && ! "$NODE_BIN" --check "$BUNDLE_EXTRACT/leon2/leon.cjs" >/dev/null 2>&1; } \
   || ! [ -s "$BUNDLE_EXTRACT/lib-motores/index.cjs" ]; then
  echo "ERRO: runtime Codex reprovou a auditoria de identidade ou permissao." >&2
  exit 1
fi
cp -a "$BUNDLE_EXTRACT"/. "$INSTALL_DIR"/
chmod 0700 "$INSTALL_DIR/bridge.cjs" "$INSTALL_DIR/smoke/appserver-smoke.cjs" "$INSTALL_DIR/workers/piper.js"
chmod 0600 "$INSTALL_DIR/capabilities.json"
chmod 0600 "$INSTALL_DIR/appserver"/*.cjs "$INSTALL_DIR/appserver/package.json" "$INSTALL_DIR/lib"/*.js "$INSTALL_DIR/lib-motores"/*.cjs
rm -rf -- "$BUNDLE_EXTRACT"
BUNDLE_EXTRACT=""
rm -f -- "$BUNDLE_TMP"
BUNDLE_TMP=""
echo "   runtime app-server validado e aplicado no stage."

# O catálogo viaja como artefato independente coberto pelo mesmo manifesto
# assinado da release. Ele nasce limpo, é validado antes da normalização e só
# substitui o catálogo antigo junto com o commit do runtime.
echo ">> preparando catálogo Codex assinado..."
SKILLS_TMP=$(mktemp --suffix=.tar.gz)
if [ -n "$LEON_BASE_PACKAGE_FILE" ] && [ "$MOCK_MODE" = "1" ]; then
  SKILLS_SOURCE="$RELEASE_SOURCE_DIR/leon-skills-codex-minimal.tar.gz"
  if [ ! -f "$SKILLS_SOURCE" ] || [ -L "$SKILLS_SOURCE" ]; then
    echo "ERRO: fixture local não contém o catálogo de skills assinado." >&2
    exit 1
  fi
  cp -- "$SKILLS_SOURCE" "$SKILLS_TMP"
else
  if ! curl -fsSL --max-filesize "$skills_bytes" --retry 3 --retry-delay 2 --retry-connrefused \
      "$CENTRAL$skills_url" -o "$SKILLS_TMP"; then
    echo "ERRO: não consegui baixar o catálogo Codex assinado." >&2
    exit 1
  fi
fi
verify_signed_artifact "$SKILLS_TMP" "$skills_sha256" "$skills_bytes" "catálogo de skills" || exit 1
audit_skills_archive "$SKILLS_TMP" \
  || { echo "ERRO: catálogo de skills contém membros inseguros ou incompletos." >&2; exit 1; }
SKILLS_EXTRACT=$(mktemp -d "$LEON_DATA_DIR/.skills-extract-$TX_ID.XXXXXX")
tar --no-same-owner --no-same-permissions --delay-directory-restore \
  -xzf "$SKILLS_TMP" -C "$SKILLS_EXTRACT"
SKILLS_ROOT="$SKILLS_EXTRACT/leon-skills"
if [ ! -d "$SKILLS_ROOT" ] || [ -L "$SKILLS_ROOT" ] \
   || [ "$(find "$SKILLS_EXTRACT" -mindepth 1 -maxdepth 1 -printf x | wc -c)" -ne 1 ] \
   || ! validate_skills_manifest "$SKILLS_ROOT"; then
  echo "ERRO: manifesto interno do catálogo de skills não confere." >&2
  exit 1
fi
# O artefato chega selado (diretórios 0500). Só depois da validação exata
# abrimos temporariamente os diretórios privados do stage para normalizar os
# placeholders e remover o manifesto de origem. O catálogo volta a 0500/0400
# em normalize_skills_catalog().
find -P "$SKILLS_ROOT" -type d -exec chmod 0700 -- {} +
mv -- "$SKILLS_ROOT" "$SKILLS_STAGE"
rmdir -- "$SKILLS_EXTRACT"
SKILLS_EXTRACT=""
normalize_skills_catalog "$SKILLS_STAGE" "$LEON_SKILLS_DIR" "$LEON_WORK_AREA" \
  || { echo "ERRO: não consegui normalizar e selar o catálogo de skills." >&2; exit 1; }
SKILLS_EXPECTED_DIGEST="$(installed_skills_digest "$SKILLS_STAGE")" \
  || { echo "ERRO: catálogo de skills preparado perdeu sua integridade." >&2; exit 1; }
rm -f -- "$SKILLS_TMP"
SKILLS_TMP=""
echo "   catálogo Codex validado e selado no stage."

cd "$INSTALL_DIR"

# ------------------------------------------------------------
# 2.4 Proprietario do bot: preserva reinstalacao e evita corrida de captura
# ------------------------------------------------------------
PREV_OWNER=""
recusa_troca_de_motor "$LIVE_DIR/.env"
if [ -e "$LIVE_DIR/.env" ]; then
  PREV_ENV_SAFE="$(mktemp "$LEON_TMPDIR/leon-prev-env.XXXXXX")"
  safe_copy_state_file "$LIVE_DIR/.env" "$PREV_ENV_SAFE" env \
    || { echo "ERRO: o .env anterior não é um arquivo regular seguro; instalação preservada." >&2; exit 1; }
  PREV_OWNER="$(leon_preserva env-valor "$PREV_ENV_SAFE" OWNER_CHAT_ID 2>/dev/null || true)"
fi

if printf %s "$OWNER_CHAT_ID" | grep -qE '^-?[1-9][0-9]*$'; then
  echo ">> proprietario recebido de forma explicita: chat_id=$OWNER_CHAT_ID"
elif printf %s "$PREV_OWNER" | grep -qE '^-?[1-9][0-9]*$'; then
  OWNER_CHAT_ID="$PREV_OWNER"
  echo ">> reinstalacao detectada: proprietario preservado (chat_id=$OWNER_CHAT_ID)."
elif [ "$MOCK_MODE" = "1" ]; then
  OWNER_CHAT_ID="999999"
  echo ">> MOCK: OWNER_CHAT_ID=999999"
else
  NONCE="LEON-$(python3 -c 'import secrets; print(secrets.token_hex(3).upper())')"
  echo ""
  echo "========================================"
  echo "  ULTIMO PASSO — vincular teu Telegram"
  echo "========================================"
  echo "Abre uma conversa PRIVADA com o bot e manda exatamente: $NONCE"
  echo "Essa frase unica impede outra pessoa de capturar teu LEON."
  echo "Vou esperar por ate 60 segundos."
  echo ""

  for _ in $(seq 1 12); do
    UPDATES_FILE=$(mktemp)
    telegram_api_get_file "$BOT_TOKEN" 'getUpdates?timeout=5' "$UPDATES_FILE" 7 || printf '{}\n' > "$UPDATES_FILE"
    CHAT_ID=$(python3 -c '
import json, sys
nonce = sys.argv[1]
try:
    data = json.load(open(sys.argv[2], encoding="utf-8"))
    for update in reversed(data.get("result", [])):
        msg = update.get("message") or {}
        chat = msg.get("chat") or {}
        if chat.get("type") == "private" and str(msg.get("text", "")).strip() == nonce:
            print(chat.get("id", ""))
            break
except Exception:
pass
' "$NONCE" "$UPDATES_FILE" 2>/dev/null || true)
    rm -f -- "$UPDATES_FILE"
    if printf %s "$CHAT_ID" | grep -qE '^-?[1-9][0-9]*$'; then
      OWNER_CHAT_ID="$CHAT_ID"
      echo ">> Telegram vinculado com seguranca: chat_id=$OWNER_CHAT_ID"
      break
    fi
  done

  if ! printf %s "$OWNER_CHAT_ID" | grep -qE '^-?[1-9][0-9]*$'; then
    echo "ERRO: nao recebi a frase de vinculacao. Nada foi sobrescrito e o servico antigo continua no ar." >&2
    echo "Rode o instalador de novo e envie a frase mostrada na tela." >&2
    exit 1
  fi
fi

# ------------------------------------------------------------
# 2.5 .env do cliente, com preservacao das configuracoes existentes
# ------------------------------------------------------------
# 23/09 (desenho estrutural, igual ao /atualiza e ao install-leon.sh): o .env anterior e do
# dono. Toda linha dele sai byte a byte; so entram no FIM as chaves que faltam, com o padrao
# desta instalacao. A unica excecao e a lista PRODUTO_ENV do preserva-casa.py, com valor
# atual provado invalido aqui. Fim do filtro por allowlist (ele apagava NOTION_TOKEN, META_*,
# CAKTO_* e toda integracao que nao estivesse na lista).
# CODEX_HOME (24/09, rodada 3): so entra quando falta, e numa casa que ja existe entra a pasta
# que o bridge JA usa (homeDoMotor: ~/.codex com credencial). A pasta do LEON so vale na
# instalacao do zero: grava-la por cima trocava a casa do login e dos MCPs do dono.
ENV_OBRA="$(mktemp -d "$INSTALL_DIR/.env-obra.XXXXXX")"
cat > "$ENV_OBRA/padroes" <<EOF
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
OWNER_CHAT_ID=$OWNER_CHAT_ID
LEON_LICENSE_EMAIL=$EMAIL
LEON_LICENSE_CENTRAL=$CENTRAL
LEON_MACHINE_ID=$MACHINE_ID
AGENT_NAME=$NOME
AGENT_GENDER=$GENDER
ENGINE=codex
ENGINE_DEFAULT=codex
LEON_CODEX_ONLY=1
CODEX_APP_SERVER=1
CODEX_HOME=$(leon_preserva home-do-motor "${PREV_ENV_SAFE:-$ENV_OBRA/nao-existe}" codex "$LEON_CODEX_HOME")
CODEX_MODEL=gpt-5.6-sol
CODEX_REASONING_EFFORT=high
LEON_CODEX_CLI_VERSION=$LEON_CODEX_CLI_VERSION
LEON_DATA_DIR=$LEON_DATA_DIR
BRAIN_DIR=$BRAIN_DIR
PERSONA_DIR=$PERSONA_DIR
LEON_SKILLS_DIR=$LEON_SKILLS_DIR
LEON_SKILLS_PESSOAIS_DIR=$LEON_SKILLS_PESSOAIS_DIR
LEON_TMPDIR=$LEON_TMPDIR
LEON_WORK_AREA=$LEON_WORK_AREA
LEON_STATE_DIR=$LEON_STATE_DIR
LEON_MISSIONS_DIR=$LEON_MISSIONS_DIR
LEON_PROMISES_DIR=$LEON_PROMISES_DIR
LEON_MISSION_OUTPUT_DIR=$LEON_MISSION_OUTPUT_DIR
WORK_DIR=$LIVE_DIR
VOICE_HANDLER=$LIVE_DIR/workers/voice-handler.py
EDGE_TTS_WORKER=$LIVE_DIR/workers/edge-tts.js
EDGE_TTS_PY=$LEON_DATA_DIR/edgetts-venv/bin/python3
PIPER_WORKER=$LIVE_DIR/workers/piper.js
PIPER_BIN=$LEON_DATA_DIR/piper-venv/bin/piper
PIPER_MODEL=$LEON_DATA_DIR/voices/piper/pt_BR-faber-medium.onnx
MEMVIVA_FILE=$MEMVIVA_FILE
ASSUNTOS_FILE=$ASSUNTOS_FILE
TTS_PROVIDER=disabled
VOICE_REPLY=off
VOICE_PY=$LEON_DATA_DIR/whisper-venv/bin/python3
EOF
if [ "$MOCK_MODE" != "1" ]; then
  echo "CODEX_BIN=$LEON_CODEX_BIN_RESOLVED" >> "$ENV_OBRA/padroes"
elif [ -n "${CODEX_BIN:-}" ]; then
  echo "CODEX_BIN=$CODEX_BIN" >> "$ENV_OBRA/padroes"
fi
: > "$ENV_OBRA/trocas"
if [ -n "$PREV_ENV_SAFE" ]; then
  _prev() { leon_preserva env-valor "$PREV_ENV_SAFE" "$1" 2>/dev/null || true; }
  # id da maquina: o da casa que nao bate com MAC + hostname desta VPS e de outra maquina.
  if [ -n "$(_prev LEON_MACHINE_ID)" ] && [ "$(_prev LEON_MACHINE_ID)" != "$MACHINE_ID" ]; then
    printf 'LEON_MACHINE_ID=%s\n' "$MACHINE_ID" >> "$ENV_OBRA/trocas"
  fi
  # token do bot: so quando o Telegram recusa o da casa (o informado agora ja passou no getMe).
  if [ "$MOCK_MODE" != "1" ] && [ -n "$(_prev TELEGRAM_BOT_TOKEN)" ] && [ "$(_prev TELEGRAM_BOT_TOKEN)" != "$BOT_TOKEN" ]; then
    _tg="$(mktemp)"
    if ! telegram_api_get_file "$(_prev TELEGRAM_BOT_TOKEN)" getMe "$_tg" 15 >/dev/null 2>&1 || ! grep -q '"ok":true' "$_tg"; then
      printf 'TELEGRAM_BOT_TOKEN=%s\n' "$BOT_TOKEN" >> "$ENV_OBRA/trocas"
    else
      echo ">> o bot desta casa continua valido no Telegram: mantive o token dela."
    fi
    rm -f -- "$_tg"
  fi
  # Codex CLI: so quando o binario que a casa aponta nao executa.
  if [ "$MOCK_MODE" != "1" ] && [ -n "$(_prev CODEX_BIN)" ] && [ ! -x "$(_prev CODEX_BIN)" ]; then
    printf 'CODEX_BIN=%s\nLEON_CODEX_CLI_VERSION=%s\n' "$LEON_CODEX_BIN_RESOLVED" "$LEON_CODEX_CLI_VERSION" >> "$ENV_OBRA/trocas"
  fi
fi
_ENV_RC=0
leon_preserva env-acrescenta "${PREV_ENV_SAFE:-$ENV_OBRA/nao-existe}" "$ENV_OBRA/padroes" "$ENV_OBRA/trocas" "$ENV_OBRA/saida" "$ENV_OBRA/relatorio" "$LEON_DATA_DIR" || _ENV_RC=$?
if [ "$_ENV_RC" -ne 0 ]; then
  echo "ERRO: o .env desta casa tem linha que o LEON recusaria: $(sed -n 's/^recusa //p' "$ENV_OBRA/relatorio" 2>/dev/null | tr '\n' ' ')" >&2
  echo "Nada foi trocado: o .env e teu e eu nao reescrevo linha tua. Corrija essa linha e rode o instalador de novo." >&2
  rm -rf -- "$ENV_OBRA"
  exit 1
fi
if [ -n "$PREV_ENV_SAFE" ]; then
  echo ">> .env: nenhuma linha que ja existia foi mudada."
  grep -q '^nova ' "$ENV_OBRA/relatorio" && echo "   acrescentadas no fim (faltavam): $(sed -n 's/^nova //p' "$ENV_OBRA/relatorio" | tr '\n' ' ')"
  grep -q '^religada ' "$ENV_OBRA/relatorio" && echo "   voltaram a valer (uma versao antiga tinha comentado): $(sed -n 's/^religada //p' "$ENV_OBRA/relatorio" | tr '\n' ' ')"
  grep -q '^binario-do-dono ' "$ENV_OBRA/relatorio" && echo "   CODEX_BIN aponta pra binario teu, fora da pasta do produto: mantive."
  grep -q '^trocada ' "$ENV_OBRA/relatorio" && echo "   chaves do produto com valor invalido, corrigidas: $(sed -n 's/^trocada //p' "$ENV_OBRA/relatorio" | tr '\n' ' ')"
  grep -q '^escolha-do-dono ' "$ENV_OBRA/relatorio" && echo "   mantive a tua escolha (a instalacao sugeria outro valor): $(sed -n 's/^escolha-do-dono //p' "$ENV_OBRA/relatorio" | tr '\n' ' ')"
fi
chmod 600 "$ENV_OBRA/saida"
mv -f -- "$ENV_OBRA/saida" .env
rm -rf -- "$ENV_OBRA"

cat > .pacote.json <<EOF
{
  "modo": "pago",
  "instalador": "https://licenca.leonardomolina.com.br/instalacao-codex",
  "usuario": "$USER",
  "servico": "leon-agente.service"
}
EOF
chmod 600 .pacote.json

# O marcador viaja com o runtime protegido. Reinstalações e updates com um
# manifesto antigo são recusados antes de qualquer commit, inclusive quando a
# assinatura do manifesto antigo ainda é válida.
RELEASE_VERSION_ACCEPTED="${version:-0.0.0}"
printf '%s\n' "$RELEASE_VERSION_ACCEPTED" > .leon-release-version
chmod 0600 .leon-release-version
write_release_identity .leon-release.json "$RELEASE_VERSION_ACCEPTED" "$RELEASE_MANIFEST_SHA256"
write_runtime_files_manifest .

# ------------------------------------------------------------
# 2.5b Marca a sala principal como Codex tambem no topics.json.
# E cinto e suspensorio de proposito: o motor aceita OS DOIS caminhos (a linha
# ENGINE=codex do .env vale pra maquina inteira, a marca aqui vale pra sala).
# Os dois foram ensinados ao motor em 04/08 — antes disso so o topics.json valia.
# NAO sobrescreve um topics.json que ja exista — reinstalar nao pode apagar as
# salas que o dono criou depois.
# ------------------------------------------------------------
if [ ! -f topics.json ]; then
  cat > topics.json <<'TOPICS'
{
  "general": {
    "engine": "codex",
    "persona": "main.md",
    "label": "Geral",
    "effort": "high"
  }
}
TOPICS
else
  echo ">> topics.json ja existia, mantive como esta (o ENGINE=codex do .env ja manda em tudo)."
fi

# ------------------------------------------------------------
# 2.6 Ativa licenca no central
# ------------------------------------------------------------
if [ "$MOCK_MODE" != "1" ]; then
  echo ""
  echo ">> ativando licenca..."
  ACTIVATE_BODY=$(python3 - "$EMAIL" "$MACHINE_ID" <<'PY'
import json, sys
print(json.dumps({"email": sys.argv[1], "machine_id": sys.argv[2]}, separators=(",", ":")))
PY
)
  if ! RESP=$(curl -fsS --retry 3 --retry-delay 2 --retry-connrefused \
      -X POST "$CENTRAL/activate" -H "Content-Type: application/json" \
      --data-binary "$ACTIVATE_BODY"); then
    echo "ERRO: a central nao respondeu durante a ativacao." >&2
    exit 1
  fi
  if ! printf %s "$RESP" | python3 -c '
import json, sys
try:
    ok = json.load(sys.stdin).get("ok") is True
except Exception:
    ok = False
raise SystemExit(0 if ok else 1)
'; then
    echo "ERRO: ativacao no central falhou. Nao vou reiniciar o servico com uma instalacao sem licenca valida." >&2
    echo "Se for machine_mismatch, essa chave ja foi ativada em outra VPS." >&2
    echo "Suporte: https://wa.me/5511988890934" >&2
    exit 1
  fi
  # A chave da licenca vem NA RESPOSTA do /activate (campo "key"). Ate a 2.4.48 ela era
  # descartada, e o .env do cliente saia sem LEON_LICENSE_KEY: o gate KEY_PRESENT do
  # bridge nunca ligava e a frota inteira rodava sem ativacao nem heartbeat de licenca.
  # Gravamos aqui, DEPOIS do ok, no mesmo .env ja escrito na 2.5. O cliente nao digita
  # nada a mais: a chave e a que a central ja tem no cadastro do email dele.
  LICENSE_KEY=$(printf %s "$RESP" | python3 -c '
import json, re, sys
try:
    key = str(json.load(sys.stdin).get("key") or "").strip()
except Exception:
    key = ""
print(key if re.fullmatch(r"[A-Za-z0-9_-]{8,128}", key) else "")
')
  if [ -n "$LICENSE_KEY" ]; then
    # 23/09: a central e a fonte da chave. Chave da casa que falta, esta malformada ou difere
    # da devolvida e invalida (lista PRODUTO_ENV); todo o resto do .env sai byte a byte.
    _LIC_OBRA="$(mktemp -d "$INSTALL_DIR/.env-obra.XXXXXX")"
    : > "$_LIC_OBRA/padroes"
    printf 'LEON_LICENSE_KEY=%s\n' "$LICENSE_KEY" > "$_LIC_OBRA/trocas"
    leon_preserva env-acrescenta .env "$_LIC_OBRA/padroes" "$_LIC_OBRA/trocas" "$_LIC_OBRA/saida" "$_LIC_OBRA/rel" "$LEON_DATA_DIR" \
      && chmod 600 "$_LIC_OBRA/saida" && mv -f -- "$_LIC_OBRA/saida" .env
    rm -rf -- "$_LIC_OBRA"
    chmod 600 .env
    echo ">> licenca ativa e chave gravada no .env."
  else
    echo "ATENCAO: a central ativou mas nao devolveu a chave da licenca." >&2
    echo "O agente sobe e funciona, porem sem LEON_LICENSE_KEY no .env o controle de" >&2
    echo "licenca do proprio agente fica desligado (so o email identifica esta casa)." >&2
    echo "Peca a chave no suporte e acrescente a linha LEON_LICENSE_KEY=<chave> em" >&2
    echo "$INSTALL_DIR/.env, depois reinicie o servico." >&2
  fi
fi

# O runtime de release usa apenas módulos nativos do Node. Dependência dinâmica
# em package.json é recusada pelo manifesto curado e nunca executa npm install.

# O perfil so vira ativo depois que o pacote, a licenca e as dependencias
# passaram. Se qualquer smoke falhar, o trap restaura o perfil anterior.
# 23/09 (desenho estrutural, igual ao /atualiza): CODEX_HOME do dono (o .env da casa aponta
# pra fora de <LEON_DATA_DIR>/codex) nao recebe config nenhum. No CODEX_HOME do LEON o texto
# do dono e a base e o molde so acrescenta o que falta (leon_preserva toml-funde); a unica
# excecao e a lista de seguranca do preserva-casa.py.
# 24/09 (rodada 2): a mesma fonte do install-leon.sh e do /atualiza, que tambem reconhece a
# pasta do LEON por link e o config.toml por link pro ~/.codex do dono.
if _CODEX_HOME_CASA="$(leon_preserva codex-home-do-dono .env "$LEON_DATA_DIR" 2>/dev/null)"; then
  echo "   config.toml: o CODEX_HOME desta casa e do dono ($_CODEX_HOME_CASA); nao escrevo config.toml nenhum."
  rm -f -- "$CONFIG_CANDIDATE"
else
  if [ -f "$LEON_CODEX_HOME/config.toml" ]; then
    cp -p -- "$LEON_CODEX_HOME/config.toml" "$CONFIG_BACKUP"
    CONFIG_HAD_ORIGINAL=1
  fi
  _CFG_RC=0
  # Saida 2 so quando o leitor TOML do python E o Codex pinado recusam o config do dono.
  LEON_PRESERVA_CODEX="${LEON_CODEX_BIN_RESOLVED:-}" \
  LEON_PRESERVA_PATH="$(dirname "${NODE_BIN:-/usr/bin/node}"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    leon_preserva toml-funde "$LEON_CODEX_HOME/config.toml" "$CONFIG_CANDIDATE" "$CONFIG_CANDIDATE.fundido" "$CONFIG_CANDIDATE.rel" "$LIVE_DIR" || _CFG_RC=$?
  case "$_CFG_RC" in
    0)
      mv -f -- "$CONFIG_CANDIDATE.fundido" "$LEON_CODEX_HOME/config.toml"
      echo "   config.toml: nada teu mudou.$(grep -q '^acrescentada ' "$CONFIG_CANDIDATE.rel" && printf ' Acrescentei do molde: %s' "$(sed -n 's/^acrescentada //p' "$CONFIG_CANDIDATE.rel" | tr '\n' ' ')")"
      CONFIG_APPLIED=1 ;;
    2)
      [ "$CONFIG_HAD_ORIGINAL" -eq 1 ] && cp -p -- "$CONFIG_BACKUP" "$LEON_CODEX_HOME/config.toml.ilegivel-$TX_ID"
      mv -f -- "$CONFIG_CANDIDATE" "$LEON_CODEX_HOME/config.toml"
      echo "   config.toml anterior ilegivel: gravei o molde; o teu esta em config.toml.ilegivel-$TX_ID."
      CONFIG_APPLIED=1 ;;
    *)
      echo "   config.toml: mantido INTACTO ($(head -1 "$CONFIG_CANDIDATE.rel" 2>/dev/null)); o LEON segue pelos parametros do app-server." ;;
  esac
  rm -f -- "$CONFIG_CANDIDATE" "$CONFIG_CANDIDATE.fundido" "$CONFIG_CANDIDATE.rel"
  [ ! -f "$LEON_CODEX_HOME/config.toml" ] || chmod 600 "$LEON_CODEX_HOME/config.toml"
fi
if [ "$MOCK_MODE" = "1" ] && [ "$LEON_TEST_FAIL_AT" = "after_config" ]; then
  echo "MOCK: falha injetada depois da troca temporaria do perfil." >&2
  exit 97
fi

if [ "$MOCK_MODE" != "1" ]; then
  echo ">> validando motor..."
  "$NODE_BIN" --check "$INSTALL_DIR/bridge.cjs"
  # 23/09: o teste "codex sandbox -P leon" (escrita protegida) saiu junto com o perfil de
  # permissoes do molde. Decisao do dono 04/09: acesso total como o mestre, sem perfil nomeado
  # (o perfil religava o isolamento e caia em "bwrap uid map denied"); e o mesmo molde do
  # atualizador. O smoke abaixo prova o motor.

  if [ "$CODEX_AUTENTICADO" = "login" ]; then
    echo ">> testando duas voltas reais na mesma sessao persistente..."
    SMOKE_OUT="$(mktemp)"
    SMOKE_DIR="$LEON_WORK_AREA/.leon-appserver-smoke-$TX_ID"
    if ! CODEX_HOME="$LEON_CODEX_HOME_MOTOR" \
        LEON_CODEX_HOME="$LEON_CODEX_HOME_MOTOR" \
        CODEX_MODEL="gpt-5.6-sol" \
        LEON_RUNTIME_DIR="$INSTALL_DIR" \
        LEON_SMOKE_DIR="$SMOKE_DIR" \
        "$NODE_BIN" "$INSTALL_DIR/smoke/appserver-smoke.cjs" >"$SMOKE_OUT" 2>&1; then
      echo "ERRO: o login existe, mas o app-server nao concluiu o teste persistente." >&2
      tail -n 8 "$SMOKE_OUT" | sed -E 's/[A-Za-z0-9_-]{32,}/<redacted>/g' >&2
      rm -f -- "$SMOKE_OUT"
      SMOKE_OUT=""
      exit 1
    fi
    if ! grep -q '"persistentSession":true' "$SMOKE_OUT"; then
      echo "ERRO: o smoke terminou sem provar a retomada da mesma sessao." >&2
      rm -f -- "$SMOKE_OUT"
      SMOKE_OUT=""
      exit 1
    fi
    rm -f -- "$SMOKE_OUT"
    SMOKE_OUT=""
    rm -rf -- "$SMOKE_DIR"
    SMOKE_DIR=""
    echo "   app-server respondeu e retomou a thread corretamente."
  fi
fi

# ------------------------------------------------------------
# 2.8 Commit atomico dos arquivos. A fase root ainda precisa trocar a unit,
# reiniciar, observar estabilidade e validar o bot. Ate este ponto o processo
# antigo continuou atendendo com o diretorio anterior.
# ------------------------------------------------------------
LIVE_MOVED=0
if [ "$MOCK_MODE" != "1" ] && [ "$LEON_ROOT_ORCHESTRATED" = "1" ]; then
  case "$LEON_TX_READY:$LEON_TX_GO:$LEON_TX_ABORT" in
    "$LEON_DATA_DIR"/*:"$LEON_DATA_DIR"/*:"$LEON_DATA_DIR"/*) ;;
    *) echo "ERRO: canal de commit root/user inválido." >&2; exit 1 ;;
  esac
  : > "$LEON_TX_READY"
  COMMIT_WAIT=0
  while [ ! -f "$LEON_TX_GO" ]; do
    [ ! -f "$LEON_TX_ABORT" ] || { echo "ERRO: coordenador root recusou o commit." >&2; exit 1; }
    COMMIT_WAIT=$((COMMIT_WAIT + 1))
    [ "$COMMIT_WAIT" -lt 3000 ] || { echo "ERRO: timeout aguardando autorização root do commit." >&2; exit 1; }
    sleep 0.2
  done
fi

if [ -d "$LIVE_DIR" ]; then
  [ ! -e "$LIVE_DIR/sessions.json" ] || safe_copy_state_file "$LIVE_DIR/sessions.json" "$DEPLOY_STAGE/sessions.json" sessions \
    || { echo "ERRO: sessions.json antigo é inseguro; runtime preservado." >&2; exit 1; }
  [ ! -e "$LIVE_DIR/topics.json" ] || safe_copy_state_file "$LIVE_DIR/topics.json" "$DEPLOY_STAGE/topics.json" topics \
    || { echo "ERRO: topics.json antigo é inseguro; runtime preservado." >&2; exit 1; }
  # 23/09: o estado de integracao e de jornada do dono viaja igual ao /atualiza (antes ficava
  # so no backup e a casa acordava sem a conexao Meta e com o dono tratado como novo).
  for _estado in .meta-token.json:meta .meta-connect.json:meta .onboarding-state.json:onboarding; do
    [ ! -e "$LIVE_DIR/${_estado%%:*}" ] || safe_copy_state_file "$LIVE_DIR/${_estado%%:*}" "$DEPLOY_STAGE/${_estado%%:*}" "${_estado##*:}" \
      || { echo "ERRO: ${_estado%%:*} antigo é inseguro; runtime preservado." >&2; exit 1; }
  done
fi

# ARQUIVOS DO DONO (30/09, perdeu-275): a troca de pastas levava so a lista fechada de estado e o resto
# do dono (rotinas, scripts, logs, .meta-account-policy.json) ficava preso no backup. Agora o que a casa
# tem e o pacote nao traz entra no stage SEM sobrescrever nada (casa e produto vencem), como a reinstala
# (install-leon.sh cp -a por cima). Troca aceita: extras da casa velha atravessam (bridge.cjs so confere
# o manifesto; nada carrega workers ou lib por listagem; node_modules da casa atravessa e o npm do pg nao
# roda). Nao seguem symlink; socket e fifo ficam. Erro de escrita sai 1; sem espaco (ENOSPC) sai 3.
funde_casa() {  # funde_casa <origem> <stage> [caminho relativo que fica de fora...]: imprime quantos entraram
  "${PYTHON_BIN:-python3}" - "$@" <<'LEON_FUNDE_PY'
import errno, os, shutil, stat, sys
src, dst, pula = sys.argv[1], sys.argv[2], set(sys.argv[3:])
raiz, novas, n = os.geteuid() == 0, [], 0
def sai(e): sys.stderr.write('funde_casa: %s\n' % e); sys.exit(3 if e.errno in (errno.ENOSPC, errno.EDQUOT) else 1)
for d, subs, arqs in os.walk(src):
    rel = os.path.relpath(d, src); alvo = os.path.normpath(os.path.join(dst, rel)); m = os.lstat(alvo).st_mode
    if not stat.S_ISDIR(m): subs[:] = []; continue
    desce = []
    for nome in subs + arqs:
        r, s, t = os.path.normpath(os.path.join(rel, nome)), os.path.join(d, nome), os.path.join(alvo, nome)
        try: st = os.lstat(s)
        except FileNotFoundError: continue
        eh_dir = stat.S_ISDIR(st.st_mode)
        if r in pula or (os.path.lexists(t) and not eh_dir): continue
        if not (eh_dir or stat.S_ISLNK(st.st_mode) or stat.S_ISREG(st.st_mode) and os.access(s, os.R_OK)): continue
        try:
            if eh_dir:
                if not os.path.lexists(t): os.mkdir(t, 0o700); novas.append((t, st))
                desce.append(nome); continue
            os.symlink(os.readlink(s), t) if stat.S_ISLNK(st.st_mode) else shutil.copy2(s, t)
            if raiz: os.lchown(t, st.st_uid, st.st_gid)
        except OSError as e:
            if os.path.lexists(t) and not eh_dir: os.unlink(t)
            if os.path.lexists(s): sai(e)
            continue
        n += 1
    subs[:] = desce
for t, st in reversed(novas):
    if raiz: os.chown(t, st.st_uid, st.st_gid)
    os.chmod(t, stat.S_IMODE(st.st_mode))
print(n)
LEON_FUNDE_PY
}
# o que o produto tira de proposito, marcadores de passagem e o produto que saiu da 2.6.8 pra 2.7.x
LEON_FORA_DA_FUSAO=(NUCLEO-LEON.md _MOTOR-CLAUDE.md _MOTOR-CODEX.md _REGRAS-DURAS.md CAMINHOS-CANONICOS.md base-manifest.json
  .bridge.lock .leon-admission-closed .update-pending.json .update-request.json lib/imagem.cjs)
if [ -d "$LIVE_DIR" ]; then
  funde_casa "$LIVE_DIR" "$DEPLOY_STAGE" "${LEON_FORA_DA_FUSAO[@]}" >/dev/null \
    || { echo "ERRO: não consegui levar os arquivos da casa pra versão nova; runtime preservado." >&2; exit 1; }
fi

if [ -e "$LEON_SKILLS_DIR" ]; then
  if [ ! -d "$LEON_SKILLS_DIR" ] || [ -L "$LEON_SKILLS_DIR" ]; then
    echo "ERRO: o catálogo anterior não é um diretório real; commit recusado." >&2
    exit 1
  fi
  mv -- "$LEON_SKILLS_DIR" "$SKILLS_BACKUP"
  SKILLS_HAD_ORIGINAL=1
fi
if ! mv -- "$SKILLS_STAGE" "$LEON_SKILLS_DIR"; then
  [ "$SKILLS_HAD_ORIGINAL" -eq 0 ] || mv -- "$SKILLS_BACKUP" "$LEON_SKILLS_DIR" 2>/dev/null || true
  echo "ERRO: não consegui ativar o catálogo Codex; runtime preservado." >&2
  exit 1
fi
SKILLS_SWAPPED=1
if [ "$(installed_skills_digest "$LEON_SKILLS_DIR")" != "$SKILLS_EXPECTED_DIGEST" ]; then
  echo "ERRO: o catálogo Codex mudou durante o commit; restaurando versão anterior." >&2
  exit 1
fi
if [ "$MOCK_MODE" = "1" ] && [ "$LEON_TEST_FAIL_AT" = "after_skills" ]; then
  echo "MOCK: falha injetada após troca de skills." >&2
  exit 97
fi

if [ -d "$LIVE_DIR" ]; then
  if ! mv -- "$LIVE_DIR" "$DEPLOY_BACKUP"; then
    echo "ERRO: nao consegui reservar o backup da versao atual." >&2
    exit 1
  fi
  LIVE_MOVED=1
fi
if [ "$MOCK_MODE" = "1" ] && [ "$LEON_TEST_FAIL_AT" = "before_new_live" ]; then
  echo "MOCK: falha injetada entre os renames; restaurando versao anterior." >&2
  if [ "$LIVE_MOVED" -eq 1 ]; then mv -- "$DEPLOY_BACKUP" "$LIVE_DIR" || true; fi
  exit 98
fi
if ! mv -- "$DEPLOY_STAGE" "$LIVE_DIR"; then
  echo "ERRO: commit do novo motor falhou; restaurando arquivos anteriores." >&2
  if [ "$LIVE_MOVED" -eq 1 ]; then mv -- "$DEPLOY_BACKUP" "$LIVE_DIR" || true; fi
  exit 1
fi
DEPLOY_COMMITTED=1
INSTALL_DIR="$LIVE_DIR"

echo ""
echo "========================================"
echo "  PACOTE VALIDADO · COMMIT CONCLUIDO"
echo "========================================"
echo "Arquivos prontos em: $LIVE_DIR"
if [ -d "$DEPLOY_BACKUP" ]; then
  echo "Backup recuperavel em: $DEPLOY_BACKUP"
fi

if [ "$LEON_ROOT_ORCHESTRATED" = "1" ]; then
  echo "Entregando ao processo root para validar o servico..."
  exit 0
fi

if [ "$MOCK_MODE" = "1" ] && [ "$LEON_FORCE_USER_PHASE" = "1" ]; then
  echo "MOCK transacional concluido sem tocar no systemd."
  exit 0
fi

echo "ERRO: a fase final precisa ser executada pelo instalador iniciado como root." >&2
exit 1
