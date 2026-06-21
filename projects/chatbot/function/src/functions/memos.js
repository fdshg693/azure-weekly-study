// ============================================================================
// メモ CRUD の HTTP API（Azure Functions Node.js v4 モデル）
// ----------------------------------------------------------------------------
// 全ユーザー共有メモを操作する REST エンドポイント。アプリ本体（Web App）は
// この Function を「自分自身（Managed Identity）の権限」で呼ぶ（OBO ではない）。
//
// 認可の考え方:
//   - Azure 上では Function に EasyAuth（App Service 認証）を有効化し、Entra トークン
//     （aud = api://<func-app-id>）を要求する。EasyAuth が検証に成功すると、呼び出し元の
//     クレームを Base64 JSON で x-ms-client-principal ヘッダに載せて関数へ渡す。
//   - ここではさらに、そのクレームの roles に MEMO_REQUIRED_ROLE（既定 Memo.ReadWrite）が
//     含まれるかを確認する。Web App の MI にだけこの app role を割り当てておくことで、
//     「このアプリだけが共有メモを操作できる」を成立させる（最小権限）。
//   - ローカル（func start）は EasyAuth が無いので MEMO_REQUIRE_AUTH=false で検証をスキップ。
// ============================================================================

const { app } = require("@azure/functions");
const memoStore = require("../memoStore");

const REQUIRE_AUTH = String(process.env.MEMO_REQUIRE_AUTH || "false").toLowerCase() === "true";
const REQUIRED_ROLE = process.env.MEMO_REQUIRED_ROLE || "Memo.ReadWrite";

// EasyAuth が付与する x-ms-client-principal（Base64 の JSON）をデコードする。
// roles / claims を取り出して呼び出し元の app role を判定する。
function decodeClientPrincipal(request) {
  const header = request.headers.get("x-ms-client-principal");
  if (!header) return null;
  try {
    return JSON.parse(Buffer.from(header, "base64").toString("utf8"));
  } catch (_) {
    return null;
  }
}

// 呼び出し元が必要な app role を持っているか検証する。
// 認可 OK なら null、NG なら { status, jsonBody } のエラーレスポンスを返す。
function checkAuthorization(request, context) {
  if (!REQUIRE_AUTH) return null; // ローカル等では検証しない

  const principal = decodeClientPrincipal(request);
  if (!principal) {
    context.warn("x-ms-client-principal が無い（EasyAuth 未経由のアクセス）");
    return { status: 401, jsonBody: { error: "認証が必要です（EasyAuth トークンがありません）" } };
  }

  // roles クレームは claims 配列内（typ: "roles"）か、トップレベル userRoles に入る。
  const claimRoles = (principal.claims || [])
    .filter((c) => c.typ === "roles" || c.typ === "http://schemas.microsoft.com/ws/2008/06/identity/claims/role")
    .map((c) => c.val);
  const roles = [...new Set([...(principal.userRoles || []), ...claimRoles])];

  if (!roles.includes(REQUIRED_ROLE)) {
    context.warn(`必要な app role(${REQUIRED_ROLE}) がありません。付与済: [${roles.join(", ")}]`);
    return { status: 403, jsonBody: { error: `app role '${REQUIRED_ROLE}' が必要です` } };
  }
  return null;
}

// リクエストボディを安全に JSON として読む（空ボディや不正 JSON は {} 扱い）。
async function readJson(request) {
  try {
    const text = await request.text();
    return text ? JSON.parse(text) : {};
  } catch (_) {
    return {};
  }
}

// CRUD ハンドラを 1 つにまとめ、メソッド + ルートで分岐する。
// （v4 モデルでは関数ごとに app.http で登録するが、認可とエラー処理を共通化したいので
//   薄いディスパッチャを 1 つ置く構成にした。）
async function handler(request, context) {
  const authError = checkAuthorization(request, context);
  if (authError) return authError;

  const method = request.method.toUpperCase();
  const id = request.params.id;

  try {
    // ---- 一覧 / 取得 ----
    if (method === "GET") {
      if (id) {
        const memo = await memoStore.get(id);
        if (!memo) return { status: 404, jsonBody: { error: "メモが見つかりません" } };
        return { jsonBody: memo };
      }
      const memos = await memoStore.list();
      return { jsonBody: { memos } };
    }

    // ---- 作成 ----
    if (method === "POST") {
      const body = await readJson(request);
      const memo = await memoStore.create({ title: body.title, body: body.body });
      return { status: 201, jsonBody: memo };
    }

    // ---- 更新（部分更新）----
    if (method === "PATCH" || method === "PUT") {
      if (!id) return { status: 400, jsonBody: { error: "更新には id が必要です" } };
      const body = await readJson(request);
      const memo = await memoStore.update(id, { title: body.title, body: body.body });
      if (!memo) return { status: 404, jsonBody: { error: "メモが見つかりません" } };
      return { jsonBody: memo };
    }

    // ---- 削除 ----
    if (method === "DELETE") {
      if (!id) return { status: 400, jsonBody: { error: "削除には id が必要です" } };
      const deleted = await memoStore.remove(id);
      return { jsonBody: { id, deleted } };
    }

    return { status: 405, jsonBody: { error: `未対応のメソッド: ${method}` } };
  } catch (err) {
    // memoStore が投げる検証エラー（statusCode 付き）はそのまま返す。
    const status = err.statusCode && err.statusCode < 500 ? err.statusCode : 500;
    context.error("memo handler error:", err.message || err);
    return { status, jsonBody: { error: err.message || "内部エラー" } };
  }
}

// コレクション操作（/api/memos）: 一覧・作成。
app.http("memosCollection", {
  methods: ["GET", "POST"],
  authLevel: "anonymous", // 認可は EasyAuth + checkAuthorization で行う（Function キーは使わない）
  route: "memos",
  handler,
});

// 単体操作（/api/memos/{id}）: 取得・更新・削除。
app.http("memosItem", {
  methods: ["GET", "PATCH", "PUT", "DELETE"],
  authLevel: "anonymous",
  route: "memos/{id}",
  handler,
});
