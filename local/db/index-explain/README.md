# index-explain — インデックスと実行計画（`EXPLAIN ANALYZE`・Seq Scan vs Index Scan）

`local/db/PLAN.md` の **案1（パフォーマンス）**。同じ結果を返すクエリでも、**DB がデータをどう探すか**で
速度は桁違いに変わる。その「探し方」を実行計画（`EXPLAIN`）で読み、インデックスが**効く条件／効かない条件**を
設定の出し入れで切り分ける。

> 学び方は `local/docker` / `learn/network` 流 ―― **まず一般概念 → 実装 → 設定を出し入れして因果を確かめる**。
> 構築・実行・観察はあなた自身が手元の Docker で行う。
>
> 立ち位置: マネージド DB（[../../../learn/db/PLAN.md](../../../learn/db/PLAN.md)）でも「インデックスを貼る」操作自体は
> できるが、**プランナが何を選んだか・なぜ Seq Scan に落ちたか**を生の `EXPLAIN (ANALYZE, BUFFERS)` で
> 突き合わせる場所はここ。「貼ったのに速くならない」を計画から説明できるようになるのが狙い。

## 前提

- Docker（Docker Desktop など）が動いていること。`docker version` が通れば OK。
- `just` が入っていること（このリポジトリの他プロジェクトと同じ）。
- `.env` を用意する: `Copy-Item .env.example .env`（ポート 5432 が埋まっていれば `HOST_PORT` を変更）。

## 一般概念（まず言葉から）

| 用語 | ざっくり |
|------|----------|
| **実行計画 (query plan)** | DB がそのクエリをどう実行するか決めた手順。`EXPLAIN` で見える。 |
| **Seq Scan（順次走査）** | テーブルを**先頭から全部**読む。絞り込みが緩い／索引が無いとき。 |
| **Index Scan** | インデックスを辿って該当行だけ拾う。よく絞れるときに速い。 |
| **Bitmap Index Scan** | インデックスで「該当ページの地図」を作ってからまとめて読む中間策。 |
| **選択性 (selectivity)** | 条件がどれだけ絞るか。`user_id=42` は高選択性、`status='paid'` は低選択性。 |
| **複合インデックスの先頭列規則** | `(a,b)` のインデックスは `a` から指定しないと使えない。 |
| **カバリングインデックス** | 必要な列を索引に同梱（`INCLUDE`）→ 本体を読まず **Index Only Scan**。 |

ポイントは **インデックスは「読みを速くする代わりに、書き込み時に維持コストを払う」装置**であり、
**常に効くわけではない**こと。効くかどうかはプランナが「選択性 × コスト」で判断する。

## セットアップ

```pwsh
just up      # PostgreSQL を起動（healthy になるまで待つ）
just seed    # 300万行を投入（数十秒。\timing で所要が出る）
just q "SELECT count(*) FROM events;"
```

`EXPLAIN (ANALYZE, BUFFERS)` の読みどころ:
- 先頭ノード名 … `Seq Scan` / `Index Scan` / `Index Only Scan` / `Bitmap Heap Scan`。
- `actual time=... rows=...` … 実測の所要時間と返した行数。
- `Buffers: shared hit/read=...` … 実際に読んだブロック数。**ここが減れば仕事量が減った証拠**。

> 補足: 並列ワーカーが付くと `Parallel Seq Scan` などと出る。挙動の本質は同じ。
> ノードや行数の見方に集中したいときは対話セッションで `SET max_parallel_workers_per_gather = 0;` してもよい。

## 実験（出し入れ検証）

### 実験1: Seq Scan ⇄ Index Scan（PLAN 検証①）

```pwsh
just e1-baseline   # インデックス無し → Seq Scan。time と Buffers を記録
just e1-index      # user_id にインデックス → Index Scan に変わり激減
just e1-drop       # 外す → Seq Scan に戻る
```

