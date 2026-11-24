# 验收记录

本文件记录 **0.1.9** 这一版实际跑出来的数字。所有数值都来自下面这条命令，
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

实际输出（2026-11-24）：

```
PASS  check          788 ms
PASS  fmt            246 ms
SKIP  test native    本机无 native 工具链
PASS  test wasm-gc   10047 ms
PASS  test js        15953 ms
PASS  package        920 ms
PASS  demo           1059 ms
PASS  bench          826 ms
PASS  build web      205 ms
PASS  wasm selftest  410 ms
PASS  wasm scene     1574 ms
PASS  guard check    1901 ms
PASS  volume check   3512 ms

没有失败项（共 13 项）
```

毫秒列随机器负载浮动，判定只看 PASS / SKIP 两列。

`test wasm-gc` / `test js` 内部都是 `Total tests: 63, passed: 63, failed: 0.`
——源码里 63 个 `test` 块，当前工具链按块计数（一块一个用例），块内逐条
`assert_*` 断言，任一条红整块就红。

## 可打印保证：输入条件与拒绝语义

`mesh_checked` 只在四条前置条件同时成立时返回网格，否则返回一个具体错误；
CLI 默认走它，错误以非零退出码表达，不产出文件。

| 前置条件 | 不满足时 |
| --- | --- |
| 采样域各轴长度 > 0、坐标有限 | `DegenerateBounds` |
| 场值处处有限（无 NaN / Inf） | `NonFiniteField` |
| 采样域 6 个面上的采样点全部 `f > 0` | `SurfaceClipped` |
| 采样域内存在内部点 | `NoSurface` |
| 后置自检：生成后 `open_edges() == 0` | `NotClosed(边数)` |

`node tools/guard_check.mjs` 用真实 CLI 输入把这张表钉死（CI 第 13 项）：

```
场景                    耗时      判定
--------------------  ------  --
正常球（自动采样域）            462 ms  ✓
半空间：无界，拒绝             151 ms  ✓
半空间 + 有界域：穿过边界，拒绝     158 ms  ✓
域小于实体：拒绝              160 ms  ✓
同一输入加 --clip：输出并声明开口  525 ms  ✓
域离实体很远：拒绝             250 ms  ✓

通过：6/6 个边界场景
```

具体到几条命令：

| 命令 | 退出码 | 关键输出 |
| --- | --- | --- |
| `sphere 10 --stats` | 0 | `watertight: true`、`open_edges: 0` |
| `sphere 10 --bounds -10.5,-10.5,-10.5,2,10.5,10.5 --stats` | 1 | 采样域被实体穿过：边界点场值 `-0.015` |
| 同上加 `--clip` | 0 | `watertight: false`、`open_edges: 402` |
| `plane 0 0 1 0 --stats` | 1 | 没有有限包围盒 |
| `plane 0 0 1 0 --bounds -10,-10,-10,10,10,10 --stats` | 1 | 边界点 `(-10,-10,-10)` 场值 `-10` |
| `sphere 1 --bounds 100,100,100,110,110,110 --stats` | 1 | 采样域内没有曲面 |

`--clip` 是显式放弃保证的开关：输出仍是合法三角网格，但不闭合、不能直接
切片，`watertight` 为 false，`open_edges` 给出开口边数。

「相切」要分两种，结论相反：

- **相切采样域**：球盒不加 `expand`，曲面正好落在 6 个面上，边界采样
  `f == 0`，判据 `f <= 0` 含相等，所以直接拒绝（`marching_test.mbt`）。
- **相切实体**：两个半径 5 的球外切（球心距 10）后取并，接触点是梯度不连续
  的奇点，但拓扑仍闭合，`mesh_checked` 返回 Ok、`open_edges == 0`；体积
  1039.1 比解析值 1047.2 小 0.8 %（接触点被采样平滑掉，属精度问题）。
  这条也在 `marching_test.mbt` 里。

## 精度：实测 vs 解析

网格一律用 `resolution = 48`（`grid_shape` 报 48³，未被 `MAX_GRID_SLOTS` 收窄），
体积由散度定理在三角网格上精确累加，解析值由 `tools/oracle.py`（纯标准库，
独立实现）给出，`node tools/volume_check.mjs` 把两边逐组比阈值（球/盒/减球
0.5 %，圆台/胶囊/环面 1 %），超差就退出非 0——这一项 PASS 是真的判过阈值，
不是「脚本能跑」。

| 形状 | 解析体积 | 实测体积 | 相对误差 | 判定 |
| --- | --- | --- | --- | --- |
| 球 r=10 | 4188.790 | 4186.821 | 0.047 % | < 0.5 % ✓ |
| 立方体 边长 10 | 1000.000 | 998.946 | 0.105 % | < 0.5 % ✓ |
| 圆台 底 8 / 高 10（顶收到 0） | 670.206 | 668.515 | 0.252 % | < 1 % ✓ |
| 胶囊 半径 4 / 段长 10 | 770.737 | 769.716 | 0.132 % | < 1 % ✓ |
| 环面 管 3 / 环 10 | 1776.529 | 1771.444 | 0.286 % | < 1 % ✓ |
| 立方体 40×30×20 减球 r=12 | 17046.608 | 17058.106 | 0.067 % | < 0.5 % ✓ |

