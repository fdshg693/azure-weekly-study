# research — 事前調査と蓄積ナレッジ

`agent_management`（Foundry Agent の CRUD・チャットができる WEB アプリ）の実装を支える調査置き場。
**2 種類のファイル**を明確に分けて置く。混ぜないことが「同じ調査の繰り返し」を防ぐ鍵。

```text
research/
├── decisions/    … 時点の判断・レビュー（一度書いたらほぼ更新しない。実装方針の「なぜ」）
└── frameworks/   … フレームワークごとの蓄積ナレッジ（読む前に必ず見る／調べたら必ず追記する）
```

## フォルダの中身

### `decisions/` — 時点の判断（point-in-time）

スタックを選んだ理由・論点・トレードオフを記録する。**過去の意思決定の記録**であり、頻繁には更新しない。

| ファイル | 内容 | これを見ると分かること |
|---|---|---|
| [decisions/01-open-decisions.md](./decisions/01-open-decisions.md) | 実装前に確定したい論点一覧（推奨つき） | 何を先に決めれば手戻りしないか |
| [decisions/02-architecture-review.md](./decisions/02-architecture-review.md) | スタックの妥当性レビュー（不自然な箇所＋代替案） | 「PostgreSQL は何を保存するのか」など構造的な疑問の答え |

### `frameworks/` — フレームワークごとの蓄積ナレッジ（accumulating）

**1 フレームワーク＝1 ファイル**。各フレームワークについて分かったことを**ここだけに貯める**。
これが本フォルダの主役で、再調査を防ぐ仕組みそのもの。

| ファイル | ローカルコピー | 深掘りの主手段 |
|---|---|---|
| [frameworks/cyclejs.md](./frameworks/cyclejs.md) | [`../cyclejs/`](../cyclejs/) あり | ローカルコピー（docs/examples）＋ Tavily |
| [frameworks/azure-ai-projects.md](./frameworks/azure-ai-projects.md) | [`../azure-ai-projects/`](../azure-ai-projects/) あり | ローカルコピー（samples/subclients.md）＋ Tavily |
| [frameworks/fastapi.md](./frameworks/fastapi.md) | なし | 公式ドキュメント＋ Tavily |
| [frameworks/postgresql.md](./frameworks/postgresql.md) | なし（既習 `learn/db/simple`） | 既習資産＋公式 |
| [frameworks/bicep.md](./frameworks/bicep.md) | なし（既習 `learn/*`） | 既習資産＋公式 |

各 `frameworks/*.md` は共通テンプレ:
**概要 / ローカルコピーの場所 / 確認済みの事実（出典つき表）/ 本プロジェクトでの方針 / 参考 URL / 未調査・TODO**。

## 運用ルール（これを守れば調査が重複しない）

フレームワークの挙動・API を知りたくなったら、毎回この順で動く:

1. **まず `frameworks/<name>.md` を読む。** 「確認済みの事実」に答えがあれば、それ以上調べない。
2. 載っていなければ、**ローカルコピー**（[`../cyclejs/`](../cyclejs/) / [`../azure-ai-projects/`](../azure-ai-projects/)）を読む。
   → **推測でコードを書かない。** SDK の引数・戻り値はサンプル／`docs/subclients.md` で必ず裏取りする。
3. ローカルに無い／Web で広く当たりたいときだけ **Tavily**（`use-tavily` スキル）を使う。
4. **分かったことは必ず該当 `frameworks/<name>.md` の「確認済みの事実」表に追記する**（出典つき）。
   調べ終わって TODO が解消したらチェックを外す／消す。
   → これをやらないと次回また同じ調査をする。追記までが 1 回の調査。

> 詳しい根拠と入口の地図は CLAUDE.md（プロジェクト直下）にもまとめてある。迷ったらそちらも参照。

## Tavily の出力先

実行結果は `<TAVILY_OUTPUT_DIR>/agent_mgmt_research/` に保存される
（この環境では `.env` 解決で `C:\CodeRoot\ZENN\temp\web\agent_mgmt_research\`）。
`frameworks/*.md` の出典欄では `agent_mgmt_research/NNNN` の連番で参照している。

> メモ: 出力先がリポジトリ外（`C:\CodeRoot\ZENN\...`）に解決されている。Git 管理に含めたい場合は
> `.env` の `TAVILY_OUTPUT_DIR` をこのプロジェクト配下に向ける選択もある
> （[decisions/01-open-decisions.md](./decisions/01-open-decisions.md) の検討対象）。
