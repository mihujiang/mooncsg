# CHANGELOG

按里程碑记录，每条都挂 commit。版本号按 mooncakes 的 0.x 规则走。

## 未发布

### Fixed

- `export_test.mbt` 里的 `Bytes::new(10)` 从 moon 0.1.20261117 起是
  `deprecated[0020]`，CI 的 `moon check --deny-warn` 因此在 `0f0f50a` 上失败。
  改成 `Bytes::make(10, b'\x00')`，语义不变（10 个零字节，仍短于 84 字节的
  二进制 STL 头）。本地工具链（0.1.20261021）两个 API 都接受，所以本地没提前
  发现——这类「上游新增的弃用诊断」只能靠 CI 用最新工具链兜住。

## 0.1.5 — 2026-11-18

### Added

- **`mesh_checked`**：网格化前先判定四条前置条件——采样域各轴长度为正、
  场值处处有限、实体严格位于采样域内部、域内确有曲面；不满足返回
  `MeshError`（`Unbounded` / `DegenerateBounds` / `NonFiniteField` /
  `SurfaceClipped` / `NoSurface`）。通过即保证闭合，不做「看起来能用」的
  降级。
- **`mesh_unchecked`**：明确不检查的底层入口；`mesh` 成为它的别名，保持
  0.1.x 调用方可用。
- **`Mesh::open_edges`**：开口边数，用于量化 `--clip` 裁剪网格的开口大小。
- **CLI `--bounds` / `--clip` / `plane`**：显式采样域、显式放弃可切片保证、
  半空间形状。拒绝时以非零退出码结束，不产出文件。
- **`tools/guard_check.mjs`**：6 个边界场景门禁（正常闭合、半空间无域拒绝、
  半空间有域拒绝、裁剪拒绝、`--clip` 声明开口、空域拒绝），进 acceptance
  与 CI。
- 测试：相切、裁剪、半空间、非有限场值、空域、退化域各一条，外加「60 个
  随机实体在默认采样域下全部闭合」的实证。

### Changed

- **口径**：README / ACCEPTANCE / 申报书不再写无限定的「一定水密、可直接
  切片」，改为「可打印保证的范围」表——输入到通过 / 拒绝条件，以及明确
  不保证的薄壳、非精确 SDF、自交。检查为何是充要条件写进 ARCHITECTURE。
- `--stats` 多一行 `open_edges`；验收从 12 项变 13 项；测试 50 块 / 225 用例；
  公开 API 77 项。

## 0.1.4 — 2026-11-16

### Added

- **`tools/volume_check.mjs`**：体积对拍真的比阈值。原来 acceptance 里那一步
  只跑 `python tools/oracle.py`，打印完就 exit 0——PASS 不代表任何事；现在跑
  `cmd/main --stats` 拿实测体积，和 `oracle.py --cases` 的解析值逐组比容差，
  超差退出 1。
- **`LICENSE`**：Apache-2.0 全文（此前只有 `moon.mod` 的 `license` 字段）。
- **`Sdf::torus`**：环面终于有了与其它六个原语对称的构造函数（此前只能用
  `Sdf::Torus(...)` 枚举字面量，`pkg.generated.mbti` 里看不见）。
- **环面的参数化对拍**：500 个 `P + t·n` 构造点，断言 `eval` 等于 `t`
  （误差 < 1e-12）。这条路径只用了环面的几何定义，不经过被测的距离公式。

### Fixed

- `tools/oracle.py` 补圆台 / 胶囊的解析式与 `--cases`；docstring 里那句不存在
  的 `--check` 和早就改名的 `acceptance.ps1` 一并删掉。
- 文档里过期的量：代码行数（2748 → 3016）、圆台与减球的体积实测值、性能基线
  改成同一台机器的同一轮实测。

### 变更

- 测试从 41 块 / 216 用例变成 42 块 / 217 用例；公开 API 从 72 项变成 73 项。

## 0.1.3 — 2026-11-13

### Added

