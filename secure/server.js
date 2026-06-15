const express = require("express");
const Database = require("better-sqlite3");
const bcrypt = require("bcrypt");
const rateLimit = require("express-rate-limit");
const path = require("path");
const crypto = require("crypto");

const app = express();
const db = new Database("./users_secure.db");

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static("public"));

// ============================================================
// BANCO DE DADOS - senhas com bcrypt (custo 12)
// ============================================================
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    email TEXT,
    role TEXT DEFAULT 'user',
    mfa_secret TEXT,
    failed_attempts INTEGER DEFAULT 0,
    locked_until INTEGER DEFAULT 0
  )
`);

// ============================================================
// SEED com bcrypt - custo 12 (lento por design)
// ============================================================
async function seedUsers() {
  const SALT_ROUNDS = 12;

  const users = [
    { username: "admin",  password: "admin123",  email: "admin@lab.com",  role: "admin" },
    { username: "joao",   password: "123456",    email: "joao@lab.com",   role: "user"  },
    { username: "maria",  password: "password",  email: "maria@lab.com",  role: "user"  },
  ];

  const check = db.prepare("SELECT id FROM users WHERE username = ?");
  const insert = db.prepare(
    "INSERT INTO users (username, password, email, role, mfa_secret) VALUES (?, ?, ?, ?, ?)"
  );

  for (const u of users) {
    if (!check.get(u.username)) {
      const hash = await bcrypt.hash(u.password, SALT_ROUNDS);
      // MFA secret simulado (TOTP real usaria speakeasy/otplib)
      const mfaSecret = crypto.randomBytes(16).toString("hex");
      insert.run(u.username, hash, u.email, u.role, mfaSecret);
      console.log(`[SEED] Usuário criado: ${u.username}`);
    }
  }
}

// ============================================================
// RATE LIMITING - máximo 5 tentativas por IP em 15 minutos
// ============================================================
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: "Muitas tentativas de login. Tente novamente em 15 minutos.",
  },
  handler: (req, res, next, options) => {
    console.log(`[BLOQUEADO] IP ${req.ip} excedeu limite de tentativas`);
    res.status(429).json(options.message);
  },
});

// ============================================================
// ROTA DE LOGIN - SEGURA
// Com bcrypt, rate limiting, bloqueio por conta, MFA obrigatório
// ============================================================
app.post("/login", loginLimiter, async (req, res) => {
  const { username, password, mfa_token } = req.body;

  if (!username || !password) {
    return res.status(400).json({ success: false, message: "Campos obrigatórios" });
  }

  const user = db.prepare("SELECT * FROM users WHERE username = ?").get(username);

  // Resposta genérica - não diferencia usuário inexistente de senha errada
  // Evita enumeração de usuários
  const GENERIC_ERROR = { success: false, message: "Credenciais inválidas" };

  if (!user) {
    // Mesmo tempo de resposta para não vazar informação via timing
    await bcrypt.hash(password, 12);
    return res.status(401).json(GENERIC_ERROR);
  }

  // Verifica bloqueio temporário da conta (5 tentativas erradas = 10 min bloqueado)
  const now = Date.now();
  if (user.locked_until && now < user.locked_until) {
    const remaining = Math.ceil((user.locked_until - now) / 1000 / 60);
    return res.status(403).json({
      success: false,
      message: `Conta bloqueada. Tente novamente em ${remaining} minuto(s)`,
    });
  }

  // bcrypt.compare - resistente a timing attack
  const passwordMatch = await bcrypt.compare(password, user.password);

  if (!passwordMatch) {
    const newAttempts = (user.failed_attempts || 0) + 1;
    const lockUntil = newAttempts >= 5 ? now + 10 * 60 * 1000 : 0;

    db.prepare("UPDATE users SET failed_attempts = ?, locked_until = ? WHERE id = ?")
      .run(newAttempts, lockUntil, user.id);

    if (lockUntil) {
      console.log(`[SEGURANÇA] Conta ${username} bloqueada por 10 min após 5 tentativas`);
    }

    return res.status(401).json(GENERIC_ERROR);
  }

  // Verifica MFA (token numérico de 6 dígitos simulado)
  // Em produção: validar TOTP com speakeasy/otplib
  if (!mfa_token || mfa_token.length !== 6 || !/^\d{6}$/.test(mfa_token)) {
    return res.status(401).json({
      success: false,
      message: "Token MFA obrigatório (6 dígitos)",
      mfa_required: true,
    });
  }

  // Simulação: aceita qualquer token de 6 dígitos válidos no formato (em lab)
  // Em produção real: verificaria TOTP via speakeasy.totp.verify()

  // Login bem-sucedido - reseta tentativas
  db.prepare("UPDATE users SET failed_attempts = 0, locked_until = 0 WHERE id = ?")
    .run(user.id);

  console.log(`[SUCESSO] Login: ${username} | IP: ${req.ip}`);

  return res.json({
    success: true,
    message: "Login realizado com sucesso!",
    user: { id: user.id, username: user.username, email: user.email, role: user.role },
  });
});

// Rota de debug removida - não expõe hashes
app.get("/debug/hashes", (req, res) => {
  res.status(403).json({ message: "Acesso negado - endpoint de debug desativado" });
});

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

seedUsers().then(() => {
  const PORT = 3001;
  app.listen(PORT, "0.0.0.0", () => {
    console.log(`[SEGURO] Servidor rodando em http://localhost:${PORT}`);
    console.log(`[SEGURO] Rate limit: 5 tentativas por IP a cada 15 min`);
    console.log(`[SEGURO] Bloqueio de conta: 5 tentativas erradas = 10 min bloqueado`);
    console.log(`[SEGURO] bcrypt custo 12 + MFA obrigatório`);
  });
});
