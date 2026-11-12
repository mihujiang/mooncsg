// 构建 wasm 模块并复制到 examples/web/，让 index.html 能 fetch("./web.wasm")。
//
// 用 Node 而不是 PowerShell：Windows PowerShell 5.1 会把 moon 的 stderr
// 进度行当成终止错误，脚本里很难判断真实退出码。

import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const moon = process.env.MOON_HOME
  ? join(process.env.MOON_HOME, "bin", process.platform === "win32" ? "moon.exe" : "moon")
  : "moon";

execFileSync(moon, ["build", "--target", "wasm-gc", "--release"], {
  cwd: root,
  stdio: "inherit",
});

const relative = "_build/wasm-gc/release/build/weopqrst/mooncsg/examples/web/web.wasm";
const candidates = [join(root, relative), join(root, "..", relative)];
const built = candidates.find((p) => existsSync(p));
if (built === undefined) {
  console.error("找不到 web.wasm，构建可能失败了");
  process.exit(1);
}

const target = join(root, "examples/web/web.wasm");
copyFileSync(built, target);
console.log("已复制到 examples/web/web.wasm");
