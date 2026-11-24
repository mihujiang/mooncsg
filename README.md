# mooncsg

纯 MoonBit 的 3D 实体建模内核：有符号距离场（SDF）原语、CSG 布尔、
marching tetrahedra 网格化、OBJ / STL 导出。没有 FFI，没有第三方几何库。

目标是让「程序化生成一个能直接进切片软件的实体」这件事只依赖一份
可读的 MoonBit 代码——几何在数学上闭合（水密、朝向一致、体积可对数），
而不是「看起来像」。闭合不是无条件承诺：`mesh_checked` 先判定输入是否
满足条件，不满足就拒绝，范围见下文「可打印保证的范围」。

在线演示：<https://mihujiang.github.io/mooncsg/>　　实测数字：见 [`ACCEPTANCE.md`](ACCEPTANCE.md)

> 演示站点由 `.github/workflows/pages.yml` 部署，仓库的 Pages Source 已设为
> “GitHub Actions”，改到 `examples/web/**` 或 `*.mbt` 的 push 会自动重建并部署。
> 首次启用必须手点一次这个开关：`GITHUB_TOKEN` 没有 admin 权限，
> `configure-pages` 的 `enablement: true` 会 403。

## 现状

已覆盖 M0–M6：

- `vec.mbt`：`Vec3` / `Mat3` / `Aabb`
- `sdf.mbt`：球、盒、半空间、圆柱、圆台、胶囊、环面；平移/矩阵旋转/缩放；
  并/交/差/平滑并；包围盒；法线优先走解析梯度（无闭式的节点回退中心差分）
- `marching.mbt`：规则体素 + 6 四面体分解 + 边键焊接 + 梯度投影；
  `mesh_checked` 的采样域前置检查与拒绝语义（`mesh` / `mesh_unchecked` 不检查）
- `mesh.mbt`：散度体积、面积、水密判定、欧拉示性数 / 亏格（只对单个闭合壳
  有定义，多壳返回 `-1`）、连通壳拆分（`shell_count` / `shells` /
  `largest_shell`）、一次性体检（`audit` → `MeshAudit`，含 JSON）、FNV-1a 指纹
- `export.mbt`：OBJ、ASCII STL、二进制 STL，以及二进制 STL 回读
- `examples/web`：交互 demo（调参 → 网格 → canvas 2D 软件投影 + 体积/面积/拓扑），
  页面里带 `?selftest=1` 的验收路径
- `examples/bench`：网格化耗时基线（native / js / wasm-gc 同一份代码）
- `tools/oracle.py`：独立解析基准（只用标准库），`--cases` 给出对拍用例
- `tools/volume_check.mjs`：把 oracle 的解析体积和 `cmd/main --stats` 的实测值逐组比阈值
- `tools/guard_check.mjs`：CLI 边界语义门禁（正常输入必须闭合，半空间 / 裁剪 / 空域必须被拒）
- `tools/wasm_check.mjs`：在 Node 里实例化同一份 wasm 跑验收
- `tools/scene_check.mjs`：在 Node 里校验交互 demo 的 wasm 接口（建网格/读坐标/读指标）
- `tools/serve.mjs`：本地静态服务，`node tools/serve.mjs` → http://127.0.0.1:8000/
- `tools/acceptance.mjs`：一条命令跑全部验收项并打表
- `tools/publish.mjs`：发布 + 发布后回拉验证（见下）

## 安装

已发布到 mooncakes（`weopqrst/mooncsg@0.1.9`）：

```bash
moon add weopqrst/mooncsg
```

效果等同在 `moon.mod` 里写：

```moonbit
import {
  "weopqrst/mooncsg@0.1.9",
}
```

再在调用方包的 `moon.pkg` 里加 `"weopqrst/mooncsg"`，即可用 `@mooncsg.` 前缀调用。

## 快速开始

