# プロジェクト一覧

## Agent Service

- [Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/overview)
- [Agent Runtime Components](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components?tabs=python)

### `ephemeral_agent`

Foundry Agent Service のエージェントのなかで、エフェメラルエージェント パターンについて学ぶ
リソース構築は行わず必要変数を注入する（同階層の`prompt_agent`と同様であるため）
https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/responses-api?pivots=python

### `hosted_agent`

- [Hosted Agent デプロイ](https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/quickstart-hosted-agent?pivots=azd) 
    - デプロイ方法のみで、それもサンプルコードをGithubから取っているだけ
        - 詳細な例は`https://github.com/microsoft-foundry/foundry-samples/blob/main/samples/python/hosted-agents/agent-framework/responses/01-basic/README.md`および同階層のコードを参照
        - `azure_sdk\hosted_agent\samples` にコピー済
- [ソースコードから Hosted Agent をデプロイ](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-code?tabs=python)

### `prompt_agent`

Foundry Agent Service のエージェントのなかで、プロンプトエージェントについて学ぶ
リソースの構築・エージェント作成・エージェント呼び出しまで行う
https://learn.microsoft.com/en-us/azure/foundry/agents/quickstarts/prompt-agent?tabs=python

## エージェントツール

- [エージェントツール全体像](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-catalog)