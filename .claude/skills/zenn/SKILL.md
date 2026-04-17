---
name: zenn
description: ZENN記事を作成するスキル
disable-model-invocation: false
user-invocable: true
---

以下の手順で ZENN 記事を作成してください。

重要:

- 外部情報の収集は、基本的にすべて `.claude\skills\use-tavily` 配下のスクリプトを使って行うこと。
- 一般的な WEB 検索ツールや曖昧なブラウズ指示ではなく、`use-tavily` スキルの各スクリプトを明示的に使い分けること。
- 既存知識だけで記事を書かないこと。概要提案の段階でも、調査が必要なら Tavily で最新情報を確認すること。
- どの工程でも、まず対象トピックに対して「何を知るための調査か」を明確にしてから検索・抽出を行うこと。

## 0. 事前確認

まず `.claude\skills\use-tavily\SKILL.md` を読み、このスキルを使う前提で進めてください。

利用する主なスクリプト:

- `src/search_topic.py`: キーワードから関連 URL を探す
- `src/search_extract_topic.py`: キーワードから関連 URL を探し、そのまま内容も抽出する
- `src/research_topic.py`: 調査タスクをまとめて Tavily に任せる
- `src/extract_url_content.py`: 既知の URL 群から内容を抽出する
- `src/map_site_titles.py`: 公式 Docs サイト内の URL 一覧とタイトルを把握する
- `src/map_extract_site_content.py`: サイトをマップしてから対象 URL の内容を抽出する
- `src/crawl_site_content.py`: 特定サイトを直接クロールして内容を集める

必要に応じて各スクリプトの `--help` も確認してください。

出力ファイルは基本的に `temp\web\` 以下へ保存してください。記事ごとにトピック名のスラッグを決め、以下のように整理します。

- `temp\web\search_{topic_slug}.json`
- `temp\web\research_{topic_slug}.json`
- `temp\web\extract_{topic_slug}.json`
- `temp\web\site_map_{topic_slug}.json`
- `temp\web\site_extract_{topic_slug}.json`

`topic_slug` は英数字と `_` を使った短い識別子に揃えてください。

## 1. 記事の概要を提案する

- テーマ、対象読者、前提知識、比較対象、扱うバージョンやサービス範囲が曖昧なら、概要提案の前にユーザーへ質問して内容を明確にすること。
- 特定のツール、ライブラリ、サービス、公式機能の紹介記事であれば、概要提案の前に軽く最新情報を確認すること。
- この段階では深掘りしすぎず、概要提案に必要な情報だけを収集すること。

### 1.a 軽い事前調査の基本パターン

まずは `search_topic.py` を使い、公式 Docs や GitHub がどこにあるかを確認してください。

例:

```powershell
python .\.claude\skills\use-tavily\src\search_topic.py "Azure API Management OpenAI integration" --detail balanced --include-domain learn.microsoft.com --include-domain github.com --output temp\web\search_apim_openai_overview.json
```

より「問い」に近いテーマで、概要までまとめてほしい場合は `research_topic.py` を使っても構いません。

例:

```powershell
python .\.claude\skills\use-tavily\src\research_topic.py "Azure API Management で Azure OpenAI を公開する設計上のポイントを整理してください。公式 Docs と Github を優先し、記事概要の判断に必要な最新論点をまとめてください。" --detail balanced --output temp\web\research_apim_openai_overview.json
```

### 1.b 概要提案時の出力要件

概要提案では少なくとも以下を含めてください。

- 記事タイトル案を 2 から 4 個
- 想定読者
- 記事で答える問い
- どこまで扱い、どこから扱わないか
- 概要提案の根拠にした主要 URL または調査ファイル

## 2. 概要提案が受け入れられたら、関連情報を収集する

既存知識だけで回答しようとしないでください。必ず Tavily を使って最新情報を収集してください。

この工程は以下の順で進めます。

1. 参考にすべき公式 Docs や GitHub を確定する
2. 参照候補 URL を一覧化する
3. 記事に必要な URL の内容を抽出する
4. 不足する論点だけ追加調査する

### 2.a サブエージェントに URL 候補の洗い出しをさせる

サブエージェントには「WEB検索して」とだけ言わず、`.claude\skills\use-tavily` を使うように明示してください。

サブエージェント指示例:

```markdown
`.claude\skills\use-tavily\SKILL.md` を先に読んでください。