```bash
moon test                 # 63 个 test 块，wasm-gc / js / native 三后端都要跑
moon run examples/demo    # 盒减球，打印体积/面积/拓扑
moon run examples/bench --release   # 网格化耗时基线
moon check --deny-warn
moon fmt --check

# 边界语义的两端：能保证的与必须拒绝的
moon run cmd/main -- sphere 10 --res 32 > s.stl   # exit 0：闭合可切片
moon run cmd/main -- sphere 10 --res 32 --audit   # JSON 体检：水密/流形/壳数/亏格/告警
moon run cmd/main -- plane 0 0 1 0 --stats        # exit 1：半空间没有有限包围盒
moon run cmd/main -- sphere 10 --bounds -10.5,-10.5,-10.5,2,10.5,10.5 --stats
                                                  # exit 1：采样域被实体穿出
moon run cmd/main -- sphere 10 --bounds -10.5,-10.5,-10.5,2,10.5,10.5 --clip --stats
                                                  # exit 0：明确声明 watertight=false

# 交互 demo（调参 + canvas 投影）
node tools/build_web.mjs  # 编译 wasm 并复制到 examples/web/
node tools/serve.mjs      # 打开 http://127.0.0.1:8000/
node tools/wasm_check.mjs # 不开浏览器，在 Node 里跑同一份 wasm 的验收项
node tools/scene_check.mjs # 在 Node 里跑 demo 用到的场景接口
node tools/guard_check.mjs # 边界语义门禁：正常输入闭合，半空间/裁剪/空域必须被拒

# 一次跑完全部验收项（13 项：check/fmt/三后端测试/package/demo/bench/web/边界语义/体积对拍）
node tools/acceptance.mjs
```

交互 demo 的形状与参数：球（半径）、立方体（边长）、圆台（底半径 + 高）、
胶囊（半径 + 圆柱段长）、环面（管半径 + 环半径），外加「减去偏移球」的挖切；
拖拽旋转、滚轮缩放、双击复位。分辨率滑杆控制的是请求值，指标区显示的是
**实际**格点数（超过 `MAX_GRID_SLOTS` 会被自动收窄，见下）。

`examples/demo` 的输出（40³ 盒减球 r=12，`res = 64`）：

```
triangles:  126484
vertices:   63242

volume:     17058.878927955866
area:       6336.3007417442195
watertight: true
euler:      0 (genus 1)
obj bytes:  4577832
stl bytes:  26192644

预期体积（解析）：24000 - 2*pi*10*(144 - 100/3) = 17046.6
```

体积相对误差 0.07%。

## 性能基线

`moon run examples/bench --release` 走 `moonbitlang/core/bench` 的单调时钟
（native 绑 `clock_gettime`，wasm 绑 `time_unstable.instant_now`，微秒），
先跑一次预热，再取三次的最小值。机器：Intel Core Ultra 9 275HX / Windows 11 /
Node 24（wasm-gc 与 js 都跑在 V8 上）。

「实际格点」一列是 `grid_shape()` 报的值：`resolution` 只是请求值，超过
`MAX_GRID_SLOTS`（16.7M 个采样点）会被按 1.25 倍步长收窄。所以请求 256 的
立方包围盒实际跑的是 205³——表里照实写。

| 用例 | 三角形 | 实际格点 | wasm-gc | js |
| --- | --- | --- | --- | --- |
| 球 r=10，请求 32 | 26280 | 32³ | 13.9 ms | 35.2 ms |
| 球 r=10，请求 64 | 104688 | 64³ | 68.3 ms | 175.0 ms |
| 立方体 40³ 挖球 r=24，请求 48 | 107280 | 48³ | 90.7 ms | 233.5 ms |
| 环面 R=8 r=3，请求 48 | 36172 | 48×48×15 | 20.6 ms | 45.3 ms |
| 球 r=25，请求 128 | 443736 | 128³ | 404.5 ms | 981.1 ms |
| 球 r=25，请求 256 | 1135968 | **205³**（被收窄） | 1419.9 ms | 3270.0 ms |

后两行用 `moon run examples/bench --release -- big` 才跑（默认不跑，js 后端
那两档要几秒，塞进 CI 会把 bench 这条 step 拖成分钟级）。

两点说明：

- **wasm-gc 比 js 后端快 2.2–2.6 倍**，这是同一份 MoonBit 源码换后端的结果，
  不是两份实现——wasm-gc 直接吃 `f64` 运算，js 后端还要过一层 BigInt/boxing 的
  边界检查。
- **native 数字本地没有**：这台 Windows 机器没装 MSVC Build Tools，native 后端
  整体不可用（`tools/acceptance.mjs` 会把它判成 SKIP 而不是 FAIL）。CI 的
  ubuntu runner 上 `moon test --target native` 会跑，所以 native 的正确性有
  持续覆盖，只是没有本地耗时对照。本表不编 native 的数。

## 可打印保证的范围

「水密」不是形容词，而是**可判定的输入条件**加**可验证的输出性质**。
`mesh_checked` 是唯一给出保证的入口，其余情况一律拒绝：