- **原语补全**：`Sdf::cone(r1, r2, half_height)` 圆台与 `Sdf::capsule(radius,
  half_height)` 胶囊，都是精确距离式（圆台 = 帽 + 侧棱投影，胶囊 = 轴向折返），
  各自实现 `bounds()`。两向都测了「退化还是解析形状」（cone r1=r2 退化为圆柱、
  capsule half_height=0 退化为球）与解析距离、梯度模长；体积对拍误差
  0.27 % / 0.13 %（`res = 48`）。
- **`grid_shape(bounds, resolution)`**：报告 `MAX_GRID_SLOTS` 收紧后**实际**会用的
  格点数。请求 256 的立方包围盒实际是 205³，以前这个差异只写在注释里。
  `mesh` 与它共用同一份 `plan_grid`，不会各算各的。
- **`cmd/main` 命令行**：`moon run cmd/main -- sphere 10 --res 32`，支持
  形状（sphere/box/cyl/cone/capsule/torus）、`--op diff|union|inter|smooth`、
  `--k`、`--at x,y,z`、`--res`、`--format stl|obj`、`--name`、`--stats`。
  输出走标准输出（当前工具链没有文件系统绑定），落盘靠重定向。
- **交互 demo**：`examples/web` 从「一个按钮 + 一段文本」改成调参面板 +
  canvas 2D 软件投影（画家算法 / 背面剔除 / lambert + 边缘光），实时显示
  三角数、顶点数、体积、面积、水密、χ、亏格与实际格点数；支持
  `?shape=&r1=&r2=&cut=&res=` 预设与拖拽 / 滚轮 / 双击复位。页面控制台打一行
  可判定结论 `mooncsg ok tris=… vol=… watertight=1`。
- **Pages 部署**：`.github/workflows/pages.yml`，构建 wasm → 跑 `wasm_check` +
  `scene_check` → 发布静态站点。
- **`tools/scene_check.mjs`**：在 Node 里覆盖 demo 的 7 个场景（球 / 盒 / 圆台 /
  退化圆台 / 胶囊 / 环面 / 挖球），建网格、读逐顶点坐标、验指标。
- **`tools/publish.mjs`**：发布后删本地缓存 zip，在临时模块里 `moon add` +
  `moon check` 做真实回拉，并校验解包内容与版本号——专门针对「列表在、下载 404」
  的平台故障。
- **`ACCEPTANCE.md`**：把 0.1.3 的实测数字（12 项门禁、6 组体积对拍、拓扑、
  性能、未覆盖项）记在一处。
- 测试 35 → 41（4 个圆台 / 胶囊断言 + 2 个 `grid_shape` 断言）。

### Changed

- 性能基线补上 128³ 与 256（实为 205³）两档，bench 输出增加 `grid=` 列，
  大分辨率那两档要 `-- big` 才跑。

## 0.1.2 — 2026-11-13

### Changed

- `Mesh::from_stl_binary` 的顶点去重从「每个顶点拼一个 `String` 键」改成
  `UInt64` 哈希分桶 + 桶内 `f32` 位模式精确比较：65 万面 / 32.7 万顶点的
  STL 回读从 671 ms 降到 128 ms（5.3×），顶点数与旧实现完全一致。哈希碰撞
  只会让桶变长，不会合并两个不同顶点。 (`96fe93c`)

### Fixed

- `Mesh::genus`：`χ > 2`（多个闭合壳叠在一起）时返回 `-1`，不再把
  `(2 - χ) / 2` 的负数当亏格返回；文档写明它只对单个闭合壳是亏格。 (`96fe93c`)

### Added

- 测试：两个不相交壳的网格（`euler = 4`、`genus = -1`）、两个壳的 STL
  往返（顶点数精确还原）。 (`96fe93c`)

## 0.1.1 — 2026-11-13

### Changed