{keyword1 keyword2 ...} に関する最新の情報を収集してください。
一般的な WEB 検索ツールではなく、`.claude\skills\use-tavily\src\search_topic.py` または必要に応じて `src\research_topic.py` を使ってください。

まずは参考になる公式 Docs や GitHub を確定させてください。
そのうえで、公式 Docs を中心に参照すべき URL とそれらのタイトルを整理し、`temp\web\search_{keyword1_keyword2_...}.md` に保存してください。(スクリプトの出力をそのまま使うのでなく、スクリプトの結果を元に不要箇所の削除等を行い、読みやすい形に整形してください)

可能なら include-domain を使って公式ドメインを優先してください。
最終報告では以下を返してください。

- 実行したコマンド
- 確定した主要ドメイン
- 重要 URL 一覧
- 出力ファイルパス
```

推奨コマンド例:

```powershell
python .\.claude\skills\use-tavily\src\search_topic.py "Azure API Management policy expressions" --detail balanced --include-domain learn.microsoft.com --include-domain github.com --output temp\web\search_apim_policy_expressions.json
```

広めに調査して論点整理も必要なら:

```powershell
python .\.claude\skills\use-tavily\src\research_topic.py "Azure API Management policy expressions の最新情報を整理してください。公式 Docs と Github を優先し、記事執筆で先に読むべき資料を洗い出してください。" --detail balanced --output temp\web\research_apim_policy_expressions.json
```

### 2.b URL 候補から、読むべき資料を特定する

`search_*.json` や `research_*.json` を読み、記事を書くために本文まで確認すべき URL を選定してください。

選定の基準:

- 公式 Docs である
- バージョンや公開日が新しい、または現行仕様を説明している
- 概要ページだけでなく、実装や制約が書かれている
- 記事の各セクションに直接使える

### 2.c URL 内容の取得方法を使い分ける

URL がすでに決まっている場合は `extract_url_content.py` を使ってください。

例:

```powershell
python .\.claude\skills\use-tavily\src\extract_url_content.py https://learn.microsoft.com/azure/api-management/api-management-policies https://learn.microsoft.com/azure/api-management/api-management-policy-expressions --query "APIM policy で何ができるか、制約、実務上重要な注意点" --detail balanced --output temp\web\extract_apim_policies.json
```

キーワードから候補 URL の抽出まで含めて一気に行いたい場合は `search_extract_topic.py` を使ってください。

例:

```powershell
python .\.claude\skills\use-tavily\src\search_extract_topic.py "Azure API Management policy expressions limitations" --detail balanced --include-domain learn.microsoft.com --output temp\web\extract_apim_policy_limitations.json
```

公式 Docs サイト全体の構造を先に見たい場合は `map_site_titles.py` を使ってください。

例:

```powershell
python .\.claude\skills\use-tavily\src\map_site_titles.py https://learn.microsoft.com/azure/api-management/ --detail balanced --select-domain learn.microsoft.com --select-path "/azure/api-management/.*" --output temp\web\site_map_apim_docs.json
```

特定サイトから関連ページ本文をまとめて収集したい場合は `map_extract_site_content.py` を使ってください。

例:

```powershell
python .\.claude\skills\use-tavily\src\map_extract_site_content.py https://learn.microsoft.com/azure/api-management/ --query "self-hosted gateway architecture, limitations, pricing-related considerations" --detail balanced --select-domain learn.microsoft.com --select-path "/azure/api-management/.*" --output temp\web\site_extract_apim_gateway.json
```

サイト全体を直接クロールしたい場合は `crawl_site_content.py` を使ってください。対象サイトが限定されていて、関連情報を広く拾いたい場合に向いています。

例:

```powershell
python .\.claude\skills\use-tavily\src\crawl_site_content.py https://learn.microsoft.com/azure/api-management/ --query "workspace feature, v2 tiers, current limitations" --detail balanced --select-domain learn.microsoft.com --select-path "/azure/api-management/.*" --output temp\web\site_crawl_apim_workspace.json
```

### 2.d 追加調査の原則

- 情報が足りない論点だけ追加で検索すること
- 追加調査も `use-tavily` のスクリプトを使うこと
- 追加検索のたびに、何を確認したかったかを明示すること
- 同じ URL を何度も雑に取得せず、必要ならクエリを変えて抽出し直すこと

## 3. 記事の構成を提案する

- 2 で収集した情報をもとに、記事の構成を提案してください。
- 構成だけでなく、各セクションの概要も記述してください。
- それぞれのセクションで参考にすべき URL を示してください。
- 可能であれば、どの収集ファイルを根拠にしたかも併記してください。
- **記事は、`zenn\plan`配下のファイルとして出力してください。**
  - こうすることで、ユーザーがコメントをつけやすくなります。

構成提案には少なくとも以下を含めてください。

- 仮タイトル
- 導入で解決する問題
- セクション一覧
- 各セクションで述べる主張
- 各セクションの根拠 URL
- 必要なら不足情報と追加調査ポイント

構成提案の時点で、各セクションに対応する「読むべき URL」が不足しているなら、記事執筆に進まず先に追加調査してください。

## 4. 問題なければ記事を作成する

- 3 で提案した構成をもとに記事を作成してください。
  - `zenn\publish`配下のファイルとして出力してください。
- 収集済みの資料を根拠にして書き、根拠が薄いことを推測で埋めないでください。
- 必要に応じてサブエージェントを使い、セクション単位で下書きを作らせてください。
- サブエージェントにも、一般的な WEB 検索ではなく `use-tavily` のスクリプトを使う方針を守らせてください。

### 4.a セクション下書きをサブエージェントに任せる場合の指示例

```markdown
`.claude\skills\use-tavily\SKILL.md` を先に読んでください。

