// 一条命令跑完全部验收项，输出一张 PASS/FAIL 表。
//
// 为什么要一个脚本而不是「CI 里那一串 step」：CI 的 step 只在 push 时跑，
// 而且任何一个 step 失败后面的都不执行，看不到全貌。本地收工前跑这个，
// 能一次看到哪些项红了。
//
// 每项都是子进程调用，输出只在失败时打印末尾 40 行，避免几万行测试
// 输出把真正的问题淹掉。
//
// 两处环境差异要处理：
// 1. 本仓库可能是 moon workspace（父目录有 `moon.work`）的一个成员，
//    所以 moon 命令都带 `-p weopqrst/mooncsg`，只测本模块。
// 2. Windows 上没装 MSVC Build Tools 时 native 后端整个不可用。这种情况
//    判 SKIP 而不是 FAIL（CI 的 ubuntu runner 会跑 native），但如果失败
//    原因不是「工具链缺失」，仍然算 FAIL。

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const moon = process.env.MOON ?? "moon";
const pkg = "weopqrst/mooncsg";

// 判定「本机根本没装 native 工具链」的痕迹。命中即 SKIP。
const nativeUnavailable = /MSVC|requires a (C )?compiler|clang-cl|Windows native backend/;

const steps = [
  // `check` / `build` / `package` 没有 `-p`，只有 `test` 有；`build` 的
  // 位置参数 `PATH` 就是当前包，够用来探测 native 工具链在不在。
  { name: "check", cmd: moon, args: ["check", "--deny-warn"], shell: true },
  { name: "fmt", cmd: moon, args: ["fmt", "--check"], shell: true },
  { name: "test native", cmd: moon, args: ["test", "--target", "native", "-p", pkg], shell: true },
  { name: "test wasm-gc", cmd: moon, args: ["test", "--target", "wasm-gc", "-p", pkg], shell: true },
  { name: "test js", cmd: moon, args: ["test", "--target", "js", "-p", pkg], shell: true },
  { name: "package", cmd: moon, args: ["package"], shell: true },
  { name: "demo", cmd: moon, args: ["run", "examples/demo"], shell: true },
  { name: "bench", cmd: moon, args: ["run", "examples/bench", "--release"], shell: true },
  // 浏览器验收壳：编译 wasm、复制到页面目录、在 Node 里实例化跑 selftest。
  { name: "build web", cmd: process.execPath, args: ["tools/build_web.mjs"] },
  {
    name: "wasm selftest",
    cmd: process.execPath,
    args: ["tools/wasm_check.mjs", "examples/web/web.wasm"],
  },
];

// Python 基准是可选的：机器上没装 python 时跳过，不判失败。
const python = process.platform === "win32" ? "python" : "python3";
if (spawnSync(python, ["--version"], { shell: true }).status === 0) {
  steps.push({ name: "analytic oracle", cmd: python, args: ["tools/oracle.py"], shell: true });
} else {
  steps.push({ name: "analytic oracle", skip: "python 不可用" });
}

const rows = [];
let failed = 0;
for (const step of steps) {
  if (step.skip !== undefined) {
    rows.push(["SKIP", step.name, step.skip]);
    continue;
  }
  const started = Date.now();
  const r = spawnSync(step.cmd, step.args, {
    cwd: root,
    encoding: "utf8",
    shell: step.shell === true,
  });
  const ms = Date.now() - started;
  const out = `${r.stdout ?? ""}${r.stderr ?? ""}`.trim();
  if (r.status === 0) {
    rows.push(["PASS", step.name, `${ms} ms`]);
    continue;
  }
  if (nativeUnavailable.test(out)) {
    rows.push(["SKIP", step.name, "本机无 native 工具链"]);
    continue;
  }
  failed += 1;
  rows.push(["FAIL", step.name, `${ms} ms (exit ${r.status})`]);
  // 只留末尾 40 行：编译/测试报错的关键信息都在尾部。
  const tail = out.split("\n").slice(-40).join("\n");
  process.stderr.write(`\n--- ${step.name} ---\n${tail}\n`);
}

// 等宽对齐，肉眼扫一遍就够了。
const width = Math.max(...rows.map((r) => r[1].length));
for (const [status, name, note] of rows) {
  console.log(`${status}  ${name.padEnd(width)}  ${note}`);
}

console.log(
  failed === 0
    ? `\n没有失败项（共 ${rows.length} 项）`
    : `\n${failed}/${rows.length} 项失败`,
);
process.exit(failed === 0 ? 0 : 1);