- 网格化增加总格点上限 `MAX_GRID_SLOTS`（16.7M）：`resolution` 上限仍是 512，
  但 512 的立方包围盒会把步长自动放大到约 253³，避免场数组在 wasm-gc / js 上
  直接 OOM（原先 513³ 个格点 ≈ 1 GB）。 (`a32ea4a`)

### Fixed

- README：补 mooncakes 安装方式、补全 `examples/demo` 的 9 行输出、修正「插值偏置
  相对体素尺度」的表述（实际是边长比例）。 (`a32ea4a`)

## 0.1.0 — 2026-11-12

首个可用版本：SDF 原语 + 布尔 + marching tetrahedra + STL/OBJ 导出，
native / js / wasm-gc 三后端同一套测试。

### Added

- `vec.mbt`：`Vec3` / `Mat3` / `Aabb`，只做几何需要的那部分运算。
  (`bbafc94`)
- `sdf.mbt`：球、盒、半空间、圆柱、环面五个原语；平移 / 旋转 / 均匀缩放；
  并 / 交 / 差 / 平滑并；每个节点都能给出保守包围盒。 (`bbafc94`)
- `marching.mbt`：规则体素采样 + 立方体固定拆 6 四面体 + 边键焊接 +
  顶点沿梯度投影回等值面。 (`bbafc94`)
- `mesh.mbt`：散度定理求体积（兼作朝向自检）、面积、水密判定、
  欧拉示性数 / 亏格。 (`bbafc94`, `5a30681`)
- `export.mbt`：OBJ、ASCII STL、二进制 STL，以及二进制 STL 回读。
  (`bbafc94`, `1328137`)
- `examples/web`：wasm-gc 验收壳，页面 `?selftest=1` 自动跑四项检查；
  报告用「长度 + 逐码元」两个整数接口读出，绕开 wasm-gc 的字符串 ABI。
  (`cfa0aea`)
- `examples/bench`：四种用例的网格化耗时基线，用 core 的单调时钟。
  (`ee03938`)
- `tools/oracle.py`：Python 标准库手算的解析期望值，避免期望值从被测实现抄。
  (`bbafc94`)
- `tools/wasm_check.mjs`：在 Node 里实例化同一份 wasm 跑验收，不开浏览器。
  (`cfa0aea`)
- `tools/acceptance.mjs`：一条命令跑完全部验收项并打 PASS/SKIP 表。 (`ee03938`)
- `Mesh::hash()`：FNV-1a 64 位指纹，覆盖顶点位模式与索引序列。 (`0757e82`)

### Changed

- CI 从「只跑 wasm-gc」扩展成 native / js / wasm-gc 三后端各跑一遍测试；
  网格指纹的常量断言让后端间的浮点差异无处可藏。 (`0757e82`)
- CI 的 wasm 验收改成走 `tools/build_web.mjs`，由它处理「单模块仓库」与
  「workspace 成员」两种产物路径，再把 wasm 复制到固定位置。 (`120ee63`,
  `422335c`)

### Fixed

- 二进制 STL 回读不再依赖实验性的 `Bytes::unsafe_extract_uint_le`，
  改成手拼 4 字节；工具链升级不会把回读弄断。 (`1328137`)
- `tools/wasm_check.mjs` 与 `tools/build_web.mjs` 在单独 clone 的仓库里
  找不到 `web.wasm`（路径少了模块前缀）。原先 CI 的 wasm 验收步骤因此
  连续失败，现在改为「列候选 + 递归兜底」。 (`422335c`)

### Known limitations

- 薄特征的差集可能漏面：体素分辨率不够时，小于一个体素的壁会消失。
  计划以「薄特征下限 + 明确报错」收口，尚未实现。
- 没有 BVH / 距离查询加速：`Mesh` 上的查询是线性扫描，`Sdf::eval` 是逐
  节点递归。当前规模（十万面）够用，但不是通用加速结构。
- 本地 Windows 机器没有 MSVC Build Tools，native 后端只在 CI 的 ubuntu
  runner 上验证；README 的性能表因此只有 wasm-gc 与 js 两列。
