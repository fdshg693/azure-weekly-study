Azureリソースの状態確認に便利なAzure CLIコマンドをご紹介します。

## 基本的なリソース確認

**リソースグループの一覧**
```bash
az group list --output table
```

**特定リソースグループ内のリソース一覧**
```bash
az resource list --resource-group <リソースグループ名> --output table
```

**すべてのリソースを表示**
```bash
az resource list --output table
```

## 仮想マシン（VM）

**VM一覧と状態**
```bash
az vm list --show-details --output table
az vm list -d --output table  # -dは--show-detailsの省略形
```

**特定VMの状態確認**
```bash
az vm get-instance-view --name <VM名> --resource-group <RG名>
```

**VM起動状態の確認**
```bash
az vm list -d --query "[].{Name:name, PowerState:powerState}" --output table
```

## App Service / Web Apps

**App Service一覧**
```bash
az webapp list --output table
```

**特定Web Appの状態**
```bash
az webapp show --name <アプリ名> --resource-group <RG名> --query state
```

## データベース

**SQL Database一覧**
```bash
az sql db list --resource-group <RG名> --server <サーバー名> --output table
```

**Azure Database for PostgreSQL**
```bash
az postgres server list --output table
az postgres server show --name <サーバー名> --resource-group <RG名>
```

## ストレージ

**ストレージアカウント一覧**
```bash
az storage account list --output table
```

**ストレージアカウントの詳細**
```bash
az storage account show --name <アカウント名> --resource-group <RG名>
```

## ネットワーク

**仮想ネットワーク一覧**
```bash
az network vnet list --output table
```

**パブリックIP一覧**
```bash
az network public-ip list --output table
```

**ロードバランサー一覧**
```bash
az network lb list --output table
```

## Container / Kubernetes

**AKSクラスター一覧**
```bash
az aks list --output table
```

**AKSクラスターの状態**
```bash
az aks show --name <クラスター名> --resource-group <RG名>
```

## アクティビティログ（操作履歴）

**最近のアクティビティログ**
```bash
az monitor activity-log list --start-time 2024-01-01 --output table
```

## 便利なオプション

**JMESPathクエリで特定情報を抽出**
```bash
az vm list -d --query "[?powerState=='VM running'].{Name:name, RG:resourceGroup}" --output table
```

**JSON形式で詳細確認**
```bash
az vm show --name <VM名> --resource-group <RG名> --output json
```

**TSV形式でスクリプト処理しやすく**
```bash
az vm list -d --output tsv
```

これらのコマンドを組み合わせて、効率的にAzureリソースの状態を監視できます。何か特定のリソースタイプについてもっと詳しく知りたいことはありますか?