| 前置条件（逐条检查） | 不满足时的处置 |
| --- | --- |
| 采样域各轴长度 > 0、坐标有限 | `DegenerateBounds` |
| 采样点场值处处有限（无 NaN / Inf） | `NonFiniteField(点)` |
| 实体**严格位于**采样域内部：6 个面上的采样点全部 `f > 0` | `SurfaceClipped(点, 场值)` |
| 采样域内确实存在内部点 | `NoSurface` |
| **后置自检**：网格生成后 `open_edges() == 0` | `NotClosed(开口边数)` |

通过检查的输出保证：每条无向边恰好被 2 个三角形共享（`is_watertight()`）、
`open_edges() == 0`、体积为正、朝向朝外。更严的一层是 `is_manifold()`
（每条边 2 面 **且** 每个顶点的星形是一个环），它蕴含 `is_watertight()`
但**不在** `mesh_checked` 的承诺范围内，需要时自己调。

这个结论不只靠论证：`mesh_checked` 生成网格后会再跑一次**后置自检**
（`open_edges() == 0`），不满足就返回 `NotClosed(边数)`。代价是多一次
`O(F log F)` 的边排序；收益是「前置条件 ⇒ 闭合」这条推理哪天真不成立时，
只会得到错误，不会得到一块开口网格。两层是独立的——把前置的边界检查关掉，
后置自检仍会以 `NotClosed` 拒绝（实测 402 条开口边，与 `--clip` 报出的数字
一致）。

**为什么第 3 条是充要条件、不是保守估计**：三角形只在相邻四面体之间按
「格点索引对」配对焊接，曲面上的每个顶点都落在一条两端格点异号的边上。
若某条边的两端都贴着采样域边界，曲面就是从边界穿出去的——那个顶点在域内
找不到对侧三角形，边界处必然留开口。反过来，边界全正意味着曲面整块在
内部，每个顶点都能在域内找到对侧三角形，于是「闭合」是构造保证，不是
概率。

### 具体到几类输入

| 输入 | 输出 / 拒绝条件 |
| --- | --- |
| 球 / 盒 / 圆柱 / 圆台 / 胶囊 / 环面（有界原语） | 默认采样域 `bounds().expand(0.5)` ⇒ 通过，闭合 |
| 原语的布尔组合（并 / 交 / 差 / 平滑并） | 同上；包围盒由运算各自收紧，平滑并额外外扩 `k/2` |
| **半空间** `plane` | `bounds() == None` ⇒ 拒绝 `Unbounded`；CLI 要求用 `--bounds` 给出有界域 |
| 半空间 + 有界域 | 域边界上必然出现 `f <= 0` ⇒ 拒绝 `SurfaceClipped`——半空间在有限域内闭不了 |
| **实体与域面相切**（球心落在域面上） | 边界采样 `f == 0` ⇒ 拒绝（判据 `f <= 0` 含相等） |
| **两个实体相切**（两球外切后取并） | 通过：接触点是梯度奇点，那一带三角形极细，体积比解析值小 0.8 %，但拓扑闭合 |
| **采样域小于实体**（被裁剪） | 默认拒绝；显式要裁剪网格时用 `--clip`（或 `mesh_unchecked`），此时 `watertight=false`、`open_edges` 给出开口边数 |
| 域与实体完全不重叠 | 拒绝 `NoSurface`，不把空网格当成功 |
| 退化参数（`scale(0)`、NaN 半径） | 采样到 Inf/NaN ⇒ 拒绝 `NonFiniteField` |

实测（`node tools/guard_check.mjs`，CI 里的第 13 项门禁）：

| 场景 | 退出码 | 关键输出 |
| --- | --- | --- |
| 球 r=10，自动采样域 | 0 | `watertight: true`、`open_edges: 0` |
| 半空间，无域 | 1 | 没有有限包围盒，提示用 `--bounds` |
| 半空间 + 有界域 | 1 | 采样域被实体穿过：边界点 `(-10,-10,-10)` 场值 `-10` |
| 域小于实体（裁一半） | 1 | 采样域被实体穿过：场值 `-0.015` |
| 同一输入加 `--clip` | 0 | `watertight: false`、`open_edges: 402` |
| 域离实体很远 | 1 | 采样域内没有曲面 |

### 明确不保证的

