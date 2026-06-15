# Password Cracking Lab

Laboratório de segurança desenvolvido como projeto acadêmico para demonstrar na prática as vulnerabilidades de sistemas com autenticação fraca. O ambiente replica falhas reais de Password Cracking e demonstra como cada uma é explorada e corrigida.

---

## Estrutura do Projeto

```
password-cracking/
├── docker-compose.yml
├── vulnerable/                 # Servidor SEM proteções (porta 3000)
│   ├── server.js
│   ├── package.json
│   ├── Dockerfile
│   └── public/index.html
├── secure/                     # Servidor COM mitigações (porta 3001)
│   ├── server.js
│   ├── package.json
│   ├── Dockerfile
│   └── public/index.html
└── attack/
    ├── wordlist.txt
    ├── attack.sh               # Executa o ataque com Hydra e John the Ripper
    └── test_mitigation.sh      # Demonstra o ataque falhando no servidor seguro
```

---

## Pré-requisitos

- Docker Desktop instalado e rodando
- Kali Linux (Hydra e John the Ripper já vêm instalados)
- Terminal com Bash

---

## Como executar

**Passo 1: subir os dois ambientes**

```bash
cd password-cracking
docker compose up --build -d
```

Após o build, os servidores estarão disponíveis em:

- `http://localhost:3000` — sistema vulnerável
- `http://localhost:3001` — sistema seguro

**Passo 2: demonstrar o ataque**

```bash
cd attack
chmod +x attack.sh
bash attack.sh
```

O script executa o Hydra para força bruta via HTTP POST e em seguida usa o John the Ripper para quebrar os hashes MD5 coletados do endpoint `/debug/hashes`.

**Passo 3: demonstrar a mitigação**

```bash
chmod +x test_mitigation.sh
bash test_mitigation.sh
```

O mesmo ataque é direcionado ao servidor seguro (porta 3001) e é bloqueado pelo rate limiting após 5 tentativas.

---

## Falhas do sistema vulnerável

### 1. Hashing fraco com MD5 sem salt

As senhas são armazenadas como hashes MD5 puros, sem nenhum valor aleatório (salt) misturado antes do hash ser gerado. MD5 é um algoritmo projetado para ser rápido, o que permite que uma GPU moderna teste bilhões de combinações por segundo. Além disso, dois usuários com a mesma senha terão hashes idênticos no banco, facilitando ataques de tabela arco-íris.

```js
// vulnerable/server.js
function weakHash(password) {
  return crypto.createHash("md5").update(password).digest("hex");
}
```

### 2. Sem rate limiting na rota de login

A rota `/login` não possui nenhum middleware de proteção. Qualquer cliente pode enviar requisições ilimitadas sem ser bloqueado, o que permite que ferramentas como o Hydra testem toda uma wordlist livremente.

```js
// vulnerable/server.js
app.post("/login", (req, res) => {
  // sem nenhuma verificação de limite de tentativas
});
```

### 3. Sem bloqueio de conta por tentativas falhas

O banco de dados não possui colunas para registrar tentativas falhas ou períodos de bloqueio. Não existe nenhuma lógica que impeça um atacante de tentar infinitas combinações para um mesmo usuário.

```js
// vulnerable/server.js — tabela sem colunas de proteção
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    email TEXT,
    role TEXT DEFAULT 'user'
  )
`);
```

### 4. Mensagens de erro que revelam usuários válidos

Quando o login falha, o servidor retorna mensagens diferentes dependendo do motivo. Isso permite que um atacante descubra quais usernames existem no sistema antes mesmo de tentar qualquer senha.

```js
// vulnerable/server.js
const userExists = db.prepare("SELECT * FROM users WHERE username = ?").get(username);
if (!userExists) {
  return res.status(401).json({ message: "Usuário não encontrado" });
}
return res.status(401).json({ message: "Senha incorreta" });
```

### 5. Endpoint de debug exposto

O servidor possui uma rota pública que retorna todos os usernames e seus hashes MD5 sem nenhuma autenticação, simulando um vazamento de banco de dados.

```js
// vulnerable/server.js
app.get("/debug/hashes", (req, res) => {
  const rows = db.prepare("SELECT username, password FROM users").all();
  res.json(rows);
});
```

### 6. Sem MFA

O sistema libera o acesso com apenas usuário e senha. Não existe um segundo fator de autenticação, então qualquer senha descoberta dá acesso imediato à conta.

---

## Mitigações aplicadas no sistema seguro

### 1. bcrypt no lugar de MD5

O bcrypt é um algoritmo projetado especificamente para hashing de senhas. O parâmetro de custo (`12`) define quantas rodadas de processamento são executadas, tornando cada hash intencionalmente lento. Um salt único é gerado automaticamente pelo bcrypt para cada senha, então dois usuários com a mesma senha terão hashes completamente diferentes no banco.

```js
// secure/server.js
const SALT_ROUNDS = 12;
const hash = await bcrypt.hash(u.password, SALT_ROUNDS);
```

### 2. Rate limiting por IP

Um middleware bloqueia qualquer IP que exceda 5 tentativas de login em uma janela de 15 minutos, respondendo com HTTP 429 (Too Many Requests) para todas as requisições seguintes dentro desse período.

```js
// secure/server.js
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
});

