#!/usr/bin/env node
// 边界语义门禁：把「什么输入能保证可打印、什么输入必须拒绝」变成可执行的断言。
//
// 起因：初审质疑「一定水密、可直接切片」这个承诺没有边界。承诺本身没错，
// 但它依赖「采样域严格包住实体」——这条前提以前只写在文档里，代码不检查。
// 现在 lib 侧有 `mesh_checked`，CLI 默认走它；这个脚本用真实 CLI 输入把
// 语义钉死：
//
//   - 正常输入：exit 0，watertight=true，open_edges=0；
//   - 半空间（无界）：exit != 0，说明要给 --bounds；
//   - 半空间 + 有界域、域小于实体、域离实体很远：exit != 0 并给出原因，
//     **不是**静默输出一个开口网格；
//   - 同一输入加 --clip：exit 0，但必须明确 watertight=false 且 open_edges>0。
//
// 任何一条不符合就 exit 1，CI 会红。

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const moon = process.env.MOON ?? "moon";

const CLIPPED_DOMAIN = ["--bounds", "-10.5,-10.5,-10.5,2,10.5,10.5"];

const cases = [
  {
    name: "正常球（自动采样域）",
    args: ["sphere", "10", "--res", "32", "--stats"],
    code: 0,
    want: ["watertight: true", "open_edges: 0"],
    open: false,
  },
  // `--audit` 的契约是「stdout 只有一份 JSON」：JSON.parse 整个 stdout 能过，
  // 就说明没有指标行混进去（这个工具链的 eprintln 与 stdout 同流，很容易混）。
  {
    name: "正常球 --audit：stdout 是纯 JSON 且字段自洽",
    args: ["sphere", "10", "--res", "32", "--audit"],
    code: 0,
    json: {
      shells: 1,
      euler: 2,
      genus: 0,
      watertight: true,
      manifold: true,
      warnings: 0,
    },
  },
  {
    name: "裁剪网格 --audit：watertight=false 且带告警",
    args: ["sphere", "10", ...CLIPPED_DOMAIN, "--clip", "--audit"],
    code: 0,
    json: { watertight: false },
    warningsAtLeast: 1,
  },
  {
    name: "半空间：无界，拒绝",
    args: ["plane", "0", "0", "1", "0", "--stats"],
    code: 1,
    want: ["没有有限包围盒"],
  },
  {
    name: "半空间 + 有界域：穿过边界，拒绝",
    args: ["plane", "0", "0", "1", "0", ...CLIPPED_DOMAIN, "--stats"],
    code: 1,
    want: ["采样域被实体穿过"],
  },
  {
    name: "域小于实体：拒绝",
    args: ["sphere", "10", ...CLIPPED_DOMAIN, "--stats"],
    code: 1,
    want: ["采样域被实体穿过"],
  },
  {
    name: "同一输入加 --clip：输出并声明开口",
    args: ["sphere", "10", ...CLIPPED_DOMAIN, "--clip", "--stats"],
    code: 0,
    want: ["watertight: false"],
    open: true,
  },
  {
    name: "域离实体很远：拒绝",
    args: ["sphere", "1", "--bounds", "100,100,100,110,110,110", "--stats"],
    code: 1,
    want: ["没有曲面"],
  },
];

const rows = [];
let failed = 0;

for (const c of cases) {
  const started = Date.now();
  const r = spawnSync(moon, ["run", "cmd/main", "--", ...c.args], {
    cwd: root,
    encoding: "utf8",
    shell: true,
  });
  const out = `${r.stdout ?? ""}${r.stderr ?? ""}`;
  const ms = Date.now() - started;
  const problems = [];

  if (r.status !== c.code) {
    problems.push(`退出码 ${r.status}（期望 ${c.code}）`);
  }
  for (const want of c.want ?? []) {
    if (!out.includes(want)) problems.push(`缺少 "${want}"`);
  }
  if (c.open) {
    const m = out.match(/open_edges:\s*(\d+)/);
    if (!m || Number(m[1]) <= 0) problems.push("open_edges 不是正数");
  }
  if (c.json) {
    let j;
    try {
      // 只解析 stdout：stderr 混进来就不该算「纯 JSON」。
      j = JSON.parse(r.stdout ?? "");
    } catch (e) {
      problems.push(`stdout 不是纯 JSON（${String(e && e.message).slice(0, 60)}）`);
    }
    if (j) {
      for (const [k, v] of Object.entries(c.json)) {
        const actual =
          k === "warnings" && Array.isArray(j.warnings) ? j.warnings.length : j[k];
        if (actual !== v) problems.push(`${k}=${JSON.stringify(actual)}（期望 ${v}）`);
      }
      if (typeof j.volume !== "number" || !(j.volume > 0)) {
        problems.push("volume 不是正数");
      }
      if (!j.bounds || !Array.isArray(j.bounds.min) || j.bounds.min.length !== 3) {
        problems.push("bounds 不是 {min:[3],max:[3]}");
      }
      if (
        c.warningsAtLeast &&
        (!Array.isArray(j.warnings) || j.warnings.length < c.warningsAtLeast)
      ) {
        problems.push(`warnings 少于 ${c.warningsAtLeast} 条`);
      }
    }
  }

  const ok = problems.length === 0;
  if (!ok) failed += 1;
  rows.push([c.name, `${ms} ms`, ok ? "✓" : `✗ ${problems.join("；")}`]);
}

const header = ["场景", "耗时", "判定"];
const widths = header.map((h, i) =>
  Math.max(h.length, ...rows.map((r) => String(r[i]).length)),
);
const line = (cells) => cells.map((c, i) => String(c).padEnd(widths[i])).join("  ");

console.log(line(header));
console.log(widths.map((w) => "-".repeat(w)).join("  "));
for (const r of rows) console.log(line(r));

console.log(
  failed === 0
    ? `\n通过：${rows.length}/${rows.length} 个边界场景`
    : `\n${failed}/${rows.length} 个边界场景不符合预期`,
);
process.exit(failed === 0 ? 0 : 1);
