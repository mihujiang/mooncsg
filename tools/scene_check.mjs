// 在 Node 里验证交互 demo 的 wasm 接口：建网格、读三角/顶点坐标、读指标。
// 浏览器里 canvas 干的就是这些事，所以 Node 通过 = 页面能跑。

import { readFile } from "node:fs/promises";

const bytes = await readFile(process.argv[2] ?? "examples/web/web.wasm");
const { instance } = await WebAssembly.instantiate(bytes, {});
const ex = instance.exports;

for (const name of [
  "build",
  "triangle_count",
  "vertex_count",
  "tri_index",
  "pos",
  "grid_dim",
  "metric",
  "flag",
]) {
  if (typeof ex[name] !== "function") {
    console.error(`缺少导出 ${name}`);
    process.exit(2);
  }
}

function bounds() {
  const n = ex.vertex_count();
  let lo = [Infinity, Infinity, Infinity];
  let hi = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < n; i++) {
    for (let k = 0; k < 3; k++) {
      const v = ex.pos(3 * i + k);
      if (v < lo[k]) lo[k] = v;
      if (v > hi[k]) hi[k] = v;
    }
  }
  return { lo, hi };
}

// 形状号：0 球、1 盒、2 圆台、3 胶囊、4 环面
const cases = [
  [0, 10, 0, 0], // 球 r=10，解析体积 4188.79
  [1, 10, 0, 0], // 盒 边长 10，体积 1000
  [2, 8, 10, 0], // 圆台 底 8 顶 0 高 10
  [2, 0, 0, 0], // 滑杆拖到 0：入口应夹住而不是 panic
  [3, 4, 10, 0], // 胶囊 半径 4 段长 10
  [4, 3, 10, 0], // 环面 管半径 3、环半径 10
  [0, 10, 0, 6], // 球减同心球
];

let failed = 0;
for (const [shape, r1, r2, cut] of cases) {
  const tris = ex.build(shape, r1, r2, cut, 48);
  const verts = ex.vertex_count();
  const b = bounds();
  const vol = ex.metric(0);
  const area = ex.metric(1);
  const watertight = ex.flag(0) === 1;
  const euler = ex.flag(1);
  const genus = ex.flag(2);
  const idxOk = ex.tri_index(3 * tris - 1) >= 0;
  const spanOk = b.hi.every((h, k) => h > b.lo[k]);
  // 请求 48 时实际格点必须也是 48（这个量级远没到 MAX_GRID_SLOTS）。
  const grid = [ex.grid_dim(0), ex.grid_dim(1), ex.grid_dim(2)];
  const gridOk = grid[0] > 0 && grid.every((g) => g <= 48);
  const ok =
    tris > 0 && verts > 0 && vol > 0 && area > 0 && watertight && idxOk &&
    spanOk && gridOk;
  if (!ok) failed++;
  console.log(
    `${ok ? "OK  " : "FAIL"} shape=${shape} tris=${tris} verts=${verts} ` +
      `vol=${vol.toFixed(3)} area=${area.toFixed(3)} ` +
      `watertight=${watertight} euler=${euler} genus=${genus} ` +
      `grid=${grid.join("x")} ` +
      `bbox=[${b.lo.map((v) => v.toFixed(2))}]..[${b.hi.map((v) => v.toFixed(2))}]`,
  );
}

if (failed > 0) {
  console.error(`${failed}/${cases.length} 个场景失败`);
  process.exit(1);
}
console.log(`通过：${cases.length} 个场景`);
