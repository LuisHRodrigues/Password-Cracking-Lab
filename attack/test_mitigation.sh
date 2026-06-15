#!/bin/bash
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

echo -e "${YELLOW}[*] Tentando força bruta contra o servidor SEGURO (porta ${TARGET_PORT})...${NC}"
echo ""

# ------------------------------------------------------------------
# Teste manual: 6 tentativas seguidas para acionar rate limit
# O servidor bloqueia após 5 tentativas (HTTP 429)
# ------------------------------------------------------------------
echo -e "${YELLOW}[*] Enviando 6 tentativas de login com senha errada...${NC}"

for i in $(seq 1 6); do
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://${TARGET_HOST}:${TARGET_PORT}/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"admin\",\"password\":\"senhaerrada${i}\"}")

  if [ "$RESPONSE" = "429" ]; then
    echo -e "${GREEN}[+] Tentativa $i: HTTP 429 — BLOQUEADO pelo rate limiting!${NC}"
  elif [ "$RESPONSE" = "401" ]; then
    echo -e "${RED}[-] Tentativa $i: HTTP 401 — Credenciais inválidas (ainda não bloqueado)${NC}"
  elif [ "$RESPONSE" = "403" ]; then
    echo -e "${RED}[-] Tentativa $i: HTTP 403 — Conta bloqueada por tentativas excessivas${NC}"
  else
    echo -e "${YELLOW}[!] Tentativa $i: HTTP $RESPONSE${NC}"
  fi

  sleep 0.3
done

echo ""
echo -e "${YELLOW}[*] Tentando Hydra contra servidor seguro...${NC}"
echo -e "${CYAN}    (rate limit já esgotado — todas as tentativas devem retornar 429)${NC}"
echo ""

# Hydra contra servidor seguro
# O rate limit já foi esgotado pelos testes manuais acima.
# O Hydra vai receber 429 em todas as tentativas, demonstrando a proteção.
# Flags:
#   -s  porta correta (3001)
#   -t 1  thread única para não saturar
#   -w 1  timeout de resposta
# Condição: S=Login realizado com sucesso — string de SUCESSO (só presente no login real)
#   Com isso, respostas 401 e 429 são corretamente marcadas como falha.
#   F= (string de falha) seria errado aqui: a resposta 429 tem corpo diferente
#   de 401, causando falsos positivos quando o rate limit está ativo.
timeout 20 hydra \
  -L "$USERS_FILE" \
  -P "$WORDLIST" \
  -s "${TARGET_PORT}" \
  -t 1 \
  -w 1 \
  "${TARGET_HOST}" \
  http-post-form \
  "/login:username=^USER^&password=^PASS^:S=Login realizado com sucesso" \
  2>&1 | head -25

echo ""
echo -e "${GREEN}[+] Demonstração concluída.${NC}"
echo -e "${CYAN}    O servidor seguro bloqueou o ataque via rate limiting.${NC}"
echo -e "${CYAN}    Mesmo sem bloqueio, bcrypt custo 12 tornaria brute force inviável.${NC}"
