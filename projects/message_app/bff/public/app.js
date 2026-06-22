// バニラ JS フロント。状態は最小限、API は BFF(/api/*) 経由。
// V2: 認証は JWT。ログイン成功で受け取ったトークンを localStorage に保持し、
// 毎リクエスト Authorization: Bearer で送る（X-User の自己申告は廃止）。

const state = {
  me: localStorage.getItem("me") || null,
  token: localStorage.getItem("token") || null,
  activePeer: null,
  friends: [],
};

const $ = (id) => document.getElementById(id);

// Bearer トークンを必ず付ける fetch ラッパ。401 ならセッション切れとして弾く。
async function api(path, opts = {}) {
  const headers = { "Content-Type": "application/json", ...(opts.headers || {}) };
  if (state.token) headers["Authorization"] = `Bearer ${state.token}`;
  const res = await fetch(path, { ...opts, headers });
  if (res.status === 401) {
    doLogout();
    throw new Error("セッションが切れました。再ログインしてください。");
  }
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.status === 204 ? null : res.json();
}

// --- 認証画面のタブ切替 -----------------------------------------------------
function showAuthMessage(text, kind = "info") {
  const el = $("auth-message");
  el.textContent = text;
  el.className = `auth-message ${kind}`;
}

$("tab-login").addEventListener("click", () => {
  $("tab-login").classList.add("active");
  $("tab-signup").classList.remove("active");
  $("login-form").classList.remove("hidden");
  $("signup-form").classList.add("hidden");
  showAuthMessage("");
});
$("tab-signup").addEventListener("click", () => {
  $("tab-signup").classList.add("active");
  $("tab-login").classList.remove("active");
  $("signup-form").classList.remove("hidden");
  $("login-form").classList.add("hidden");
  showAuthMessage("");
});

// --- サインアップ -----------------------------------------------------------
$("signup-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const email = $("signup-email").value.trim().toLowerCase();
  const username = $("signup-username").value.trim().toLowerCase();
  const password = $("signup-password").value;
  if (!email || !username || !password) return;
  try {
    // トークン不要の入口。Authorization は付かない（state.token は null）。
    const res = await fetch("/api/signup", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, username, password }),
    });
    if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
    // ローカルでは検証リンクがコンソール / .verify-links に出る。
    showAuthMessage(
      "登録しました。検証リンクを開いてください（ローカルは func のコンソール / .verify-links/ に出力）。検証後にログインできます。",
      "ok"
    );
  } catch (err) {
    showAuthMessage(`登録に失敗: ${err.message}`, "err");
  }
});

// --- ログイン ---------------------------------------------------------------
$("login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const email = $("login-email").value.trim().toLowerCase();
  const password = $("login-password").value;
  if (!email || !password) return;
  try {
    const res = await fetch("/api/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    if (res.status === 403) {
      showAuthMessage("メール未検証です。検証リンクを開いてからログインしてください。", "err");
      return;
    }
    if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
    const data = await res.json();
    state.token = data.token;
    state.me = data.username;
    localStorage.setItem("token", state.token);
    localStorage.setItem("me", state.me);
    enterApp();
  } catch (err) {
    showAuthMessage(`ログインに失敗: ${err.message}`, "err");
  }
});

function doLogout() {
  localStorage.removeItem("token");
  localStorage.removeItem("me");
  state.token = null;
  state.me = null;
  state.activePeer = null;
  state.friends = [];
  $("main-view").classList.add("hidden");
  $("login-view").classList.remove("hidden");
}
$("logout-btn").addEventListener("click", doLogout);

async function enterApp() {
  $("me").textContent = state.me;
  $("login-view").classList.add("hidden");
  $("main-view").classList.remove("hidden");
  // 友達一覧を先に取り、その後ユーザー一覧（「＋友達/友達✓」の判定に state.friends を使う）
  await loadFriends();
  await loadUsers();
}

// --- 友達リスト -------------------------------------------------------------
async function loadFriends() {
  const data = await api("/api/friends");
  state.friends = data.friends;
  const ul = $("friend-list");
  ul.innerHTML = "";
  for (const u of data.friends) {
    const li = document.createElement("li");
    li.dataset.user = u;
    if (u === state.activePeer) li.classList.add("active");

    const name = document.createElement("span");
    name.textContent = u;
    name.className = "row-name";
    name.addEventListener("click", () => openConversation(u));

    const del = document.createElement("button");
    del.className = "ghost small";
    del.textContent = "削除";
    del.title = "友達から削除";
    del.addEventListener("click", (e) => {
      e.stopPropagation();
      removeFriend(u);
    });

    li.appendChild(name);
    li.appendChild(del);
    ul.appendChild(li);
  }
  $("friends-cache").textContent = data.cached
    ? "（キャッシュ表示：自分の追加/削除では即時に無効化されます）"
    : "（最新を取得）";
}

async function addFriend(username) {
  await api("/api/friends", {
    method: "POST",
    body: JSON.stringify({ username }),
  });
  // 自分の操作 → 自分のキャッシュは無効化済み。一覧を取り直すと即反映される。
  await loadFriends();
  await loadUsers();
}

async function removeFriend(username) {
  await api(`/api/friends/${encodeURIComponent(username)}`, { method: "DELETE" });
  await loadFriends();
  await loadUsers();
}

$("refresh-friends").addEventListener("click", loadFriends);

// --- ユーザー一覧 -----------------------------------------------------------
async function loadUsers() {
  const data = await api("/api/users");
  const others = data.users.filter((u) => u !== state.me);
  const ul = $("user-list");
  ul.innerHTML = "";
  for (const u of others) {
    const li = document.createElement("li");
    li.dataset.user = u;
    if (u === state.activePeer) li.classList.add("active");

    const name = document.createElement("span");
    name.textContent = u;
    name.className = "row-name";
    name.addEventListener("click", () => openConversation(u));

    const isFriend = state.friends.includes(u);
    const btn = document.createElement("button");
    btn.className = "ghost small";
    btn.textContent = isFriend ? "友達✓" : "＋友達";
    btn.disabled = isFriend;
    btn.title = isFriend ? "すでに友達" : "友達に追加";
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      addFriend(u);
    });

    li.appendChild(name);
    li.appendChild(btn);
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
    .querySelectorAll("#user-list li, #friend-list li")
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

// 既ログイン（トークン保持）なら自動で入る
if (state.token && state.me) enterApp();
