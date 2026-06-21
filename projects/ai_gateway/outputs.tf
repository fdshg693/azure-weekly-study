# ============================================================================
# 出力値（terraform apply 後 / terraform output で確認）
# ============================================================================

output "resource_group_name" {
  description = "リソースグループ名"
  value       = azurerm_resource_group.main.name
}

output "openai_account_name" {
  description = "Azure OpenAI アカウント名（az cognitiveservices ... の -n に使う）"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Azure OpenAI エンドポイント（アプリの AZURE_OPENAI_ENDPOINT と同じ値）"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_account_id" {
  description = "Azure OpenAI アカウントのリソース ID（ロール割り当てのスコープに使う）"
  value       = azurerm_cognitive_account.openai.id
}

output "local_auth_enabled" {
  description = "API キー認証が有効か（false = キーレス強制）"
  value       = azurerm_cognitive_account.openai.local_auth_enabled
}

# 動作確認用コマンド（ステップ0 時点では「デプロイは0件」が正常）
output "verify_commands" {
  description = "ステップ0 の土台が出来たかを確認するコマンド"
  value       = <<-EOT
    # ============================================================
    # AI Gateway ステップ0 動作確認
    # ============================================================

    # 1. アカウントが出来ているか（プロビジョニング状態を確認）
    az cognitiveservices account show -n ${azurerm_cognitive_account.openai.name} -g ${azurerm_resource_group.main.name} --output table

    # 2. モデルデプロイ一覧 … この時点では「空」が正解（後続ステップで作る対象）
    az cognitiveservices account deployment list -n ${azurerm_cognitive_account.openai.name} -g ${azurerm_resource_group.main.name} --output table

    # 3. 自分に割り当てられたロールを確認（OpenAI User / Contributor の2つが見えるはず）
    az role assignment list --scope ${azurerm_cognitive_account.openai.id} --output table

    # 4. デプロイ可能なベースモデル一覧（リージョン×モデルの可用性を確認）
    az cognitiveservices account list-models -n ${azurerm_cognitive_account.openai.name} -g ${azurerm_resource_group.main.name} --query "[].{model:name, version:version, format:format}" --output table
  EOT
}
