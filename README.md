# Password Cracking Lab — Tema 04

Ambiente vulnerável para demonstração de ataques de **força bruta** e **quebra de hashes**,
com posterior aplicação das mitigações obrigatórias.

---

## Estrutura do Projeto

```
password-cracking/
├── docker-compose.yml          # Sobe os dois ambientes de uma vez
├── vulnerable/                 # App SEM proteções (porta 3000)
│   ├── server.js               # Express + MD5 sem salt, sem rate limit, sem MFA
│   ├── package.json
│   ├── Dockerfile
│   └── public/index.html       # Interface de login vulnerável
├── secure/                     # App COM mitigações (porta 3001)
│   ├── server.js               # Express + bcrypt + rate limit + MFA + bloqueio
│   ├── package.json
│   ├── Dockerfile
│   └── public/index.html       # Interface de login segura
└── attack/
    ├── wordlist.txt             # Senhas comuns para força bruta
    ├── attack.sh                # Demonstração do ataque (Hydra + John)
    └── test_mitigation.sh       # Demonstra o ataque falhando no servidor seguro
```

---

## Pré-requisitos

- Docker Desktop instalado e rodando
- Kali Linux (ou Ubuntu com Hydra e John instalados)
- Terminal com Bash

---

## Passo 1 — Subir os dois ambientes

```bash
cd password-cracking
docker compose up --build -d
```

Verifique:
- http://localhost:3000 → sistema **vulnerável**
- http://localhost:3001 → sistema **seguro**

---

## Passo 2 — Demonstrar o ataque (servidor vulnerável)

```bash
cd attack
chmod +x attack.sh
bash attack.sh
```

O script executa:
1. **Hydra** (força bruta HTTP POST) contra `localhost:3000`
2. Coleta hashes MD5 expostos em `/debug/hashes`
3. **John the Ripper** quebra os hashes com a wordlist

Usuários e senhas que serão descobertos:

| Usuário | Senha      |
|---------|------------|
| admin   | admin123   |
| joao    | 123456     |
| maria   | password   |
| carlos  | qwerty     |
| ana     | letmein    |

---

## Passo 3 — Demonstrar a mitigação (servidor seguro)

```bash
chmod +x test_mitigation.sh
bash test_mitigation.sh
```

O ataque falha porque:
- Rate limit bloqueia o IP após 5 tentativas (HTTP 429)
- Hydra não consegue completar a wordlist
- MFA impede login mesmo com senha correta
- bcrypt torna a quebra offline inviável em tempo hábil

---

## Vulnerabilidades do sistema vulnerável

| Problema            | Detalhe                                              |
|---------------------|------------------------------------------------------|
| Hash fraco          | MD5 sem salt — quebrável em segundos com wordlist    |
| Sem rate limiting   | Força bruta ilimitada via HTTP                       |
| Sem MFA             | Senha única dá acesso total                          |
| Enumeração          | Mensagens de erro distintas para usuário/senha errada|
| Debug exposto       | `/debug/hashes` devolve todos os hashes do banco     |

---

## Mitigações implementadas no sistema seguro

| Mitigação           | Implementação                                        |
|---------------------|------------------------------------------------------|
| bcrypt custo 12     | `bcrypt.hash(password, 12)` — resistente a GPU       |
| Rate limiting       | 5 req/IP em 15 min via `express-rate-limit`          |
| Bloqueio de conta   | 5 erros = conta bloqueada por 10 min no banco        |
| MFA obrigatório     | Token de 6 dígitos exigido após senha correta        |
| Resposta genérica   | Mesmo erro para usuário inexistente e senha errada   |
| Debug removido      | Endpoint `/debug/hashes` retorna 403                 |

---

## Comandos manuais úteis

```bash
# Testar login manualmente no servidor vulnerável
curl -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'

# Ver hashes expostos (servidor vulnerável)
curl http://localhost:3000/debug/hashes

# Testar rate limit (servidor seguro) — execute 6 vezes seguidas
curl -X POST http://localhost:3001/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"errada"}'

# Derrubar os containers
docker compose down
```

---

## Ferramentas utilizadas

- **Hydra** — força bruta de login HTTP
- **John the Ripper** — quebra de hashes offline
- **Docker** — containerização dos dois ambientes
- **Node.js / Express** — servidor web dos dois sistemas
- **bcrypt** — algoritmo de hash seguro (sistema corrigido)
