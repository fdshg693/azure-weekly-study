# IaC：Bicep — 蓄積ナレッジ

> このファイルは **本プロジェクトの IaC（Bicep）まわりで「分かったこと」を貯める場所**。
> Bicep 自体は既習トピック多数。深掘りは既存の `learn/*` の Bicep を正とする。

## 概要・方針（決定済み）

- IaC は **Bicep**（このリポジトリの Azure リソース構築の主流。auth/network/vm/db/k8s/container が Bicep）。
- Bicep で作る範囲: **AIServices アカウント（kind=AIServices）＋ Foundry プロジェクト＋モデルデプロイ
  （AOAI、既定 `gpt-4.1-mini` 等）＋ PostgreSQL Flexible Server ＋ ロール割当**
  （[../decisions/01-open-decisions.md](../decisions/01-open-decisions.md) C-3）。

## 今回の新規ポイント（既習との差分）

- **`Microsoft.Authorization/roleAssignments`（Foundry User ロール付与）を Bicep に内包**する。
  → `learn/foundry/prompt_agent` では「ロール割当だけ `az` 頼り」だったのを解消できる
  （[../decisions/01-open-decisions.md](../decisions/01-open-decisions.md) C-2）。

## 既習資産（リポジトリ内＝最優先で流用）

- `learn/db/simple/` … PostgreSQL Flexible Server の Bicep。
- `learn/foundry/prompt_agent/00_provision.py` … AIServices アカウント＋プロジェクト＋デプロイのリソース構成。
  **Python で書かれた構成を Bicep に翻訳する**形で下敷きにする。

## 確認済みの事実

| # | 事実 | 出典 |
|---|---|---|
| B1 | mgmt SDK はロール割当 API を持たず `az` 頼りだったが、Bicep ならネイティブに書ける | [../decisions/02-architecture-review.md](../decisions/02-architecture-review.md) 5.・[../decisions/01-open-decisions.md](../decisions/01-open-decisions.md) C-2 |

## 未調査・次に確認したいこと（TODO）

- [ ] AIServices＋Foundry プロジェクト＋デプロイの Bicep リソースタイプ／API バージョンの確定
- [ ] ロール割当の `principalId`（自分）をどう Bicep に渡すか（パラメータ化）
- [ ] モデルデプロイの容量（capacity/SKU）の最小設定
