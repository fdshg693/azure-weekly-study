// ============================================================================
// メモの永続化レイヤ（Azure Table Storage）
// ----------------------------------------------------------------------------
// 全ユーザー共有のメモを 1 つの Table に格納する CRUD ヘルパ。
//
// 接続方法は 2 通りを優先順位で切り替える（アプリ本体の OpenAI / Tavily と同じ「キーレス優先」思想）:
//   1. MEMO_STORAGE_ACCOUNT_URL があれば、それ + DefaultAzureCredential（キーレス）。
//      → Azure 上では Function のシステム割り当てマネージド ID が
//        "Storage Table Data Contributor" ロールで読み書きする。
//   2. 無ければ MEMO_STORAGE_CONNECTION_STRING（ローカル: Azurite の UseDevelopmentStorage=true）。
//
// データモデル:
//   - PartitionKey = "memo" 固定。共有メモなので全件を 1 パーティションに置き、
//     一覧取得（同一 PK の query）を単純化する。件数が多い用途では PK を分散させる。
//   - RowKey = メモ ID（時刻ベースのソート可能な文字列）。
//   - title / body / createdAt / updatedAt を持つ。
// ============================================================================

const { TableClient } = require("@azure/data-tables");
const { DefaultAzureCredential } = require("@azure/identity");

const TABLE_NAME = process.env.MEMO_TABLE_NAME || "memos";
// 共有メモは単一パーティションにまとめる（PK 固定）。
const PARTITION_KEY = "memo";

let _client = null;

// Table クライアントを 1 度だけ生成してキャッシュする。
// 初回アクセス時に Table が無ければ作成する（createTable は冪等で 409 を握りつぶす）。
async function getClient() {
  if (_client) return _client;

  const accountUrl = process.env.MEMO_STORAGE_ACCOUNT_URL;
  const connectionString = process.env.MEMO_STORAGE_CONNECTION_STRING;

  if (accountUrl) {
    // Azure 本番経路: キーを使わず Managed ID（DefaultAzureCredential）で接続。
    _client = new TableClient(accountUrl, TABLE_NAME, new DefaultAzureCredential());
  } else if (connectionString) {
    // ローカル経路: Azurite などへ接続文字列で接続。
    _client = TableClient.fromConnectionString(connectionString, TABLE_NAME, {
      // Azurite は v2 API のため、許可リストを緩めておく（既定で問題ないが明示）。
      allowInsecureConnection: true,
    });
  } else {
    throw new Error(
      "ストレージ接続が未設定です。MEMO_STORAGE_ACCOUNT_URL（Azure/MI）または MEMO_STORAGE_CONNECTION_STRING（ローカル/Azurite）を設定してください。"
    );
  }

  // Table が無ければ作る（既存なら 409 を無視）。
  await _client.createTable().catch((err) => {
    if (err.statusCode !== 409) throw err;
  });
  return _client;
}

// Table のエンティティ → API で返すメモ形へ正規化。
function toMemo(entity) {
  return {
    id: entity.rowKey,
    title: entity.title || "",
    body: entity.body || "",
    createdAt: entity.createdAt || null,
    updatedAt: entity.updatedAt || null,
  };
}

// ソート可能なメモ ID を生成する。時刻 + ランダムサフィックスで衝突を避けつつ作成順に並ぶ。
function newId() {
  const ts = new Date().toISOString().replace(/[^0-9]/g, ""); // 20260621T...　→ 数字のみ
  const rand = Math.random().toString(36).slice(2, 8);
  return `${ts}-${rand}`;
}

// 全メモを取得（作成が新しい順）。
async function list() {
  const client = await getClient();
  const items = [];
  const iter = client.listEntities({
    queryOptions: { filter: `PartitionKey eq '${PARTITION_KEY}'` },
  });
  for await (const entity of iter) {
    items.push(toMemo(entity));
  }
  // RowKey（時刻ベース）の降順 = 新しい順。
  items.sort((a, b) => (a.id < b.id ? 1 : -1));
  return items;
}

// 1 件取得。無ければ null。
async function get(id) {
  const client = await getClient();
  try {
    const entity = await client.getEntity(PARTITION_KEY, id);
    return toMemo(entity);
  } catch (err) {
    if (err.statusCode === 404) return null;
    throw err;
  }
}

// 新規作成。title は必須、body は任意。
async function create({ title, body }) {
  if (!title || !String(title).trim()) {
    const e = new Error("title は必須です");
    e.statusCode = 400;
    throw e;
  }
  const client = await getClient();
  const now = new Date().toISOString();
  const id = newId();
  const entity = {
    partitionKey: PARTITION_KEY,
    rowKey: id,
    title: String(title).trim(),
    body: body ? String(body) : "",
    createdAt: now,
    updatedAt: now,
  };
  await client.createEntity(entity);
  return toMemo(entity);
}

// 更新。渡された title / body だけを差し替える（部分更新）。無ければ null。
async function update(id, { title, body }) {
  const existing = await get(id);
  if (!existing) return null;
  const client = await getClient();
  const merged = {
    partitionKey: PARTITION_KEY,
    rowKey: id,
    title: title !== undefined ? String(title).trim() : existing.title,
    body: body !== undefined ? String(body) : existing.body,
    createdAt: existing.createdAt,
    updatedAt: new Date().toISOString(),
  };
  // mode "Replace" でエンティティ全体を置き換える（merged に全フィールドを入れてある）。
  await client.updateEntity(merged, "Replace");
  return toMemo(merged);
}

// 削除。存在しなくても 404 は握りつぶし、成功扱いにする（冪等）。
async function remove(id) {
  const client = await getClient();
  try {
    await client.deleteEntity(PARTITION_KEY, id);
    return true;
  } catch (err) {
    if (err.statusCode === 404) return false;
    throw err;
  }
}

module.exports = { list, get, create, update, remove };
