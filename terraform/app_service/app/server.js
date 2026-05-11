const http = require("http");

const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(
    "<!doctype html><meta charset=\"utf-8\"><title>Minimal App</title>" +
      "<h1>Hello from Azure App Service</h1>" +
      "<p>Node " + process.version + " / host " + (req.headers.host || "-") + "</p>"
  );
});

server.listen(port, () => {
  console.log(`listening on ${port}`);
});
