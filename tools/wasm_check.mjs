// 在 Node 里跑 wasm 验收壳，不需要浏览器。
//
// 它实例化 examples/web 编译出的 wasm 模块，调用 `selftest()`，
// 再把 `report_len()` / `report_code_unit(i)` 拼回文本。这两步
// 就是浏览器里按钮做的全部事情，所以 Node 通过 = 页面通过。
//
// wasm-gc 需要 V8 12+（Node 22 起内置）。

import { readFile } from "node:fs/promises";
import { existsSync, readdirSync } from "node:fs";

// 构建产物的目录层级取决于「模块根在哪」：
// - 单独 clone 本仓库（CI 就是这样）是 `_build/wasm-gc/release/build/examples/web/`；
// - 作为 moon workspace 的成员时，路径里会多出模块前缀 `weopqrst/mooncsg/`。
// 硬编码某一种会让另一种环境找不到文件，所以列候选之外再兜一次递归搜索。
const candidates = [
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
  for (const e of entries) {
    if (e.isFile() && e.name === "web.wasm") return `${dir}/${e.name}`;
  }
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    const hit = findWasm(`${dir}/${e.name}`);
    if (hit !== undefined) return hit;
  }
  return undefined;
}

const wasmPath =
  process.argv[2] ?? candidates.find((p) => existsSync(p)) ?? findWasm("_build");
if (wasmPath === undefined) {
  console.error("找不到 web.wasm，先跑 moon build --target wasm-gc --release");
  process.exit(2);
}

const bytes = await readFile(wasmPath);
const { instance } = await WebAssembly.instantiate(bytes, {});
const exports = instance.exports;

if (typeof exports.selftest !== "function") {
  console.error("wasm 没有导出 selftest");
  process.exit(2);
}

const passed = exports.selftest();
const len = exports.report_len();
let text = "";
for (let i = 0; i < len; i++) {
  text += String.fromCharCode(exports.report_code_unit(i));
}

console.log(text);
if (passed !== 4) {
  console.error(`失败：${passed}/4 项通过`);
  process.exit(1);
}
console.log(`通过：${passed}/4 项`);
