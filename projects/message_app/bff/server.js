// BFF（Backend For Frontend / Express）。
// 役割は 3 つ:
//   1) public/ の静的フロントを配信する
//   2) /api/* を下流へ振り分ける（読み取り=FastAPI、書き込み=Functions）
//   3) V2: JWT を検証し、本人(username)を下流へ信頼済み X-User として注入する
//
// V2 の信頼境界：client は JWT を送る → BFF が署名/期限を検証 → sub(=username) を取り出し、
// 下流へ X-User として転送する。これで client は身元を詐称できなくなる（V1 との違いの肝）。
// 例外：signup / verify / login はトークン発行前の入口なので検証しない（そのまま流す）。

require("dotenv").config();
const path = require("path");
const express = require("express");
const jwt = require("jsonwebtoken");

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
// 読み取り API（FastAPI / App Service）
const API_BASE = process.env.API_BASE_URL || "http://localhost:8000";
// 書き込み（Azure Functions）。ローカル func は http://localhost:7071
const FUNC_BASE = process.env.FUNCTIONS_BASE_URL || "http://localhost:7071";
// Azure 上の Functions を function キーで保護する場合に付与（ローカルは anonymous で空）
const FUNC_KEY = process.env.FUNCTIONS_KEY || "";
// login(FastAPI) が発行した JWT を、同じ秘密鍵 / HS256 で検証する。
const JWT_SECRET = process.env.JWT_SECRET || "dev-insecure-secret-change-me";

// 下流へ JSON を中継する小さなヘルパ。X-User は呼び出し元から引き継ぐ。
async function forward(res, url, { method = "GET", user, body, extraHeaders } = {}) {
  const headers = { "Content-Type": "application/json", ...extraHeaders };
  if (user) headers["X-User"] = user;
  try {
    const upstream = await fetch(url, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    const text = await upstream.text();
    res.status(upstream.status);
    res.type(upstream.headers.get("content-type") || "application/json");
    res.send(text);
  } catch (err) {
    console.error(`forward error -> ${url}:`, err.message);
    res.status(502).json({ error: "upstream unavailable", target: url });
  }
}

// JWT 検証ミドルウェア。Authorization: Bearer <JWT> を検証し、req.authUser に本人をセット。
// 失敗（欠落 / 改ざん / 失効）は下流へ流さず 401（信頼境界は BFF にある）。
function requireAuth(req, res, next) {
  const header = req.header("Authorization") || "";
  const match = header.match(/^Bearer (.+)$/);
  if (!match) return res.status(401).json({ error: "missing bearer token" });
  try {
    const payload = jwt.verify(match[1], JWT_SECRET, { algorithms: ["HS256"] });
    req.authUser = payload.sub;
    next();
  } catch (err) {
    return res.status(401).json({ error: "invalid or expired token" });
  }
}

// 書き込み(Functions)へ流すときに関数キーを付ける小ヘルパ。
function funcHeaders() {
  return FUNC_KEY ? { "x-functions-key": FUNC_KEY } : {};
}

// --- 認証の入口（トークン不要・検証しない例外ルート） -----------------------
app.post("/api/signup", (req, res) =>
  forward(res, `${FUNC_BASE}/api/signup`, {
    method: "POST",
    body: req.body,
    extraHeaders: funcHeaders(),
  })
);

// メールのリンク先。ブラウザが直接開く（HTML が返る）。
app.get("/api/verify", (req, res) => {
  const token = encodeURIComponent(req.query.token || "");
  forward(res, `${FUNC_BASE}/api/verify?token=${token}`, {
    extraHeaders: funcHeaders(),
  });
});

app.post("/api/login", (req, res) =>
  forward(res, `${API_BASE}/login`, { method: "POST", body: req.body })
);

// --- 以降は要トークン（BFF が検証して X-User を注入） ------------------------
// 読み取り（FastAPI へ）
app.get("/api/users", requireAuth, (req, res) =>
  forward(res, `${API_BASE}/users`, { user: req.authUser })
);

app.get("/api/conversation", requireAuth, (req, res) => {
  const withUser = encodeURIComponent(req.query.with || "");
  forward(res, `${API_BASE}/conversation?with=${withUser}`, { user: req.authUser });
});

app.get("/api/friends", requireAuth, (req, res) =>
  forward(res, `${API_BASE}/friends`, { user: req.authUser })
);

// 書き込み（Functions へ）
app.post("/api/messages", requireAuth, (req, res) =>
  forward(res, `${FUNC_BASE}/api/messages`, {
    method: "POST",
    user: req.authUser,
    body: req.body,
    extraHeaders: funcHeaders(),
  })
);

app.post("/api/friends", requireAuth, (req, res) =>
  forward(res, `${FUNC_BASE}/api/friends`, {
    method: "POST",
    user: req.authUser,
    body: req.body,
    extraHeaders: funcHeaders(),
  })
);

app.delete("/api/friends/:username", requireAuth, (req, res) =>
  forward(res, `${FUNC_BASE}/api/friends/${encodeURIComponent(req.params.username)}`, {
    method: "DELETE",
    user: req.authUser,
    extraHeaders: funcHeaders(),
  })
);

// --- 静的フロント -------------------------------------------------------------
app.use(express.static(path.join(__dirname, "public")));

app.listen(PORT, () => {
  console.log(`BFF listening on http://localhost:${PORT}`);
  console.log(`  read  -> ${API_BASE}`);
  console.log(`  write -> ${FUNC_BASE}`);
});
