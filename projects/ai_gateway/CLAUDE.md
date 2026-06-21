NodeのOpenAISDKについては、`projects\chatbot\app\openai-node`のクローンされたものを随時参考にする。
特に`projects\chatbot\app\openai-node\examples`に様々なサンプルコードがあるので、必要に応じて参照する。
必ずResponse APIを使うこと。Completion APIは非推奨。
AOAIモデルはGPT-4.1, GPT-5などResponse APIに対応しているものを使うこと。

上記OpenAI SDK含めた、変更が激しいフレームワーク・ツールについては記憶にたよらず必ずWEB検索を行う。
特に多少なりとも複雑な検索には必ず`use-tavily`スキルが有用なので使うこと（それなりに重いスキルなので、1回検索して済むような軽量な検索には使わないこと）。