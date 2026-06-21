// BFF（Backend For Frontend / Express）。
// 役割は 2 つ:
//   1) public/ の静的フロントを配信する
//   2) /api/* を下流へ振り分ける（読み取り=FastAPI、書き込み=Functions）
// 認証は無いので、フロントが付ける X-User ヘッダ(=自分の username)をそのまま下流に転送する。

require("dotenv").config();
const path = require("path");
const express = require("express");

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
// 読み取り API（FastAPI / App Service）
const API_BASE = process.env.API_BASE_URL || "http://localhost:8000";
// 書き込み（Azure Functions）。ローカル func は http://localhost:7071
const FUNC_BASE = process.env.FUNCTIONS_BASE_URL || "http://localhost:7071";
// Azure 上の Functions を function キーで保護する場合に付与（ローカルは anonymous で空）
const FUNC_KEY = process.env.FUNCTIONS_KEY || "";

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

// --- 読み取り（FastAPI へ） ---------------------------------------------------
app.post("/api/login", (req, res) =>
  forward(res, `${API_BASE}/login`, { method: "POST", body: req.body })
);

app.get("/api/users", (req, res) => forward(res, `${API_BASE}/users`));

app.get("/api/conversation", (req, res) => {
  const withUser = encodeURIComponent(req.query.with || "");
  forward(res, `${API_BASE}/conversation?with=${withUser}`, {
    user: req.header("X-User"),
  });
});

// --- 書き込み（Functions へ） -------------------------------------------------
app.post("/api/messages", (req, res) => {
  const extraHeaders = FUNC_KEY ? { "x-functions-key": FUNC_KEY } : {};
  forward(res, `${FUNC_BASE}/api/messages`, {
    method: "POST",
    user: req.header("X-User"),
    body: req.body,
    extraHeaders,
  });
});

// --- 静的フロント -------------------------------------------------------------
app.use(express.static(path.join(__dirname, "public")));

app.listen(PORT, () => {
  console.log(`BFF listening on http://localhost:${PORT}`);
  console.log(`  read  -> ${API_BASE}`);
  console.log(`  write -> ${FUNC_BASE}`);
});
