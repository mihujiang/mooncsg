// 极简静态服务器，只为本地预览 examples/web。
// 生成 wasm 后运行：node tools/build_web.mjs && node tools/serve.mjs
// 打开 http://localhost:8000 点 "run selftest"。

import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "examples/web");
const types = {
  ".html": "text/html; charset=utf-8",
  ".wasm": "application/wasm",
  ".js": "text/javascript; charset=utf-8",
};

createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", "http://localhost");
  const rel = normalize(url.pathname === "/" ? "/index.html" : url.pathname);
  const file = join(root, rel);
  if (!file.startsWith(root)) {
    res.writeHead(403).end("forbidden");
    return;
  }
  try {
    const body = await readFile(file);
    res.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404).end("not found");
  }
}).listen(8000, () => {
  console.log("http://localhost:8000");
});
