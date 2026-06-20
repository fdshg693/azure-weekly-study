# persistence — データの永続化（bind mount / named volume / tmpfs）

`local/docker/PLAN.md` の **案5**。コンテナのファイルシステムは**使い捨て**であることを起点に、
「消えてほしくないデータ」「ホストと共有したいソース」「消えてよい一時データ」を**置き場所で区別**する
感覚を、設定を出し入れしながら体で覚える。

> 学び方は `learn/network` 流 ―― **まず一般概念 → 実装 → 設定を出し入れして因果を確かめる**。
> 構築・実行はあなた自身が手元の Docker で行う。

## 前提

- Docker（Docker Desktop など）が動いていること。`docker version` が通れば OK。
- `just` が入っていること（このリポジトリの他プロジェクトと同じ）。

## 3 つの置き場所（一般概念）

| 種類 | 実体 | 寿命 | 主な用途 |
|------|------|------|----------|
| 書き込み可能レイヤ | コンテナ固有の上書き層 | **コンテナと共に消える** | 一時ファイル（残す気がない物） |
| **bind mount** | ホストの任意パスを直結 | ホスト側に残る | ソース共有・設定流し込み・ホスト編集の即反映 |
| **named volume** | Docker 管理の保存領域 | コンテナを消しても残る | DB など**残したいデータ** |
| **tmpfs** | メモリ上 | コンテナと共に消える（ディスクに書かない） | 機密の一時データ・高速スクラッチ |

ポイントは **「コンテナの寿命」と「データの寿命」を切り離す**こと。`docker rm` でコンテナを捨てても
データを残したいなら、データを書き込みレイヤの外（volume か bind mount）に出す。

## 学習の流れ（出し入れ検証）

### 実験A→B: 消える書き込みレイヤ vs 残る named volume（検証①）

```pwsh
just count-novol   # 何度叩いても "count is now 1"（--rm で毎回まっさら）
just count-novol
just count-vol     # 1, 2, 3 ... と増える（ボリュームに残る）
just count-vol
just inspect       # docker volume ls / inspect で保存先(Mountpoint)を確認
```

同じ `count` スクリプトでも、`-v {{ボリューム}}:/data` を**載せるか載せないか**だけで
「毎回リセット」⇄「累積」と変わる。データを残しているのが**ボリューム**だと切り分けられる。

### 実験C: bind mount のライブ反映＋マウントによる隠蔽（検証②）

```pwsh
just serve           # ./site をコンテナの公開ディレクトリに直結して起動
just show            # ホストの site/index.html がそのまま配信される
#   → site/index.html を編集して保存（"v1" を "v2" など）
just show            # 再起動していないのに内容が変わる（ホスト編集が即反映）

just serve-default   # マウント無しの nginx を 8081 で起動
just show-default    # こちらは nginx 既定ページが見える
just web-stop        # 後片付け
```

- **ライブ反映**：bind mount はホストのファイルを直接見るので、コンテナを作り直さなくても編集が反映される。
- **マウントによる隠蔽**：`serve` では、nginx イメージに**元から入っている既定ページ**が、上に被せた
  `./site` に隠れて見えなくなる（`serve-default` と見比べる）。マウントは「その場所の元の中身を覆い隠す」。

### 実験D: tmpfs はメモリ上で揮発

```pwsh
just tmpfs-demo   # /scratch に書く → mount 出力に tmpfs と出る → 終了で消える
```

ディスクに残したくない一時データ（や機密）は tmpfs。named volume と違い**何も残らない**のが狙い。

### 実験E: 所有権/権限の落とし穴

```pwsh
just perm-fail   # 非 root(1000) で書く → Permission denied（/data は root 所有で作られる）
just perm-fix    # 一度 root で /data を chown
just perm-fail   # 今度は書ける
```

空の named volume を初めてマウントすると、その階層は**コンテナ内の所有者（既定 root）**で作られる。
非 root で動かすイメージ（案9 で扱う）では、ここで書き込みに失敗しがち。原因は権限であって
「ボリュームが壊れている」わけではない、と切り分けられる。

## 後片付け

```pwsh
just clean   # コンテナとボリュームを削除
```

ローカル完結なので課金は無いが、ボリュームはディスクに残る。終わったら `just clean`。

## 関連

- 次の学習候補は `local/docker/PLAN.md` を参照。永続化の次は **案2（プロセスとシグナル）** や
  **案4（ネットワーク）** が地続き。
- 新しく出た用語は `KNOWLEDGE.md` に整理。
