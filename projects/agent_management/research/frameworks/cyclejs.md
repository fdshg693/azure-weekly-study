# Cycle.js（フロントエンド）— 蓄積ナレッジ

> このファイルは **Cycle.js について「分かったこと」を貯める唯一の場所**。
> 実装前に必ずここを読み、Web 検索や本体読みで新たに分かったことは**ここへ追記**する（再調査の防止）。
> 原則: **見つけるのは Web 検索（Tavily）／正確さはローカルコピー**（[../README.md](../README.md) の方針）。

## 概要

- 「**人とコンピュータの循環（cycle）」をストリームで表現する FRP フレームワーク**。
  `main(sources) → sinks` という純粋関数を書き、**副作用はすべて「ドライバ」**（DOM/HTTP 等）に追い出す。
- 中核概念は 4 つ:
  - **ストリーム**（`xstream` が既定。RxJS でも可）
  - **ドライバ**（副作用のプラグイン。`makeDOMDriver` / `makeHTTPDriver`。**自作できる**＝SSE 中継の鍵）
  - **MVI（Model-View-Intent）**：intent（イベント→action）→ model（state）→ view（VDOM）
  - **state / isolate**（`@cycle/state` のオニオン状態、コンポーネント分離）
- VDOM は Snabbdom。`div([...])` のようなハイパースクリプトで書く。

## ローカルコピー（＝正・最優先で読む）

本体リポジトリのコピー: [`../../cyclejs/`](../../cyclejs/)

- ドキュメント Markdown: `cyclejs/docs/content/documentation/`
  - `getting-started.md` / `streams.md` / `model-view-intent.md` / `components.md` / `drivers.md` / `dialogue.md` / `basic-examples.md`
- API リファレンス Markdown: `cyclejs/docs/content/api/`
  - `run.md` / `dom.md` / `http.md` / `state.md` / `isolate.md` / `history.md`
- サンプル: `cyclejs/examples/basic/`（hello-world→checkbox→counter→http-random-user→bmi-naive の順が推奨）、
  `cyclejs/examples/advanced/autocomplete-search/`（HTTP＋非同期 UI の実戦例。チャット UI の参考）

## 最小例（ローカル `examples/basic/counter/src/main.js` より）

```js
const action$ = xs.merge(
  sources.DOM.select('.decrement').events('click').map(() => -1),
  sources.DOM.select('.increment').events('click').map(() => +1)
);
const count$ = action$.fold((acc, x) => acc + x, 0);   // model
const vdom$ = count$.map(count => div([ ... ]));        // view
return { DOM: vdom$ };                                  // sink
```

HTTP は sink にリクエストを流し、`sources.HTTP.select(category).flatten()` で応答を受ける
（`examples/basic/http-random-user/src/index.ts`）。

## 確認済みの事実（出典つき。新たに分かったら追記）

| # | 事実 | 出典 |
|---|---|---|
| C1 | エコシステムは成熟・停滞気味。2025 のフレームワーク動向ではほぼ言及されない | Tavily `agent_mgmt_research/0001` |
| C2 | ローカル本体は古い（TS 3.2.4 / RxJS 6 / Node 8 想定） | `cyclejs/package.json`・`tsconfig.common.json` |
| C3 | SSE は `@cycle/http`（一発応答型）では素直に扱えない。`EventSource` のカスタムドライバ自作が筋 | `cyclejs/docs/content/documentation/drivers.md`・[../decisions/01-open-decisions.md](../decisions/01-open-decisions.md) B-2 |

## 本プロジェクトでの方針（決定済み）

- **アプリ依存は最新を npm で別途取得**（`@cycle/run` / `@cycle/dom` / `@cycle/http` / `@cycle/state` / `xstream`）＋ Vite でバンドル。
  ローカルコピーは**ドキュメント・サンプル参照専用**にする（[../decisions/01-open-decisions.md](../decisions/01-open-decisions.md) E-3）。
- CRUD フォーム・一覧・選択の状態は `@cycle/state`（onionify）で土台を組む（[../decisions/02-architecture-review.md](../decisions/02-architecture-review.md) 2.）。
- ストリーミングは MVP では非対応。やるなら `EventSource` のカスタムドライバ自作を独立回に（同 B）。

## 参考 URL

- 公式: <https://cycle.js.org/> ／ Getting started: <https://cycle.js.org/getting-started.html>
- ドライバ自作: <https://cycle.js.org/drivers.html>
- `@cycle/state`: <https://cycle.js.org/api/state.html>
- xstream: <https://github.com/staltz/xstream>

## 未調査・次に確認したいこと（TODO）

- [ ] 最新版（npm）と本体コピー（古い）の API 差分（`@cycle/state` の onionify 周りで非互換がないか）
- [ ] Vite + TypeScript での最小 scaffold 構成（実装時に確定）
- [ ] `EventSource` カスタムドライバの最小実装例（発展課題に着手するとき）