- **薄壳**：壁厚小于约 1 个体素时，格点采样漏掉壁内的负区，内腔表面被当成
  实体边界——网格**仍然水密、仍然流形**，但体积**偏大**（实测壁厚 0.2 / 体素
  0.66 时是解析值的 29 倍，壁厚 0.6 时误差 0.1 %）。`NotClosed` 兜不住这类，
  看 `audit()` 的壳数告警，或拿解析体积对拍。加密 `--res` 到壁厚以下即可。
- **非精确 SDF**（`|∇f|` 明显偏离 1）：拓扑仍闭合，但体积与法线有偏差。
- **自交实体**（环面管半径 ≥ 母线半径、`subtract` 挖成非流形）：输出闭合，
  但不是合法实体，切片器会拒绝。
- **多壳**：`is_watertight` 对多个不相交壳仍为真（每条边 2 面），但
  `genus()` 返回 `-1` 表示「单壳亏格不可用」——它现在真的数壳，不靠 `χ` 猜
  （两个环面 `χ` 都是 0，加起来还是 0）。壳数看 `shell_count()`，要逐壳亏格先
  `shells()`，只要主体就 `largest_shell()`。多壳本身仍是流形，`is_manifold()`
  为真——它拒的是两瓣只在**一个顶点**相触（星形分成两个环）。
- **非流形顶点**：两瓣实体共用一个顶点（手搓网格、或 STL 导入按坐标焊接后把
  相切的两瓣焊到同一点）时，`is_watertight()` 仍为真，`is_manifold()` 为假。
  本库的 `union` 不会产生这种网格（两球外切取并是两块独立的壳），所以
  `mesh_checked` 不拦它；从外部导入的网格要自己查。

## 验收口径

每条断言都能把当前代码判为失败，不是「跑通了就算」：

| 判据 | 测试 |
| --- | --- |
| 球/盒各 1000 个随机点、圆柱 / 平面 / 圆台 / 胶囊的解析距离误差 < 1e-12，环面按参数化构造点对拍 | `sdf_test.mbt` |
| 梯度模长为 1，且沿法线走 `t` 距离正好变 `t`（球 / 盒 / 圆柱 / 胶囊 / 环面 / 旋转后的球，各 200 个随机点） | `sdf_test.mbt` |
| 布尔与 `min` / `max` / 取负逐点一致 | `sdf_test.mbt` |
| 球体积误差 < 0.5%（128 分辨率）、盒 < 1%（40 分辨率） | `mesh_test.mbt` |
| 环面亏格 = 1、欧拉示性数 = 0 | `mesh_test.mbt` |
| 盒挖两个贯通孔后亏格 = 2、欧拉示性数 = -2、体积误差 < 0.5% | `mesh_test.mbt` |
| 盒减球体积与球带公式误差 < 1% | `mesh_test.mbt` |
| 完全被挖空时输出空网格 | `mesh_test.mbt` |
| 相切球、零厚度板、空交集、贴面格点、退化包围盒、超低分辨率都不崩 | `mesh_test.mbt` |
| 等值面正好落在格点上时仍水密、体积误差 < 1% | `mesh_test.mbt` |
| 每条无向边恰好 2 个面（水密） | `mesh_test.mbt` |
| 四面体闭合流形为真；两个四面体共用一个顶点时 `is_watertight` 真但 `is_manifold` 假 | `mesh_test.mbt` |
| 一条边挂 3 个面、去掉一个面的开口网格、空网格的 `is_manifold` 结果 | `mesh_test.mbt` |
| 两个不相交环面 → 2 壳、整体亏格 -1、各壳亏格 1；`largest_shell` 丢掉远处碎屑后仍是单壳 | `mesh_test.mbt` |
| `audit()` 对干净实体零告警、对多壳与开口给告警，JSON 字段与实测一致 | `mesh_test.mbt` |
| 壁厚小于 1 个体素时体积偏大但仍水密；同形状加密后回到 5 % 以内 | `mesh_test.mbt` |
| 矩阵旋转的矩阵正交性自检：旋转阵为真，拉伸 / 剪切 / 零矩阵为假 | `sdf_test.mbt` |
| `mesh_checked` 对相切 / 裁剪 / 空域 / 退化域 / 非有限场值分别返回对应错误 | `marching_test.mbt` |
| 60 个随机实体在 `bounds().expand(0.5)` 下全部闭合、`open_edges == 0` | `marching_test.mbt` |
| 两球外切后的并集仍闭合（体积误差 0.8 %），与「相切采样域必须拒绝」并列 | `marching_test.mbt` |
| 同输入两次网格化逐位相同 | `mesh_test.mbt` |
| 网格指纹等于常量 7885752854646016839（js / wasm-gc 本地跑，native 在 CI 跑，三后端同值） | `mesh_test.mbt` |
| 分辨率或朝向变化时指纹必然改变（指纹确实覆盖几何与拓扑） | `mesh_test.mbt` |
| OBJ/ASCII STL 行数与索引范围、字节级确定性 | `export_test.mbt` |
| 二进制 STL 往返后三角数/顶点数/欧拉示性数不变、体积相对误差 < 1e-6 | `export_test.mbt` |
| 截断的二进制 STL 返回 `None` 而不是越界 | `export_test.mbt` |
| wasm 验收壳 4/4 通过（Node 与浏览器同一份 wasm） | `tools/wasm_check.mjs` |
| CLI 边界语义：正常输入 exit 0 且闭合；半空间 / 裁剪 / 空域 exit ≠ 0；`--clip` 声明开口 | `tools/guard_check.mjs` |
| 全部验收项一条命令跑完（13 项，含边界语义与体积对拍） | `tools/acceptance.mjs` |

