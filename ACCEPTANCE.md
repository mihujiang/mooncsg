# 验收记录

本文件记录 **0.1.3** 这一版实际跑出来的数字。所有数值都来自下面这条命令，
不是估算，也不是设计目标。

## 环境

| 项 | 值 |
| --- | --- |
| 系统 | Windows 11 |
| MoonBit | 0.1.20261021（`MOON_HOME=D:\mb`） |
| core | 0.10.17 |
| Node | v24（wasm-gc / js 都跑在 V8 上） |
| native 后端 | **本机不可用**（没装 MSVC Build Tools），相关项判 SKIP |

## 一条命令

```bash
node tools/acceptance.mjs
```

实际输出（2026-11-13）：

```
PASS  check            1046 ms
PASS  fmt               823 ms
SKIP  test native      本机无 native 工具链
PASS  test wasm-gc     5539 ms
PASS  test js          8513 ms
PASS  package          1565 ms
PASS  demo              903 ms
PASS  bench            1062 ms
PASS  build web         292 ms
PASS  wasm selftest     367 ms
PASS  wasm scene       1183 ms
PASS  analytic oracle   319 ms

没有失败项（共 12 项）
```

毫秒列随机器负载浮动，判定只看 PASS / SKIP 两列。

`test wasm-gc` 内部是 `Total tests: 41, passed: 41, failed: 0.`
（其中 4 个是新加的圆台/胶囊断言，2 个是 `grid_shape` 的格点规划断言）。

## 精度：实测 vs 解析

网格一律用 `resolution = 48`（`grid_shape` 报 48³，未被 `MAX_GRID_SLOTS` 收窄），
体积由散度定理在三角网格上精确累加，解析值由 `tools/oracle.py`（纯标准库，
独立实现）给出。

| 形状 | 解析体积 | 实测体积 | 相对误差 | 判定 |
| --- | --- | --- | --- | --- |
| 球 r=10 | 4188.790 | 4186.821 | 0.047 % | < 0.5 % ✓ |
| 立方体 边长 10 | 1000.000 | 998.946 | 0.105 % | < 0.5 % ✓ |
| 圆台 底 8 / 高 10（顶收到 0） | 670.206 | 668.397 | 0.270 % | < 1 % ✓ |
| 胶囊 半径 4 / 段长 10 | 770.733 | 769.716 | 0.132 % | < 1 % ✓ |
| 环面 管 3 / 环 10 | 1776.528 | 1771.444 | 0.286 % | < 1 % ✓ |
| 立方体 40×30×20 减球 r=12 | 17046.608 | 17058.879 | 0.072 % | < 0.5 % ✓ |

圆台和胶囊的误差天然比球大：它们有尖锐的棱（圆台顶点的锥尖、胶囊的
圆柱-半球接缝），marching tetrahedra 在棱附近只能用细长三角逼近曲面。
0.27 % / 0.13 % 是 `res = 48` 下的实际水平，不是常数——加密到 128 会更小。

「减球」这一项唯一的解析值来自 `oracle.py`：球心在盒内、半径 12 小于盒的
最短半边长 10+ 的容积关系，挖掉的部分是一个完整的球，所以
`24000 − 4/3·π·12³ = 17046.608`。

## 拓扑：每个形状都必须是闭合流形

| 形状 | 水密 | χ | 亏格 |
| --- | --- | --- | --- |
| 球 / 立方体 / 圆台 / 胶囊 / 减球 | true | 2 | 0 |
| 环面 | true | 0 | 1 |

判定方式不是「看着像」：`is_watertight()` 检查每条边恰好被两个三角共用且
方向相反，`euler()` 是 `V − E + F`，亏格由 `(2 − χ) / 2` 得出。

## 浏览器侧

`node tools/build_web.mjs` 产出 `examples/web/web.wasm`（wasm-gc，release），
在 Node 里实例化后跑页面上同一套接口：

```
✓ 球体积误差 < 0.5%
✓ 水密
✓ 欧拉示性数 = 2
✓ 二进制 STL 往返
三角数 58944，体积 4186.820763715631
通过：4/4 项
```

页面本身（`node tools/serve.mjs` → http://127.0.0.1:8000/）在控制台打一行
可判定的结论，无头浏览器抓这一行就够：

```
mooncsg ok tris=26280 vol=4184.412 watertight=1
```

`tools/scene_check.mjs` 覆盖 demo 的 7 个场景（球/盒/圆台/退化圆台/胶囊/环面/减球），
每项都检查三角数、顶点数、体积、面积、水密、χ、包围盒跨度与实际格点。

## 性能

见 README「性能基线」：`res` 从 32 到 256（实际被收窄到 205³），单线程
wasm-gc 上 13.6 ms → 1713.8 ms，三角形从 2.6 万到 114 万。js 后端慢
2.1–3.0 倍。这两档大分辨率用 `moon run examples/bench --release -- big` 才会跑。

## 没覆盖到的

- **native 耗时**：本机无 MSVC，本表不编数字。CI 的 ubuntu runner 跑
  `moon test --target native` 做正确性覆盖。
- **高分辨率精度**：128³ / 205³ 只记录了耗时与三角形数，没有与解析值对拍
  （对拍成本主要在 `oracle.py` 侧，不是网格本身不可信）。
- **偏置挖球的解析体积**：球减偏移球是透镜形，没有写解析式，只验了水密、
  拓扑与包围盒收缩。
- **浏览器实机**：本机只验证到 Edge（`playwright screenshot --channel=msedge`）
  的截图与单行结论；Safari / Firefox 未测。
- **Pages 部署**：workflow 已提交，首次实际部署结果取决于仓库的 Pages 设置，
  不是本机能验的。

## 这些断言真的能失败吗

防止「跑通了就算」的退化。前两条是开发中真实踩到的，测试确实红过：

- 把 `Capsule` 的轴向折返写回 `|z| − h`：`capsule 解析距离` 与
  `capsule volume matches analytic` 失败（中段点算远约 0.4 个单位）。
- 把圆台体积期望值里的总高写成半高：`cone frustum volume` 差 2 倍
  （实测 3663 vs 期望 1831，探测负区域体积 3714 确认是期望值写错）。

后两条是按代码路径推的，没有手验：

- 去掉 `plan_grid` 里的 `MAX_GRID_SLOTS` 循环：`grid_shape clamps to
  MAX_GRID_SLOTS` 里 `slots <= 16777216` 那条断言会红。
- 去掉散度体积的朝向校正：`is_watertight` 仍为 true，但 `volume` 变负，
  体积比对与 STL 往返都会失败。