app.post("/login", loginLimiter, async (req, res) => {
  // ...
});
```

### 3. Bloqueio de conta por tentativas falhas

O banco registra o número de tentativas erradas por usuário e o timestamp de expiração do bloqueio. Após 5 erros consecutivos, a conta fica bloqueada por 10 minutos independentemente do IP utilizado pelo atacante.

```js
// secure/server.js — tabela com colunas de proteção
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    ...
    failed_attempts INTEGER DEFAULT 0,
    locked_until    INTEGER DEFAULT 0
  )
`);

// lógica de bloqueio aplicada a cada tentativa falha
const newAttempts = (user.failed_attempts || 0) + 1;
const lockUntil = newAttempts >= 5 ? now + 10 * 60 * 1000 : 0;

db.prepare("UPDATE users SET failed_attempts = ?, locked_until = ? WHERE id = ?")
  .run(newAttempts, lockUntil, user.id);
```

### 4. Resposta genérica e tempo de resposta equalizado

O servidor retorna a mesma mensagem para qualquer falha de autenticação, impedindo a enumeração de usuários. Quando o username não existe, um hash bcrypt é calculado mesmo assim para igualar o tempo de resposta e evitar que o atacante distinga os casos medindo a latência.

```js
// secure/server.js
const GENERIC_ERROR = { success: false, message: "Credenciais inválidas" };

if (!user) {
  await bcrypt.hash(password, 12); // equaliza o tempo de resposta
  return res.status(401).json(GENERIC_ERROR);
}
```

### 5. MFA obrigatório

Após validar a senha corretamente, o servidor exige um token numérico de 6 dígitos antes de liberar o acesso. Uma senha descoberta por força bruta ou quebra de hash não é suficiente para autenticar sem o segundo fator.

```js
// secure/server.js
if (!mfa_token || mfa_token.length !== 6 || !/^\d{6}$/.test(mfa_token)) {
  return res.status(401).json({
    success: false,
    message: "Token MFA obrigatório (6 dígitos)",
    mfa_required: true,
  });
}
```

### 6. Endpoint de debug desativado

A rota `/debug/hashes` continua registrada no código para fins de demonstração, mas agora retorna HTTP 403 sem devolver nenhum dado do banco.

```js
// secure/server.js
app.get("/debug/hashes", (req, res) => {
  res.status(403).json({ message: "Acesso negado" });
});
```

---

## Credenciais do laboratório

| Usuário | Senha     |
|---------|-----------|
| admin   | admin123  |
| joao    | 123456    |
| maria   | password  |
| carlos  | qwerty    |
| ana     | letmein   |

---

## Ferramentas utilizadas

| Ferramenta       | Finalidade                                  |
|------------------|---------------------------------------------|
| Hydra            | Força bruta de login via HTTP POST          |
| John the Ripper  | Quebra de hashes offline                    |
| Docker           | Containerização dos dois ambientes          |
| Node.js/Express  | Servidor web dos dois sistemas              |
| bcrypt           | Algoritmo de hash seguro no sistema corrigido |

---

## Comandos úteis

```bash
# Testar login no servidor vulnerável
curl -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'

# Ver hashes expostos
curl http://localhost:3000/debug/hashes

# Testar rate limit no servidor seguro (execute mais de 5 vezes)
curl -X POST http://localhost:3001/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"errada"}'

# Derrubar os containers
docker compose down
```
