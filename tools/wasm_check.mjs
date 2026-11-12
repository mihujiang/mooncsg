// 在 Node 里跑 wasm 验收壳，不需要浏览器。
//
// 它实例化 examples/web 编译出的 wasm 模块，调用 `selftest()`，
// 再把 `report_len()` / `report_code_unit(i)` 拼回文本。这两步
// 就是浏览器里按钮做的全部事情，所以 Node 通过 = 页面通过。
//
// wasm-gc 需要 V8 12+（Node 22 起内置）。

import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";

const candidates = [
  "_build/wasm-gc/release/build/weopqrst/mooncsg/examples/web/web.wasm",
  "../_build/wasm-gc/release/build/weopqrst/mooncsg/examples/web/web.wasm",
];

const wasmPath = process.argv[2] ?? candidates.find((p) => existsSync(p));
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
