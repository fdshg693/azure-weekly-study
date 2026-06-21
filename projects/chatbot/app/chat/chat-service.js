// ============================================================================
// チャット処理のドメインロジック
// ----------------------------------------------------------------------------
// /chat ルートから HTTP の関心事（req/res）を切り離した「会話生成そのもの」を担う。
//   - 履歴のサニタイズ／検証
//   - Responses API への問い合わせ
//   - モデルがツールを呼んだら実行し、結果を返して再生成するループ
// ルート側は入出力の整形だけを行い、ここのロジックを呼ぶ。
// ============================================================================

const tools = require("../tools");
const { getChatModel } = require("../config/models");
const { getClient } = require("./openai-clients");

const SYSTEM_PROMPT =
  "あなたは親切で簡潔に答える日本語アシスタントです。" +
  "ユーザーが自分自身の情報（氏名・メール・部署・勤務地など）を尋ねたら、" +
  "get_user_profile ツールが使える場合はそれを呼び出して正確に答えてください。" +
  "ツールが使えない場合は、サインインすると自分の情報を取得できる旨を案内してください。" +
  "最新の情報や事実確認が必要なとき、Web 検索系のツール（Tavily）が使える場合は" +
  "それを使って調べてから答えてください。" +
  "全ユーザー共有のメモの操作（一覧・作成・更新・削除）を頼まれたら、memo 系ツール" +
  "（list_memos / create_memo / update_memo / delete_memo）を使ってください。" +
  "更新・削除のときは先に list_memos で対象の id を確認してから実行してください。";

const MAX_HISTORY = 40;
// ツール呼び出し → 結果を返して再生成、のループ上限（暴走防止）。
const MAX_TOOL_ROUNDS = 5;

// クライアントから来た履歴を信頼できる形に整える。
//   - user / assistant の文字列メッセージだけ残す（role 詐称や余計なフィールドを排除）
//   - 直近 MAX_HISTORY 件に切り詰める（トークン暴発を防ぐ）
function sanitizeHistory(messages) {
  const history = Array.isArray(messages) ? messages : [];
  return history
    .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .slice(-MAX_HISTORY)
    .map((m) => ({ role: m.role, content: m.content }));
}

// サニタイズ後の履歴が会話として成立しているか検証する。
// 成立していなければ理由（文字列）を返し、問題なければ null。
function validateHistory(sanitized) {
  if (sanitized.length === 0 || sanitized[sanitized.length - 1].role !== "user") {
    return "最後のメッセージは user である必要があります";
  }
  return null;
}

// 会話履歴から AI の応答テキストを生成する。
//   req       : ツールの出し分け／実行に使う（サインイン状態などを参照）
//   sanitized : sanitizeHistory 済みのメッセージ配列
//   modelId   : 画面で選択されたモデル id（未指定・不正は既定モデルにフォールバック）
async function generateReply({ req, sanitized, modelId }) {
  // 画面で選択されたモデルを解決する。未指定・不正な id は既定モデルにフォールバック。
  const selected = getChatModel(modelId);
  const { deployment, reasoningEffort } = selected;
  const openai = getClient(selected.id);

  // Responses API の input 配列。Chat Completions の messages とほぼ同じ形だが、
  // ツール呼び出し（function_call）と結果（function_call_output）も同じ配列に積んでいく。
  const input = [{ role: "system", content: SYSTEM_PROMPT }, ...sanitized];

  // ログイン状態に応じて、この会話で AI に渡すツールを出し分ける。
  // Tavily キーを Key Vault から取得する場合があるため await する。
  const availableTools = await tools.toolsForRequest(req);

  // Responses API のリクエスト本体。reasoning は推論モデルのときだけ付ける
  // （非推論モデルに reasoning を渡すとエラーになるため）。
  const buildParams = (input) => {
    const params = { model: deployment, input, tools: availableTools };
    if (reasoningEffort) params.reasoning = { effort: reasoningEffort };
    return params;
  };

  let response = await openai.responses.create(buildParams(input));

  // モデルがツールを呼んだら実行し、結果を返して再度生成させるループ。
  for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
    const calls = response.output.filter((o) => o.type === "function_call");
    if (calls.length === 0) break;

    // モデルの出力（function_call を含む）をそのまま会話に積み戻す。
    input.push(...response.output);

    // 各ツール呼び出しを実行し、結果を function_call_output として追加。
    for (const call of calls) {
      let args = {};
      try {
        args = call.arguments ? JSON.parse(call.arguments) : {};
      } catch (_) {
        args = {};
      }
      const result = await tools.executeTool(req, call.name, args);
      console.log(`[tool] ${call.name}(${call.arguments || "{}"}) -> ${JSON.stringify(result)}`);
      input.push({
        type: "function_call_output",
        call_id: call.call_id,
        output: JSON.stringify(result),
      });
    }

    response = await openai.responses.create(buildParams(input));
  }

  // output_text は最終的なテキスト出力を結合してくれる便利プロパティ。
  return response.output_text || "";
}

module.exports = { sanitizeHistory, validateHistory, generateReply };