`tools/oracle.py` 用 Python 标准库手算解析值，`tools/volume_check.mjs` 把它和
`cmd/main --stats` 的实测体积逐组比阈值——只跑 oracle.py 没意义（它打印完就
exit 0），所以 CI 里跑的是后者，超差直接红。

## 设计要点

**`f == 0` 一律算外部。** 边界点归外部，插值参数再夹到 `t ∈ [1e-6, 1-1e-6]`
（按边长比例，与体素尺寸无关），避免零面积三角形；否则同一格点会在相邻
体素里被两边都算一次，网格出现重面。

**焊接不靠 eps 量化。** 交点的键是「两个格点索引的 min/max」：同一条
几何边无论从哪个四面体、哪个方向被访问都得到同一个键，位置也统一按
`min -> max` 方向插值。于是焊接是精确的，而 `O(1)` 查表不依赖哈希遍历顺序。

**绕向用顶点梯度，不用格点当参考。** 格点可能恰好贴着等值面，参考方向会
被浮点噪声决定；顶点就在面上，梯度就是外法线。逐面判定后仍保留
「体积为负则整体翻转」的兜底。

**四面体对角固定。** 立方体只沿 `(0,0,0)-(1,1,1)` 拆 6 个四面体。
换一种拆分，同一 SDF 同一分辨率会得到不同三角数，体积就不可比。

**网格化是确定性的。** 固定遍历顺序、固定四面体表、固定排序（自写归并），
不使用哈希迭代顺序决定输出顺序。这份确定性是可验证的：`Mesh::hash()` 把
顶点位模式与索引序列压成 FNV-1a 64 位指纹，测试用常量断言，native / js /
wasm-gc 三个后端必须算出同一个数。

## 已知限制

- 体积与面积是结果度量，不是约束求解；没有做保体积简化（decimation）。
- 半空间没有有限包围盒，单独网格化必须先给 `--bounds`；给了也会因「曲面从域边界
  穿出」被拒绝——半空间只有和别的形状做布尔（例如与盒求交）才构成有界实体。
- 只有均匀缩放；非均匀缩放会让 SDF 不再是距离场（需要除以梯度模）。旋转要
  自己给矩阵（`Sdf::rotate`），core 没有三角函数，转完可以用
  `Mat3::is_orthonormal` 自检——非正交矩阵不会报错，只会让距离场被拉伸。
- 二进制 STL 的坐标是 `f32`，这是格式限制；要更高精度请用 OBJ。
- 回读只做了二进制 STL（OBJ 回读需要文本数字解析，暂缓）。
- 没有 BVH / 距离查询加速，`eval` 直接遍历树；雏版靠分辨率控制成本。
- `resolution` 上限 512，且总格点另有 `MAX_GRID_SLOTS`（16.7M）收紧：
  512 的立方包围盒实际按约 253³ 采样（场数组约 134 MB），再大就该分块
  或换稀疏/自适应表示，而不是继续加分辨率。

## 许可

Apache-2.0。

更细的取舍说明（每个文件「为什么长这样」、验收策略、AI 参与与验证流程）见
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)，版本变更见
[`CHANGELOG.md`](CHANGELOG.md)。
