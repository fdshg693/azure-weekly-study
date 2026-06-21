// バニラ JS フロント。状態は最小限、API は BFF(/api/*) 経由。
// 自分が誰かは localStorage に保存し、毎リクエスト X-User ヘッダで送る（認証なし MVP）。

const state = {
  me: localStorage.getItem("me") || null,
  activePeer: null,
};

const $ = (id) => document.getElementById(id);

// X-User を必ず付ける fetch ラッパ
async function api(path, opts = {}) {
  const headers = { "Content-Type": "application/json", ...(opts.headers || {}) };
  if (state.me) headers["X-User"] = state.me;
  const res = await fetch(path, { ...opts, headers });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.status === 204 ? null : res.json();
}

// --- ログイン ---------------------------------------------------------------
$("login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const username = $("username-input").value.trim().toLowerCase();
  if (!username) return;
  await api("/api/login", { method: "POST", body: JSON.stringify({ username }) });
  state.me = username;
  localStorage.setItem("me", username);
  enterApp();
});

$("logout-btn").addEventListener("click", () => {
  localStorage.removeItem("me");
  state.me = null;
  state.activePeer = null;
  $("main-view").classList.add("hidden");
  $("login-view").classList.remove("hidden");
});

function enterApp() {
  $("me").textContent = state.me;
  $("login-view").classList.add("hidden");
  $("main-view").classList.remove("hidden");
  loadUsers();
}

// --- ユーザー一覧 -----------------------------------------------------------
async function loadUsers() {
  const data = await api("/api/users");
  const others = data.users.filter((u) => u !== state.me);
  const ul = $("user-list");
  ul.innerHTML = "";
  for (const u of others) {
    const li = document.createElement("li");
    li.textContent = u;
    li.dataset.user = u;
    if (u === state.activePeer) li.classList.add("active");
    li.addEventListener("click", () => openConversation(u));
    ul.appendChild(li);
  }
  $("users-cache").textContent = data.cached
    ? "（キャッシュ表示：⟳ で最新化）"
    : "（最新を取得）";
}

$("refresh-users").addEventListener("click", loadUsers);

// --- 会話 -------------------------------------------------------------------
async function openConversation(peer) {
  state.activePeer = peer;
  document
    .querySelectorAll("#user-list li")
    .forEach((li) => li.classList.toggle("active", li.dataset.user === peer));
  $("chat-with").textContent = peer;
  $("send-form").classList.remove("hidden");
  await loadConversation();
}

async function loadConversation() {
  if (!state.activePeer) return;
  const data = await api(
    `/api/conversation?with=${encodeURIComponent(state.activePeer)}`
  );
  renderMessages(data.messages);
  $("conv-cache").textContent = data.cached
    ? "（キャッシュ表示：リロードしても TTL 切れまで新着は出ません）"
    : "（Cosmos から最新を取得）";
}

function renderMessages(messages) {
  const box = $("messages");
  box.innerHTML = "";
  for (const m of messages) {
    box.appendChild(bubble(m, m.from === state.me));
  }
  box.scrollTop = box.scrollHeight;
}

function bubble(m, mine) {
  const div = document.createElement("div");
  div.className = `bubble ${mine ? "mine" : "theirs"}`;
  div.textContent = m.text;
  const ts = document.createElement("span");
  ts.className = "ts";
  ts.textContent = new Date(m.createdAt).toLocaleTimeString();
  div.appendChild(ts);
  return div;
}

$("refresh-conv").addEventListener("click", loadConversation);

// --- 送信（楽観的表示） -----------------------------------------------------
$("send-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const text = $("message-input").value.trim();
  if (!text || !state.activePeer) return;
  $("message-input").value = "";

  // 楽観的表示：送信者の画面には即追加する（リアルタイム配信はしない MVP）
  $("messages").appendChild(
    bubble({ text, from: state.me, createdAt: new Date().toISOString() }, true)
  );
  $("messages").scrollTop = $("messages").scrollHeight;

  await api("/api/messages", {
    method: "POST",
    body: JSON.stringify({ to: state.activePeer, text }),
  });
});

// 既ログインなら自動で入る
if (state.me) enterApp();
