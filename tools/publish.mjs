// 发版一条龙：打包 → 发布 → **回拉验证**。
//
// 回拉这一步是重点。mooncakes 出现过「列表接口说版本在，下载却 404」的
// 平台故障，只看 `moon publish` 的退出码发现不了。这里的做法是：
//
//   1. 删掉本地 registry 缓存里该版本的目录；
//   2. 在一个临时模块里 `moon add <name>@<version>`；
//   3. `moon check` —— 走真实的下载 + 解包 + 编译路径。
//
// 也就是说，这一步通过 = 陌生人 `moon add` 一定拿得到能用的包。
//
// 用法：
//   node tools/publish.mjs               # 真发布（检查 → 打包 → 发布 → 回拉）
//   node tools/publish.mjs --dry-run     # 检查 + 打包 + 回拉，不发布
//   node tools/publish.mjs --probe-only  # 只回拉：发布后单独复验
//
// 注意：要在 workspace 之外的干净 clone 里跑。workspace 内 `moon check`
// 会连带检查兄弟模块，`moon publish` 也会拿它们当依赖处理。

import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dryRun = process.argv.includes("--dry-run");
const probeOnly = process.argv.includes("--probe-only");
const win = process.platform === "win32";
const moon = process.env.MOON ?? "moon";
const moonHome = process.env.MOON_HOME ?? join(homedir(), ".moon");

function run(cmd, args, cwd = root) {
  process.stdout.write(`$ ${cmd} ${args.join(" ")}\n`);
  const r = spawnSync(cmd, args, { cwd, stdio: "inherit", shell: win });
  if (r.status !== 0) {
    throw new Error(`命令失败（exit ${r.status}）：${cmd} ${args.join(" ")}`);
  }
}

function readField(source, key) {
  const m = new RegExp(`${key}\\s*=\\s*"([^"]+)"`).exec(source);
  if (!m) throw new Error(`moon.mod 里没有 ${key}`);
  return m[1];
}

const mod = readFileSync(join(root, "moon.mod"), "utf8");
const name = readField(mod, "name");
const version = readField(mod, "version");
const [user, pkg] = name.split("/");
console.log(`模块 ${name} 版本 ${version}${dryRun ? "（dry-run）" : ""}`);

// 只跑回拉那一段：发布之后单独复验，或者对着一个没发布的版本号验证
// 「它确实会失败」。
if (!probeOnly) {
  if (!dryRun && !existsSync(join(moonHome, "credentials.json"))) {
    console.error(
      `没有找到 ${join(moonHome, "credentials.json")}: 先 moon login，` +
        `或把 ~/.moon/credentials.json 复制到 MOON_HOME 下。`,
    );
    process.exit(2);
  }

  // 1) 打包前先确认自己的树是绿的：publish 内部会跑 check，红了更晚才发现。
  run(moon, ["check", "--deny-warn"]);
  run(moon, ["package"]);

  // 2) 发布
  if (dryRun) {
    console.log("跳过 moon publish");
  } else {
    run(moon, ["publish"]);
  }
}

// 3) 回拉验证。先删掉本地缓存的 zip，逼出一次真实下载：缓存命中时
// `moon add` 根本不联网，测不出平台故障。
// 缓存落在 `<MOON_HOME>/registry/cache/<user>/<pkg>/<version>.zip`，
// 解包落在探针目录的 `.mooncakes/<user>/<pkg>/`。
const cachedZip = join(moonHome, "registry", "cache", user, pkg, `${version}.zip`);
if (existsSync(cachedZip)) {
  rmSync(cachedZip, { force: true });
  console.log(`已清掉缓存 ${cachedZip}`);
}

const probe = mkdtempSync(join(tmpdir(), "mooncsg-probe-"));
try {
  run(moon, ["new", probe, "--user", "mooncsgprobe", "--name", "check"]);
  run(moon, ["add", `${name}@${version}`], probe);
  run(moon, ["check"], probe);
  // `moon check` 只保证下载与解包没报错；再确认解出来的内容不是空壳
  // （发生过 zip 只有元数据、源码缺失的情况）。
  const unpacked = join(probe, ".mooncakes", user, pkg);
  const mustHave = ["moon.mod", "moon.pkg", "sdf.mbt", "mesh.mbt"];
  for (const file of mustHave) {
    const path = join(unpacked, file);
    if (!existsSync(path)) {
      throw new Error(`回拉验证失败：解包里缺少 ${file}（${unpacked}）`);
    }
    const size = statSync(path).size;
    if (size < 16) {
      throw new Error(`回拉验证失败：${file} 只有 ${size} 字节，像是截断了`);
    }
  }
  const pulled = readField(readFileSync(join(unpacked, "moon.mod"), "utf8"), "version");
  if (pulled !== version) {
    throw new Error(`回拉验证失败：拿到的是 ${pulled}，期望 ${version}`);
  }
  console.log(`\n回拉验证通过：${name}@${version} 可下载、可解包、可编译`);
} finally {
  if (!process.env.KEEP_PROBE) {
    rmSync(probe, { recursive: true, force: true });
  } else {
    console.log(`探针目录保留在 ${probe}`);
  }
}
