// 构建 wasm 模块并复制到 examples/web/，让 index.html 能 fetch("./web.wasm")。
//
// 用 Node 而不是 PowerShell：Windows PowerShell 5.1 会把 moon 的 stderr
// 进度行当成终止错误，脚本里很难判断真实退出码。
//
// 产物路径随「模块根在哪」变化：
// - 单独 clone 本仓库（CI 就是这样）：`_build/wasm-gc/release/build/examples/web/`；
// - 作为 moon workspace 的成员：中间多出模块前缀 `weopqrst/mooncsg/`，
//   而且 `_build` 落在 workspace 根上，也就是上一级目录。
// 所以先列候选，最后再在 `_build` 里递归找一次兜底——路径变了也不会静默失败。

import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, readdirSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const moon = process.env.MOON_HOME
  ? join(
      process.env.MOON_HOME,
      "bin",
      process.platform === "win32" ? "moon.exe" : "moon",
    )
  : "moon";

execFileSync(moon, ["build", "--target", "wasm-gc", "--release"], {
  cwd: root,
  stdio: "inherit",
});

const relativePaths = [
  "_build/wasm-gc/release/build/examples/web/web.wasm",
  "_build/wasm-gc/release/build/weopqrst/mooncsg/examples/web/web.wasm",
  "../_build/wasm-gc/release/build/weopqrst/mooncsg/examples/web/web.wasm",
];

function findWasm(dir) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return undefined;
  }
  for (const entry of entries) {
    if (entry.isFile() && entry.name === "web.wasm") return join(dir, entry.name);
  }
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const hit = findWasm(join(dir, entry.name));
    if (hit !== undefined) return hit;
  }
  return undefined;
}

const built =
  relativePaths.map((p) => join(root, p)).find((p) => existsSync(p)) ??
  findWasm(join(root, "_build")) ??
  findWasm(join(root, "..", "_build"));
if (built === undefined) {
  console.error("找不到 web.wasm，构建可能失败了");
  process.exit(1);
}

const target = join(root, "examples/web/web.wasm");
copyFileSync(built, target);
console.log(`已复制 ${built} -> examples/web/web.wasm`);
