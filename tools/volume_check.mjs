#!/usr/bin/env node
// 体积对拍：解析值来自 tools/oracle.py（纯标准库），实测值来自
// `moon run cmd/main -- <shape> --res 48 --stats`。
//
// 为什么单独一个脚本：acceptance 里原来那一步只是 `python tools/oracle.py`，
// 它打印解析值就 exit 0 —— PASS 只说明脚本能跑，没有任何一条断言真的比过
// 阈值。这里把两边接起来：误差超过 oracle 给的容差就 exit 1，CI 会红。

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const moon = process.env.MOON ?? "moon";
const python = process.platform === "win32" ? "python" : "python3";
const res = "48";

const oracle = spawnSync(python, ["tools/oracle.py", "--cases"], {
  cwd: root,
  encoding: "utf8",
});
if (oracle.error || oracle.status !== 0) {
  process.stderr.write(
    `oracle.py 跑不起来（${python}）：${oracle.error?.message ?? oracle.stderr}\n`,
  );
  process.exit(1);
}

let cases;
try {
  cases = JSON.parse(oracle.stdout);
} catch {
  process.stderr.write(`oracle.py 的输出不是 JSON：\n${oracle.stdout.slice(0, 400)}\n`);
  process.exit(1);
}

// --stats 的输出形如：
//   triangles:  58944 | vertices: 29474 | volume: 4186.8207... | area: ...
// 只认 volume 这一个字段；其余字段在别的检查里管。
const VOLUME = /volume:\s*(-?[\d.]+(?:[eE][-+]?\d+)?)/;

const rows = [];
let failed = 0;
for (const c of cases) {
  const started = Date.now();
  const r = spawnSync(
    moon,
    ["run", "cmd/main", "--", ...c.cmd, "--res", res, "--stats"],
    { cwd: root, encoding: "utf8", shell: true },
  );
  const out = `${r.stdout ?? ""}${r.stderr ?? ""}`;
  const ms = Date.now() - started;
  if (r.status !== 0) {
    failed += 1;
    rows.push([c.label, c.volume.toFixed(3), "-", "-", `构建失败（${ms} ms）`, "✗"]);
    process.stderr.write(`\n--- ${c.label}: moon run 失败 ---\n${out.trim().slice(-600)}\n`);
    continue;
  }
  const m = out.match(VOLUME);
  if (!m) {
    failed += 1;
    rows.push([c.label, c.volume.toFixed(3), "-", "-", "没读到 volume 字段", "✗"]);
    continue;
  }
  const measured = Number(m[1]);
  const errPct = Math.abs(measured - c.volume) / c.volume * 100;
  const ok = errPct <= c.tol_pct;
  if (!ok) failed += 1;
  rows.push([
    c.label,
    c.volume.toFixed(3),
    measured.toFixed(3),
    `${errPct.toFixed(3)} %`,
    `< ${c.tol_pct} %`,
    ok ? "✓" : "✗",
  ]);
}

const header = ["形状", "解析体积", "实测体积", "相对误差", "容差", "判定"];
const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => String(r[i]).length)));
const line = (cells) => cells.map((c, i) => String(c).padEnd(widths[i])).join("  ");

console.log(line(header));
console.log(widths.map((w) => "-".repeat(w)).join("  "));
for (const r of rows) console.log(line(r));

console.log(
  failed === 0
    ? `\n通过：${rows.length}/${rows.length} 组（resolution = ${res}）`
    : `\n${failed}/${rows.length} 组超差（resolution = ${res}）`,
);
process.exit(failed === 0 ? 0 : 1);
