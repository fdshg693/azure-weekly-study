# CLAUDE.md — agent_management 作業ガイド

このファイルは **このプロジェクトで作業する CLAUDE 向けの道しるべ**。
README に書いてある「何を作るか」は繰り返さない。ここに書くのは
**①フォルダ／ファイルの探し方** と **②フレームワーク調査の鉄則** の 2 つ。

---

## 0. 着手前にこれだけ読む

順に開けば、この時点での設計判断をすべて追える。

1. [README.md](./README.md) … 全体像とフォルダ地図
2. [research/README.md](./research/README.md) … 調査の運用ルール（下の §2 と対）
3. [rough/mvp/README.md](./rough/mvp/README.md) … **確定した MVP（正本）**
4. [imple/README.md](./imple/README.md) … 実装順・設計・スキーマ

> 設計の「正本」は層で違う。**確定事項＝`rough/mvp/`**、**実装粒度の設計＝`imple/`**、
> **論点の背景＝`research/decisions/`**、**FW の事実＝`research/frameworks/`**。
> 食い違ったらこの優先で、かつ上位（rough）を直してから下位に反映する。

---

## 1. フォルダ／ファイルの探し方

| 知りたいこと | 見る場所 |
|---|---|
| プロジェクトの方針・確定した設定 | [rough/mvp/README.md](./rough/mvp/README.md)（論点表 A-1〜F-2） |
| データの所在・DB スキーマ・REST API 契約・SDK マッピング | [imple/common-schema-api.md](./imple/common-schema-api.md) |
| 全体設計・認証・設定・フォルダ構成・用語 | [imple/common-architecture.md](./imple/common-architecture.md) |
| 実装の手順（step 1〜5） | [imple/step-*.md](./imple/) |
| 「なぜこのスタック／この役割か」の背景 | [research/decisions/](./research/decisions/) |
| **あるフレームワークの API・挙動・確認済みの事実** | **[research/frameworks/&lt;name&gt;.md](./research/frameworks/)** |
| Cycle.js の実コード・ドキュメント | ローカルコピー [cyclejs/](./cyclejs/)（`docs/content/`・`examples/`） |
| Foundry SDK の実コード・API 一覧 | ローカルコピー [azure-ai-projects/](./azure-ai-projects/)（`samples/`・`docs/subclients.md`） |

注意:

- **`cyclejs/` と `azure-ai-projects/` は外部リポジトリのコピー。原則編集しない**（参照専用）。
  アプリの依存は別途 npm / pip で最新を取る（[research/frameworks/cyclejs.md](./research/frameworks/cyclejs.md) の方針）。
- ファイル全文を端から読むより、上の表で当たりをつけてから対象だけ読む。

---

## 2. フレームワーク調査の鉄則（最重要）

**フレームワーク（Cycle.js / Foundry SDK / FastAPI 等）を推測で実装しない。** 必ず裏取りする。
調べ方には優先順位があり、調べた結果は必ず蓄積する。これを破ると同じ調査を何度も繰り返すことになる。

### 調べる順序

1. **まず [research/frameworks/&lt;name&gt;.md](./research/frameworks/) の「確認済みの事実」を読む。**
   そこに答えがあれば、それ以上調べない。
2. 無ければ **ローカルの同梱コピーを読む（最も正確）**。
   - Cycle.js → [cyclejs/](./cyclejs/) の `docs/content/`（解説）・`examples/`（動くコード）
   - Foundry SDK → [azure-ai-projects/](./azure-ai-projects/) の `samples/`（実コード）・`docs/subclients.md`（全 API 一覧）
   - **SDK の引数・戻り値・イベント型は、サンプルで現物を見るまで確定しない。** 記憶や推測で書かない。
3. ローカルに無い／Web で広く当たりたいときだけ **Tavily を使う**。
   - **必ず `use-tavily` スキル（`.claude/skills/use-tavily`）の作法に従う**。生 HTTP 取得や素のスクリプト直叩きをしない。
   - 出力は `--topic agent_mgmt_research` に集約する（既存の調査と同じトピックに貯める）。
   - 迷ったら `tav search`、URL が分かっているなら `tav extract`（スキル内の判断フロー参照）。

### 調べたら必ず追記する（蓄積＝再調査防止）

- 分かったことは **該当 [research/frameworks/&lt;name&gt;.md](./research/frameworks/) の「確認済みの事実」表に出典つきで追記**する。
  出典はローカルパス（例 `azure-ai-projects/samples/...`）か Tavily 連番（例 `agent_mgmt_research/0005`）。
- 解消した「未調査・TODO」はチェック／削除する。**追記までやって 1 回の調査が完了**。
- 1 フレームワーク＝1 ファイル。新しいフレームワークを足すときは同じテンプレ
  （概要 / ローカルコピー / 確認済みの事実 / 方針 / 参考 URL / 未調査・TODO）で `frameworks/` に新規作成する。

---

## 3. research フォルダの整理方法（ルールの所在）

`research/` は **`decisions/`（時点の判断・更新しない）** と
**`frameworks/`（FW ごとの蓄積・調べたら追記）** の 2 系統に分ける。
詳細な運用は [research/README.md](./research/README.md) が正本。**FW を調べる前後では必ずそのルールに従う**こと。

---

## 4. 実装に入るときの順守事項（リポジトリ CLAUDE.md の再掲ポイント）

- ルート CLAUDE.md の規約に従う（python は共有 `.venv`＋各 `requirements.txt`、`.env`/`.env.example`、
  複雑なら justfile でなく **Taskfile**、明示指示が無い限り**実デプロイしない**）。
- このプロジェクトは複数プロセス起動（Docker DB＋uvicorn＋Vite）なので **Taskfile** を使う（[rough/mvp/README.md](./rough/mvp/README.md) E-2）。
- 新出概念は実装時に `KNOWLEDGE.md`（未作成）へ。`projects/` 直下なので `learn/{topic}/CLAUDE.md` の対象外。
