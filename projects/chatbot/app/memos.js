// ============================================================================
// 全ユーザー共有メモの「クライアント」モジュール
// ----------------------------------------------------------------------------
// Web App（このアプリ）から、メモ CRUD を行う Azure Function を呼び出す。
// 手動 UI（/memos）も AI ツール（tools.js の memo 系）も、最終的にここを経由する。
//
// 学習ポイント（get_user_profile の OBO との対比）:
//   - メモは「全ユーザー共有」なので、サインインしたユーザー本人の委任権限（OBO）ではなく、
//     アプリ自身（= Web App のマネージド ID）の権限で Function を呼ぶ（アプリ間認証）。
//   - Function は Entra（EasyAuth）で保護され、aud = api://<func-app-id> のトークンを要求する。
//     アプリは DefaultAzureCredential で `${MEMO_API_SCOPE}` のトークンを取得し Bearer で送る。
//     これは server.js が Azure OpenAI を呼ぶときと同じ「キーレス + MI」方式。
//
// 接続先と挙動は環境変数で切り替える（既存の Tavily / Entra と同じ「未設定なら劣化動作」方針）:
//   - MEMO_API_BASE_URL 未設定 → Function を呼ばず、プロセス内のインメモリ Mock を使う。
//       Azure を一切立てなくても、AI ツールと手動 UI の配線を端から端まで試せる。
//   - MEMO_API_BASE_URL 設定済み → その URL の Function を axios で叩く。
//       さらに MEMO_API_SCOPE があれば MI トークンを Bearer 付与（Azure 上）。
//       ローカルの func start（EasyAuth 無し）では MEMO_API_SCOPE を空にしてトークン無しで叩く。
// ============================================================================

const axios = require("axios");
const { getBearerTokenProvider, DefaultAzureCredential } = require("@azure/identity");

const BASE_URL = process.env.MEMO_API_BASE_URL || "";
// 例: api://<func-app-id>/.default 。空ならトークンを付けない（ローカル func 向け）。
const API_SCOPE = process.env.MEMO_API_SCOPE || "";

// Function を実際に呼ぶ構成かどうか。false ならインメモリ Mock。
const useRemote = Boolean(BASE_URL);

// MI トークンプロバイダ（スコープがあるときだけ用意）。OpenAI クライアントと同じ仕組みで、
// 内部でトークンをキャッシュ・自動更新してくれる。
let _tokenProvider = null;
if (useRemote && API_SCOPE) {
  const credential = new DefaultAzureCredential();
  _tokenProvider = getBearerTokenProvider(credential, API_SCOPE);
}

// ----------------------------------------------------------------------------
// インメモリ Mock ストア（MEMO_API_BASE_URL 未設定時）
// ----------------------------------------------------------------------------
// プロセスが生きている間だけ保持する簡易ストア。Function 側 memoStore.js と
// 同じデータ形（id / title / body / createdAt / updatedAt）を返し、呼び出し側から
// 見た振る舞いを Function 経路とそろえる。
const _mockMemos = new Map();
function mockNewId() {
  const ts = new Date().toISOString().replace(/[^0-9]/g, "");
  const rand = Math.random().toString(36).slice(2, 8);
  return `${ts}-${rand}`;
}
const mockStore = {
  list() {
    const memos = [..._mockMemos.values()].sort((a, b) => (a.id < b.id ? 1 : -1));
    return { memos };
  },
  get(id) {
    return _mockMemos.get(id) || null;
  },
  create({ title, body }) {
    if (!title || !String(title).trim()) {
      const e = new Error("title は必須です");
      e.statusCode = 400;
      throw e;
    }
    const now = new Date().toISOString();
    const memo = {
      id: mockNewId(),
      title: String(title).trim(),
      body: body ? String(body) : "",
      createdAt: now,
      updatedAt: now,
    };
    _mockMemos.set(memo.id, memo);
    return memo;
  },
  update(id, { title, body }) {
    const memo = _mockMemos.get(id);
    if (!memo) return null;
    if (title !== undefined) memo.title = String(title).trim();
    if (body !== undefined) memo.body = String(body);
    memo.updatedAt = new Date().toISOString();
    _mockMemos.set(id, memo);
    return memo;
  },
  remove(id) {
    return _mockMemos.delete(id);
  },
};

// ----------------------------------------------------------------------------
// Function（リモート）呼び出し
// ----------------------------------------------------------------------------
// Bearer トークン付きの共通ヘッダを組み立てる。スコープ未設定ならトークンは付けない。
async function authHeaders() {
  const headers = { "Content-Type": "application/json" };
  if (_tokenProvider) {
    const token = await _tokenProvider();
    headers.Authorization = `Bearer ${token}`;
  }
  return headers;
}

function memoUrl(path = "") {
  // BASE_URL 末尾スラッシュの有無を吸収して /api/memos に繋ぐ。
  const base = BASE_URL.replace(/\/$/, "");
  return `${base}/api/memos${path}`;
}

const remoteStore = {
  async list() {
    const { data } = await axios.get(memoUrl(), { headers: await authHeaders() });
    return data; // { memos: [...] }
  },
  async get(id) {
    try {
      const { data } = await axios.get(memoUrl(`/${encodeURIComponent(id)}`), { headers: await authHeaders() });
      return data;
    } catch (err) {
      if (err.response?.status === 404) return null;
      throw err;
    }
  },
  async create({ title, body }) {
    const { data } = await axios.post(memoUrl(), { title, body }, { headers: await authHeaders() });
    return data;
  },
  async update(id, { title, body }) {
    try {
      const { data } = await axios.patch(
        memoUrl(`/${encodeURIComponent(id)}`),
        { title, body },
        { headers: await authHeaders() }
      );
      return data;
    } catch (err) {
      if (err.response?.status === 404) return null;
      throw err;
    }
  },
  async remove(id) {
    const { data } = await axios.delete(memoUrl(`/${encodeURIComponent(id)}`), { headers: await authHeaders() });
    return Boolean(data?.deleted);
  },
};

// ----------------------------------------------------------------------------
// 公開 API（呼び出し側＝server.js / tools.js はこれだけ使う）
// ----------------------------------------------------------------------------
// remote / mock を意識せず使えるよう、同じシグネチャでラップする。
// _source を付けて「どの経路で動いたか」を呼び出し側（AI/UI）から確認できるようにする。

async function listMemos() {
  const data = useRemote ? await remoteStore.list() : mockStore.list();
  return { memos: data.memos || [], _source: useRemote ? "function" : "mock" };
}

async function getMemo(id) {
  const memo = useRemote ? await remoteStore.get(id) : mockStore.get(id);
  return memo;
}

async function createMemo({ title, body }) {
  const memo = useRemote ? await remoteStore.create({ title, body }) : mockStore.create({ title, body });
  return { ...memo, _source: useRemote ? "function" : "mock" };
}

async function updateMemo(id, { title, body }) {
  const memo = useRemote ? await remoteStore.update(id, { title, body }) : mockStore.update(id, { title, body });
  if (!memo) return null;
  return { ...memo, _source: useRemote ? "function" : "mock" };
}

async function deleteMemo(id) {
  const deleted = useRemote ? await remoteStore.remove(id) : mockStore.remove(id);
  return { id, deleted, _source: useRemote ? "function" : "mock" };
}

module.exports = {
  listMemos,
  getMemo,
  createMemo,
  updateMemo,
  deleteMemo,
  // 設定状況をログ等で確認できるように公開。
  isRemote: useRemote,
};