圆台和胶囊的误差天然比球大：它们有尖锐的棱（圆台顶点的锥尖、胶囊的
圆柱-半球接缝），marching tetrahedra 在棱附近只能用细长三角逼近曲面。
0.25 % / 0.13 % 是 `res = 48` 下的实际水平，不是常数——加密到 128 会更小。

「减球」这一项的解析值来自 `oracle.py` 的 `box_minus_sphere`：球半径 12
大于盒半高 10，球在 z 方向穿出盒外，挖掉的不是整球而是被 `z = ±10` 两个
平面夹住的**球带**，`V = 2πa(r² − a²/3)`（`a = 10`），所以
`24000 − 2π·10·(144 − 100/3) = 17046.608`。`examples/demo` 打印的就是这个式子。

## 拓扑：每个形状都必须是闭合流形

| 形状 | 水密 | 流形 | χ | 亏格 |
| --- | --- | --- | --- | --- |
| 球 / 立方体 / 圆台 / 胶囊 / 减球 | true | true | 2 | 0 |
| 环面 | true | true | 0 | 1 |

判定方式不是「看着像」：`is_watertight()` 检查每条边恰好被两个三角共用且
方向相反，`is_manifold()` 再查每个顶点的星形是一个环（比 `is_watertight()`
严，能抓出「两瓣只在一个顶点相触」），`euler()` 是 `V − E + F`，亏格由
`(2 − χ) / 2` 得出。

`is_manifold()` 不是 `mesh_checked` 的承诺：本库 `union` 两球外切时输出的
是两块独立壳（χ = 4），不会产生共用顶点的 pinch；这类网格只从外部导入
（STL 按坐标焊接）或手搓数据里来，`mesh_test.mbt` 用两个共顶点的四面体钉住
这个判据（水密为真、流形为假）。

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
wasm-gc 上 13.9 ms → 1419.9 ms，三角形从 2.6 万到 114 万。js 后端慢
2.2–2.6 倍。这两档大分辨率用 `moon run examples/bench --release -- big` 才会跑。

## 没覆盖到的

- **native 耗时**：本机无 MSVC，本表不编数字。CI 的 ubuntu runner 跑
  `moon test --target native` 做正确性覆盖。
- **高分辨率精度**：128³ / 205³ 只记录了耗时与三角形数，没有进对拍表——
  单档要跑几十秒，`volume_check.mjs` 固定在 `res = 48`。
- **偏置挖球的解析体积**：球减偏移球是透镜形，没有写解析式，只验了水密、
  拓扑与包围盒收缩。
- **薄壳与自交**：`mesh_checked` 的前置条件只覆盖「采样域包住实体」，不覆盖
  「壁厚小于约 1 个体素」与「自交」（闭合但不可打印）。薄壳的失败方式不是空
  网格而是**体积偏大**：内腔表面被当成实体边界，网格仍水密仍流形，`NotClosed`
  兜不住，只能靠 `audit()` 的壳数告警或与解析体积对拍。实测记录在
  `mesh_test.mbt` 的 `thin wall inflates volume while staying watertight`（壁厚
  0.2 / 体素 0.66 时体积是解析值的 29 倍，壁厚 0.6 时误差 0.1 %）。
- **浏览器实机**：本机只验证到 Edge（`playwright screenshot --channel=msedge`）
  的截图与单行结论；Safari / Firefox 未测。
- **Pages 部署**：已上线 <https://mihujiang.github.io/mooncsg/>（run 在
  `6e3cbfb` 上 success）。首轮失败是因为仓库没启用 Pages（`configure-pages`
  报 Get Pages site failed），在 Settings → Pages → Source 选 “GitHub Actions”
  之后重跑即通过。

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

边界语义的两条，同样是「改一行就红」：

- 把 `check_field` 的边界判据从 `f <= 0.0` 放宽成 `f < 0.0`：相切测试
  （球盒不加 `expand`，边界采样恰好 `f == 0`）会失败。
- 让 `mesh_checked` 直接返回 `assemble_mesh` 的结果、不做任何检查：
  `marching_test` 里四个拒绝用例全部失败，`guard_check` 的三个 exit 1
  场景会变成 exit 0，CI 直接红。
- **双层防御实测**：只把前置的边界检查关掉（判据改成 `f < -1e300`），
  被裁剪的那条命令仍然 exit 1，只是错误从「采样域被实体穿过」变成了
  「网格未闭合：402 条边的相邻面数不是 2」——402 与 `--clip` 报出的
  `open_edges` 是同一个数。说明后置自检能独立兜住前置检查的失效。