同じ `WHERE user_id = 42` が、**インデックスを貼るか外すかだけ**で `Seq Scan ⇄ Index Scan` と切り替わり、
`actual time` と `Buffers` が桁で動く。速くしているのが**そのインデックス**だと切り分けられる。

### 実験2: 低選択性だと、貼っても使われない

```pwsh
just e2-lowselectivity   # status にインデックスを貼って EXPLAIN → それでも Seq Scan
```

`status='paid'` は全体の約25%を返す。これだけ多いと「索引を辿る」より「全部読む」方が安いと
プランナが判断し、**インデックスがあっても Seq Scan**。インデックス＝万能ではない、を体感する。

### 実験3: 複合インデックスの先頭列規則（PLAN 検証②）

```pwsh
just e3-create       # (user_id, amount) を作成
just e3-leading      # WHERE user_id=42        → 効く（Index Scan）
just e3-nonleading   # WHERE amount=500.00     → 効かない（Seq Scan）
just e3-prove        # amount 単独の索引を足すと amount 条件が Index Scan に → 原因は列順だったと確定
```

`(user_id, amount)` は先頭列 `user_id` から指定したときだけ使える。`amount` は高選択性なのに
単独では使われず Seq Scan に落ちる。`e3-prove` で「amount だからではなく**先頭列規則**」と裏づける。

### 実験4: カバリングインデックスで Index Only Scan

```pwsh
just e4-plain      # (user_id) のみ → Index Scan ＋ Heap Fetches あり（本体を読む）
just e4-covering   # (user_id) INCLUDE (amount) → Index Only Scan（Heap Fetches 激減）
```

取得列が索引に揃うと、テーブル本体に行かない `Index Only Scan` になる。`Heap Fetches:` の値が
落ちることで「本体を読まなくなった」と分かる（`seed` の `VACUUM` で可視性マップが立っているのが前提）。

### 実験5: LIKE は前方一致なら効く・後方一致は効かない

```pwsh
just e5-index    # email を text_pattern_ops で索引（前方一致が効くように）
just e5-prefix   # LIKE 'user123%'      → Index Scan
just e5-suffix   # LIKE '%23@example.com' → 索引があっても Seq Scan
```

前方一致は「先頭が決まる」ので B-tree の範囲に変換できる。後方一致は先頭が決まらず使えない
（部分一致を速くしたいなら `pg_trgm` など別の仕組みが要る、という次への伏線）。

### 実験6: 列に関数を噛ませると効かない → 式インデックスで救う

```pwsh
just e6-baseline   # email に索引があっても lower(email)=... は Seq Scan
just e6-fix        # 式インデックス lower(email) を貼ると Index Scan
```

条件側で列を加工すると「列そのものの索引」とは別物になり使えない。よくある落とし穴で、
対策は加工後の値に索引する**式インデックス**。

## 状態確認・後片付け

```pwsh
just indexes   # 今ある自作インデックス一覧
just reset     # 実験で作った索引を全削除（主キーだけに戻す）
just down      # コンテナ＋ボリュームごと破棄（データも消える）
```

ローカル完結なので課金は無いが、ボリュームはディスクに残る。終わったら `just down`。

## まとめ（PaaS との対比を一言で）

- インデックスは**選択性が高いとき**に効き、**低いとき／先頭列を外したとき／列を加工したとき**は効かない。
- 「貼ったのに速くならない」の答えは、ほぼ常に `EXPLAIN (ANALYZE, BUFFERS)` の中にある。
- マネージド DB でも索引は貼れるが、**なぜそのプランを選んだか**を計画から読む癖は、PaaS でも自前でも同じ武器になる。

## 関連

- 新出語は [KNOWLEDGE.md](KNOWLEDGE.md) に整理。
- 次の候補は `local/db/PLAN.md` の **案4（制約・正規化）→ 案2（VACUUM・統計）**。
  特に案2 は「`ANALYZE` 前後でプランが変わる」＝ここで前提にした**統計**を主役にした続き。
