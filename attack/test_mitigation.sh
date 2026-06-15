
TARGET_HOST="127.0.0.1"
TARGET_PORT="3001"
WORDLIST="./wordlist.txt"
USERS_FILE="./users.txt"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║      TESTE DE MITIGAÇÃO - SERVIDOR SEGURO    ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}[*] Tentando força bruta contra o servidor SEGURO (porta 3001)...${NC}"
echo ""

# ------------------------------------------------------------------
# Teste manual: 6 tentativas seguidas para acionar rate limit
# ------------------------------------------------------------------
echo -e "${YELLOW}[*] Enviando 6 tentativas de login com senha errada...${NC}"

for i in $(seq 1 6); do
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://${TARGET_HOST}:${TARGET_PORT}/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"senhaerrada'$i'"}')

  if [ "$RESPONSE" == "429" ]; then
    echo -e "${GREEN}[+] Tentativa $i: HTTP 429 — BLOQUEADO pelo rate limiting!${NC}"
  elif [ "$RESPONSE" == "401" ]; then
    echo -e "${RED}[-] Tentativa $i: HTTP 401 — Credenciais inválidas (ainda não bloqueado)${NC}"
  else
    echo -e "${YELLOW}[!] Tentativa $i: HTTP $RESPONSE${NC}"
  fi

  sleep 0.3
done

echo ""
echo -e "${YELLOW}[*] Tentando Hydra contra servidor seguro...${NC}"
echo -e "${CYAN}    (deve ser bloqueado rapidamente pelo rate limit)${NC}"
echo ""

# Hydra contra servidor seguro - deve travar após poucas tentativas
timeout 20 hydra \
  -L "$USERS_FILE" \
  -P "$WORDLIST" \
  -t 1 \
  -w 1 \
  "${TARGET_HOST}" \
  http-post-form \
  "/login:username=^USER^&password=^PASS^:Credenciais inválidas:H=Content-Type: application/x-www-form-urlencoded" \
  2>&1 | head -20