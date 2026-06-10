Terraformで現在管理しているリソースを表示するコマンドについて説明します。

## 基本コマンド

### `terraform state list`
最も基本的なコマンドで、管理中の全リソースを一覧表示します。

```bash
terraform state list
```

**出力例:**
```
aws_instance.web
aws_security_group.allow_ssh
module.vpc.aws_vpc.main
```

## 主要なオプション

### `terraform state list` のオプション

```bash
# 特定のリソースタイプのみ表示
terraform state list aws_instance

# 特定のモジュール内のリソースを表示
terraform state list module.vpc

# IDでフィルタリング
terraform state list | grep "security_group"
```

### `terraform state show`
特定リソースの詳細情報を表示します。

```bash
# 特定リソースの詳細表示
terraform state show aws_instance.web

# JSON形式で出力
terraform state show -json aws_instance.web
```

## 類似・関連コマンド

### `terraform show`
現在のstate全体を人間が読みやすい形式で表示します。

```bash
# state全体を表示
terraform show

# JSON形式で出力（プログラムでの処理に便利）
terraform show -json

# 特定のstateファイルを指定
terraform show terraform.tfstate
```

### `terraform state pull`
リモートstateの内容を取得してJSON形式で表示します。

```bash
# リモートstateをJSON形式で取得
terraform state pull

# ファイルに保存
terraform state pull > state_backup.json
```

### `terraform output`
定義されたoutput値を表示します。

```bash
# 全output値を表示
terraform output

# 特定のoutput値を表示
terraform output vpc_id

# JSON形式で出力
terraform output -json
```

### `terraform providers`
使用中のproviderとそれらが管理するリソースを表示します。

```bash
terraform providers

# providerの依存関係をツリー形式で表示
terraform providers schema -json
```

## 便利な組み合わせ例

```bash
# リソース数をカウント
terraform state list | wc -l

# 特定のタグでフィルタ
terraform state list | grep "production"

# モジュール別にリソースをグループ化
terraform state list | grep "^module\." | cut -d. -f1-2 | sort -u

# 全リソースの詳細をファイルに出力
terraform state list | while read resource; do
  echo "=== $resource ===" >> resources.txt
  terraform state show $resource >> resources.txt
done
```

## その他の有用なコマンド

### `terraform plan -refresh-only`
実際のインフラとstateの差分を確認（リソースの存在確認）

```bash
terraform plan -refresh-only
```

### `terraform graph`
リソース間の依存関係を可視化（Graphviz形式）

```bash
# DOT形式で出力
terraform graph

# 画像として保存（Graphvizが必要）
terraform graph | dot -Tpng > graph.png
```

これらのコマンドを組み合わせることで、Terraformで管理しているインフラの全体像を把握できます。