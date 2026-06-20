// ============================================================================
// チャットの AI が呼び出せる「ツール（function calling）」定義と実体。
// ----------------------------------------------------------------------------
// experiments/tools-demo.js の get_user_profile を、実アプリ向けに作り直したもの。
// 違い:
//   - デモは固定のモックユーザーを返すだけだった
//   - こちらは「Entra ID 認証が設定され、かつユーザーが OBO サインイン済み」のとき、
//     ユーザー本人のトークンを OBO 交換して本物の Microsoft Graph /me を呼ぶ。
//     未設定のときだけモックを返す。
//
// 設計の意図（学習ポイント）:
//   (A)「AI がログインユーザー本人の権限で下流（Graph）を叩く」を端から端まで成立させる。
//   - チャットのサインインは OBO フロー（/auth/signin-obo）を使い、セッションには
//     aud = api://<client-id> の初回トークンが入る。
//   - ツール実行時にその初回トークンを OBO 交換し、aud = Graph のトークンを得て /me を呼ぶ。
//   - これによりサーバー ID ではなく「サインインしたユーザー本人の委任権限」で Graph が動く。
//   また、AI に渡すツールの「定義」自体をログイン状態で出し分けるため、
//   未サインインだと AI はそもそもプロフィール取得手段を持たない。
// ============================================================================

const obo = require("./auth_obo");
const { isConfigured } = require("./auth");

// Microsoft Graph /me が返す代表的なフィールド。モックもこれに合わせておくと、
// 本物 / モックのどちらでも AI から見たデータ形状が揃う。
const PROFILE_FIELDS = [
  "displayName",
  "givenName",
  "surname",
  "mail",
  "userPrincipalName",
  "jobTitle",
  "officeLocation",
  "mobilePhone",
  "preferredLanguage",
];

// Entra 未設定時に返すモックプロフィール（Graph /me と同じキー名で用意）。
const MOCK_PROFILE = {
  displayName: "山田 太郎（モック）",
  givenName: "太郎",
  surname: "山田",
  mail: "taro.yamada@example.com",
  userPrincipalName: "taro.yamada@example.com",
  jobTitle: "デモ用ダミーユーザー",
  officeLocation: "東京",
  mobilePhone: "+81-90-0000-0000",
  preferredLanguage: "ja-JP",
};

// Responses API 形式のツール定義。
// Chat Completions（experiments/tools-demo.js）では function を入れ子にしていたが、
// Responses API では name / description / parameters がトップレベルにフラットに並ぶ。
const toolDefinition = {
  type: "function",
  name: "get_user_profile",
  description:
    "サインイン中ユーザー自身のプロフィール情報（氏名・メール・部署・勤務地など）を取得する。" +
    "ユーザーが『私の名前は？』『私のメールアドレスは？』など自分の情報を尋ねたときに使う。",
  parameters: {
    type: "object",
    properties: {
      fields: {
        type: "array",
        items: { type: "string", enum: PROFILE_FIELDS },
        description: "取得したい項目だけに絞りたい場合に指定する。省略時は全項目。",
      },
    },
    required: [],
    additionalProperties: false,
  },
};

// 指定された fields だけ抜き出す（不要な個人情報を AI に渡さない練習）。
// extra にはデータ源（mock / graph）などのメタ情報を付与する。
function pickFields(source, fields, extra = {}) {
  let picked = source;
  if (Array.isArray(fields) && fields.length > 0) {
    picked = {};
    for (const f of fields) {
      if (f in source) picked[f] = source[f];
    }
  }
  return { ...picked, ...extra };
}

// このツールを AI に渡してよいか（＝定義を tools 配列に含めるか）を判定する。
//   - Entra 未設定: モックで誰でも試せるよう、常に利用可
//   - Entra 設定済み: OBO サインイン済み（初回トークンを持つ）場合のみ利用可
function isAvailable(req) {
  if (!isConfigured) return true;
  return obo.hasOboSession(req);
}

// ツールの実体。AI が get_user_profile を呼んだときに実行される。
async function runGetUserProfile(req, args = {}) {
  // 未設定: モック応答（Graph を呼ばずに固定データを返す）
  if (!isConfigured) {
    return pickFields(MOCK_PROFILE, args.fields, { _source: "mock" });
  }
  // 設定済みだが OBO サインインしていない: ツール自体渡していないので通常ここには
  // 来ないが、念のため安全側で明示エラーを返す。
  if (!obo.hasOboSession(req)) {
    return { error: "OBO でサインインしていません。/auth/signin-obo からサインインして再度お試しください。" };
  }
  // 設定済み + OBO サインイン済み:
  //   ユーザー本人の初回トークン → OBO 交換 → Graph トークン → /me。
  //   サーバー ID ではなく、サインインしたユーザーの委任権限で Graph が呼ばれる。
  try {
    const graphToken = await obo.acquireGraphTokenViaObo(req.session.oboInitialToken);
    const data = await obo.fetchGraphMe(graphToken);
    return pickFields(data, args.fields, { _source: "graph-obo" });
  } catch (err) {
    console.error("[tool] OBO/Graph error:", err.response?.data || err.errorMessage || err.message);
    return {
      error:
        "OBO 交換または Graph 呼び出しに失敗しました（トークン失効の可能性。再サインインしてください）: " +
        (err.errorMessage || err.message || String(err)),
    };
  }
}

// 名前 → 実体のディスパッチ表（ツールが増えてもここに足すだけ）。
const handlers = {
  get_user_profile: runGetUserProfile,
};

// このリクエストで AI に渡すツール定義の配列を返す。
function toolsForRequest(req) {
  return isAvailable(req) ? [toolDefinition] : [];
}

// AI が呼んだツールを実行して結果（JSON 化可能なオブジェクト）を返す。
async function executeTool(req, name, args) {
  const handler = handlers[name];
  if (!handler) return { error: `未知のツール: ${name}` };
  return handler(req, args);
}

module.exports = { toolsForRequest, executeTool };
