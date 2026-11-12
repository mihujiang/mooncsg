# CHANGELOG

按里程碑记录，每条都挂 commit。版本号按 mooncakes 的 0.x 规则走。

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
