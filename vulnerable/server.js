const express = require("express");
const Database = require("better-sqlite3");
const crypto = require("crypto");
const path = require("path");

const app = express();
const db = new Database("./users.db");

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static("public"));

// ============================================================
// BANCO DE DADOS - senhas armazenadas como MD5 simples (fraco)
// ============================================================
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    email TEXT,
    role TEXT DEFAULT 'user'
  )
`);

// Hash MD5 simples - VULNERÁVEL (sem salt, algoritmo quebrado)
function weakHash(password) {
  return crypto.createHash("md5").update(password).digest("hex");
}

// Seed: usuários com senhas fracas e comuns
const users = [
  { username: "admin",   password: "admin123",  email: "admin@lab.com",   role: "admin" },
  { username: "joao",    password: "123456",    email: "joao@lab.com",    role: "user"  },
  { username: "maria",   password: "password",  email: "maria@lab.com",   role: "user"  },
  { username: "carlos",  password: "qwerty",    email: "carlos@lab.com",  role: "user"  },
  { username: "ana",     password: "letmein",   email: "ana@lab.com",     role: "user"  },
];

const insertUser = db.prepare(
  "INSERT OR IGNORE INTO users (username, password, email, role) VALUES (?, ?, ?, ?)"
);

for (const u of users) {
  insertUser.run(u.username, weakHash(u.password), u.email, u.role);
}

// ============================================================
// ROTA DE LOGIN - VULNERÁVEL
// Sem rate limiting, sem bloqueio por tentativas, sem MFA
// ============================================================
app.post("/login", (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ success: false, message: "Campos obrigatórios" });
  }

  const hashed = weakHash(password);

  // Sem prepared statement correto + sem proteção de enumeração de usuário
  const user = db.prepare("SELECT * FROM users WHERE username = ? AND password = ?")
    .get(username, hashed);

  if (user) {
    // Sem JWT, sem sessão segura - apenas retorna os dados diretamente
    return res.json({
      success: true,
      message: "Login realizado com sucesso!",
      user: { id: user.id, username: user.username, email: user.email, role: user.role },
    });
  }

  // Mensagem diferenciada por username/senha - ajuda enumeração de usuários
  const userExists = db.prepare("SELECT * FROM users WHERE username = ?").get(username);
  if (!userExists) {
    return res.status(200).json({ success: false, message: "Usuário não encontrado" });
  }
  return res.status(200).json({ success: false, message: "Senha incorreta" });
});

// Expõe hashes MD5 diretamente (simula dump de banco)
app.get("/debug/hashes", (req, res) => {
  const rows = db.prepare("SELECT username, password FROM users").all();
  res.json(rows);
});

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

const PORT = 3000;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`[VULNERÁVEL] Servidor rodando em http://localhost:${PORT}`);
  console.log(`[VULNERÁVEL] Hashes expostos em http://localhost:${PORT}/debug/hashes`);
});
