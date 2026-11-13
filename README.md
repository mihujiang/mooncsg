# mooncsg

纯 MoonBit 的 3D 实体建模内核：有符号距离场（SDF）原语、CSG 布尔、
marching tetrahedra 网格化、OBJ / STL 导出。没有 FFI，没有第三方几何库。

目标是让「程序化生成一个能直接进切片软件的实体」这件事只依赖一份
可读的 MoonBit 代码——几何在数学上闭合（水密、朝向一致、体积可对数），
而不是「看起来像」。

## 现状

已覆盖 M0–M6：

- `vec.mbt`：`Vec3` / `Mat3` / `Aabb`
- `sdf.mbt`：球、盒、半空间、圆柱、环面；平移/旋转/缩放；并/交/差/平滑并；
  保守包围盒
- `marching.mbt`：规则体素 + 6 四面体分解 + 边键焊接 + 梯度投影
- `mesh.mbt`：散度体积、面积、水密判定、欧拉示性数 / 亏格（只对单个闭合壳
  有定义，多壳返回 `-1`）、FNV-1a 指纹
- `export.mbt`：OBJ、ASCII STL、二进制 STL，以及二进制 STL 回读
- `examples/web`：wasm 验收壳（页面 + `?selftest=1` 自动跑）
- `examples/bench`：网格化耗时基线（native / js / wasm-gc 同一份代码）
- `tools/oracle.py`：独立解析基准（只用标准库）
- `tools/wasm_check.mjs`：在 Node 里实例化同一份 wasm 跑验收
- `tools/acceptance.mjs`：一条命令跑全部验收项并打表

## 安装

已发布到 mooncakes（`weopqrst/mooncsg@0.1.1`）：

```bash
moon add weopqrst/mooncsg
```

效果等同在 `moon.mod` 里写：

```moonbit
import {
  "weopqrst/mooncsg@0.1.1",
}
```

再在调用方包的 `moon.pkg` 里加 `"weopqrst/mooncsg"`，即可用 `@mooncsg.` 前缀调用。

## 快速开始

```bash
moon test                 # 33 个测试（native / js / wasm-gc 都要跑）
moon run examples/demo    # 盒减球，打印体积/面积/拓扑
moon run examples/bench --release   # 网格化耗时基线
moon check --deny-warn
moon fmt --check

# 浏览器验收壳
node tools/build_web.mjs  # 编译 wasm 并复制到 examples/web/
node tools/serve.mjs      # 打开 http://localhost:8000/?selftest=1
node tools/wasm_check.mjs # 不开浏览器，在 Node 里跑同一份 wasm

# 一次跑完全部验收项（check/fmt/三后端测试/package/demo/web/oracle）
node tools/acceptance.mjs
```

`examples/demo` 的输出（盒减球，48 分辨率）：

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

| 用例 | 三角形 | wasm-gc | js |
| --- | --- | --- | --- |
| 球 r=10，32³ | 26280 | 13.1 ms | 37.6 ms |
| 球 r=10，64³ | 104688 | 64.1 ms | 165.1 ms |
| 立方体 40³ 挖球 r=24，48³ | 107280 | 87.5 ms | 220.1 ms |
| 环面 R=8 r=3，48³ | 36172 | 20.3 ms | 40.5 ms |

两点说明：

- **wasm-gc 比 js 后端快 1.9–2.9 倍**，这是同一份 MoonBit 源码换后端的结果，
  不是两份实现——wasm-gc 直接吃 `f64` 运算，js 后端还要过一层 BigInt/boxing 的
  边界检查。
- **native 数字本地没有**：这台 Windows 机器没装 MSVC Build Tools，native 后端
  整体不可用（`tools/acceptance.mjs` 会把它判成 SKIP 而不是 FAIL）。CI 的
  ubuntu runner 上 `moon test --target native` 会跑，所以 native 的正确性有
  持续覆盖，只是没有本地耗时对照。本表不编 native 的数。

## 验收口径

每条断言都能把当前代码判为失败，不是「跑通了就算」：

| 判据 | 测试 |
| --- | --- |
| 4 个原语在 1000 个随机点上与解析距离误差 < 1e-12 | `sdf_test.mbt` |
| 布尔与 `min` / `max` / 取负逐点一致 | `sdf_test.mbt` |
| 球体积误差 < 0.5%（128 分辨率）、盒 < 1%（40 分辨率） | `mesh_test.mbt` |
| 环面亏格 = 1、欧拉示性数 = 0 | `mesh_test.mbt` |
| 盒挖两个贯通孔后亏格 = 2、欧拉示性数 = -2、体积误差 < 0.5% | `mesh_test.mbt` |
| 盒减球体积与球带公式误差 < 1% | `mesh_test.mbt` |
| 完全被挖空时输出空网格 | `mesh_test.mbt` |
| 相切球、零厚度板、空交集、贴面格点、退化包围盒、超低分辨率都不崩 | `mesh_test.mbt` |
| 等值面正好落在格点上时仍水密、体积误差 < 1% | `mesh_test.mbt` |
| 每条无向边恰好 2 个面（水密） | `mesh_test.mbt` |
| 同输入两次网格化逐位相同 | `mesh_test.mbt` |
| 网格指纹等于常量 7885752854646016839（js / wasm-gc 本地跑，native 在 CI 跑，三后端同值） | `mesh_test.mbt` |
| 分辨率或朝向变化时指纹必然改变（指纹确实覆盖几何与拓扑） | `mesh_test.mbt` |
| OBJ/ASCII STL 行数与索引范围、字节级确定性 | `export_test.mbt` |
| 二进制 STL 往返后三角数/顶点数/欧拉示性数不变、体积相对误差 < 1e-6 | `export_test.mbt` |
| 截断的二进制 STL 返回 `None` 而不是越界 | `export_test.mbt` |
| wasm 验收壳 4/4 通过（Node 与浏览器同一份 wasm） | `tools/wasm_check.mjs` |
| 全部验收项一条命令跑完（check/fmt/三后端测试/package/demo/web/oracle） | `tools/acceptance.mjs` |

`tools/oracle.py` 用 Python 标准库手算同样的解析值，CI 里单独跑一遍，
避免「期望值是从被测实现抄来的」。

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
- 半空间没有有限包围盒，单独网格化需要调用方给范围。
- 只有均匀缩放；非均匀缩放会让 SDF 不再是距离场（需要除以梯度模）。
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
