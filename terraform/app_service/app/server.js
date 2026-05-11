const express = require("express");
const { AzureOpenAI } = require("openai");
const { getBearerTokenProvider, DefaultAzureCredential } = require("@azure/identity");

const port = process.env.PORT || 3000;
const endpoint = process.env.AZURE_OPENAI_ENDPOINT;
const deployment = process.env.AZURE_OPENAI_DEPLOYMENT || "gpt-4o-mini";
const apiVersion = process.env.AZURE_OPENAI_API_VERSION || "2024-10-21";

// DefaultAzureCredential はローカル開発時は `az login` の資格情報、
// App Service 上ではシステム割り当てマネージド ID を自動で使用する
const credential = new DefaultAzureCredential();
const scope = "https://cognitiveservices.azure.com/.default";
const azureADTokenProvider = getBearerTokenProvider(credential, scope);

const openai = new AzureOpenAI({ endpoint, azureADTokenProvider, deployment, apiVersion });

const app = express();
app.set("view engine", "ejs");
app.set("views", __dirname + "/views");
app.use(express.urlencoded({ extended: false }));

app.get("/", (req, res) => {
  res.render("index", { title: "Azure OpenAI Chatbot", aiMessage: null, userMessage: null });
});

app.post("/chat", async (req, res) => {
  const userMessage = (req.body.message || "").trim();
  if (!userMessage) return res.redirect("/");

  let aiMessage = "";
  try {
    const result = await openai.chat.completions.create({
      model: deployment,
      messages: [
        { role: "system", content: "あなたは親切で簡潔に答える日本語アシスタントです。" },
        { role: "user", content: userMessage },
      ],
    });
    aiMessage = result.choices[0]?.message?.content || "";
  } catch (err) {
    console.error("OpenAI error:", err);
    aiMessage = "Azure OpenAI からの応答取得に失敗しました: " + (err.message || err);
  }

  res.render("index", { title: "Azure OpenAI Chatbot", aiMessage, userMessage });
});

app.get("/healthz", (_req, res) => res.status(200).send("ok"));

app.listen(port, () => {
  console.log(`listening on ${port}`);
});