以下の Zenn 記事セクションの下書きを作成してください。

- セクション名: {section_title}
- 記事全体のテーマ: {article_theme}
- このセクションで答える問い: {section_goal}
- 主に参照するファイル: {temp\web\...json}
- 主に参照する URL: {url1, url2, ...}

まずは指定された JSON 調査結果と URL を読み、根拠を確認してください。
根拠が不足する場合のみ、`.claude\skills\use-tavily\src\extract_url_content.py` または `src\search_extract_topic.py` を使って追加調査してください。
一般的な WEB 検索ツールは使わないでください。

出力では以下を返してください。

- セクション下書き本文
- 根拠として使った URL 一覧
- 追加調査した場合はそのコマンドと出力ファイル
- 不確実な点
```

### 4.b 記事執筆時の品質基準

- 公式資料に基づく説明を優先する
- 読者にとっての判断材料になる比較や制約を落とさない
- 「できること」だけでなく「向いていないケース」「制約」「設計上の注意点」も書く
- 概要ページだけでなく、実装ページや制約ページに当たって確認する
- 日付やプレビュー状況、SKU 依存、リージョン依存などの変動要素があれば明記する

## 5. 推奨ワークフローのまとめ

1. テーマが曖昧なら先に質問する
2. `.claude\skills\use-tavily\SKILL.md` を読む
3. `search_topic.py` または `research_topic.py` で概要提案に必要な最新情報を集める
4. 概要提案を出す
5. 承認後、`search_topic.py` / `research_topic.py` で主要 URL 候補を確定する
6. `extract_url_content.py` / `search_extract_topic.py` / `map_extract_site_content.py` / `crawl_site_content.py` を使って本文根拠を集める
7. 構成案を出す
8. セクションごとの根拠 URL を揃える
9. サブエージェントも活用しつつ記事本文を書く

## 6. 禁止事項

- 外部情報が必要なのに、既存知識だけで断定して書かないこと
- 「WEB検索した」とだけ書いて、何をどう調べたか曖昧にしないこと
- 一般的な WEB 検索ツールを優先しないこと
- 公式ソースがあるのに、非公式ブログだけを根拠にしないこと
- 根拠 URL が不足したまま構成や本文を書き進めないこと