///|
/// 交互 demo 的场景缓存：`build` 建一次，剩下的读取接口都从它取数。
/// wasm-gc 里 `Mesh` 是 GC 对象，JS 读不到字段，所以坐标与索引都拆成
/// 逐个 `Double` / `Int32` 的接口——几万个顶点量级下调用开销可以接受。
let scene : Ref[@mooncsg.Mesh] = { val: @mooncsg.Mesh::empty(), }

///|
/// 上一次构建实际用到的格点数，见 `grid_dim`。
let grid : Ref[(Int32, Int32, Int32)] = { val: (0, 0, 0), }

///|
/// 按形状号生成网格并缓存：
///
/// - `0` 球：`r1` 半径
/// - `1` 立方体：`r1` 边长
/// - `2` 圆台：`r1` 底半径、`r2` 高（顶面收到 0）
/// - `3` 胶囊：`r1` 半径、`r2` 圆柱段长
/// - `4` 环面：`r1` 管半径、`r2` 环半径
///
/// `cut > 0` 时再从 `+x` 方向减去一个球（偏心，缺口看得见）。返回三角数。
///
/// 参数来自网页上的滑杆，可以被拖到 0 或负数；退化的 SDF 会让包围盒
/// 某个方向退化成零长，网格化时会除零 panic（wasm 里表现为 `unreachable`）。
/// 所以入口处先夹到安全区间——这是给人点着玩的 demo，不是严格 API。
pub fn build(
  shape : Int32,
  r1 : Double,
  r2 : Double,
  cut : Double,
  res : Int32,
) -> Int32 {
  let a = if r1 < 0.5 { 0.5 } else { r1 }
  let b = if r2 < 0.5 { 0.5 } else { r2 }
  let c = if cut < 0.0 { 0.0 } else { cut }
  let n = if res < 8 { 8 } else if res > 96 { 96 } else { res }
  let base = match shape {
    1 => @mooncsg.Sdf::box(@mooncsg.Vec3::splat(a * 0.5))
    2 => @mooncsg.Sdf::cone(0.0, a, b * 0.5)
    3 => @mooncsg.Sdf::capsule(a, b * 0.5)
    // 管半径必须小于环半径，否则自交：夹到 1.05 倍，留一点余量。
    4 =>
      @mooncsg.Sdf::Torus(
        @mooncsg.Vec3::zero(),
        if b > a * 1.05 {
          b
        } else {
          a * 1.05
        },
        a,
      )
    _ => @mooncsg.Sdf::sphere(a)
  }
  // 挖球偏心放：同心挖只会得到一层外壳，外表面一模一样，画面上看不出变化。
  // 偏到 x 正方向能直接咬掉一块，减法的效果肉眼可见。
  let sdf = if c > 0.0 {
    base.subtract(
      @mooncsg.Sdf::sphere(c).at(@mooncsg.Vec3::new(a * 0.8, 0.0, 0.0)),
    )
  } else {
    base
  }
  let bounds = match sdf.bounds() {
    Some(b) => b.expand(0.5)
    None =>
      @mooncsg.Aabb::from_center_half(
        @mooncsg.Vec3::zero(),
        @mooncsg.Vec3::splat(10.0),
      ).expand(0.5)
  }
  let (gx, gy, gz) = @mooncsg.grid_shape(bounds, n)
  grid.val = (gx, gy, gz)
  let m = @mooncsg.mesh(sdf, bounds, @mooncsg.MeshOptions::new(n))
  scene.val = m
  m.triangle_count()
}

///|
/// 上一次 `build` 实际用到的格点数：`0/1/2` → x/y/z。
///
/// 页面上要显示「真实的采样密度」而不是滑杆的回显值，否则请求 64 而被
/// `MAX_GRID_SLOTS` 收窄时，人会以为自己在看 64³ 的结果。
pub fn grid_dim(k : Int32) -> Int32 {
  let (gx, gy, gz) = grid.val
  match k {
    1 => gy
    2 => gz
    _ => gx
  }
}

///|
pub fn triangle_count() -> Int32 {
  scene.val.triangle_count()
}

///|
pub fn vertex_count() -> Int32 {
  scene.val.vertex_count()
}

///|
/// 第 `i` 个索引（长度 `3 * 三角数`）。
pub fn tri_index(i : Int32) -> Int32 {
  scene.val.indices[i]
}

///|
/// 第 `i` 个坐标分量（长度 `3 * 顶点数`，按 x,y,z 交错）。
pub fn pos(i : Int32) -> Double {
  let p = scene.val.positions[i / 3]
  match i % 3 {
    1 => p.y
    2 => p.z
    _ => p.x
  }
}

///|
/// `0` 体积、`1` 面积。
pub fn metric(k : Int32) -> Double {
  if k == 1 {
    scene.val.area()
  } else {
    scene.val.volume()
  }
}

///|
/// `0` 水密（1/0）、`1` 欧拉示性数、`2` 亏格。
pub fn flag(k : Int32) -> Int32 {
  if k == 0 {
    if scene.val.is_watertight() {
      1
    } else {
      0
    }
  } else if k == 1 {
    scene.val.euler()
  } else {
    scene.val.genus()
  }
}

///|
/// 浏览器验收壳的入口。
///
/// 这些函数会被 `moon build --target wasm-gc` 导出成 wasm 函数，
/// 由 `examples/web/index.html` 里的按钮调用。它们只做两件事：
/// 跑一遍「网格化 + 导出 + 回读」，然后给出可读的结论。
let selftest_report : Ref[String] = { val: "", }

///|
fn check(name : String, ok : Bool) -> String {
  if ok {
    "\u{2713} " + name
  } else {
    "\u{2717} " + name
  }
}

///|
/// 跑一遍验收检查，返回通过项数（用于 JS 侧判断是否全绿）。
pub fn selftest() -> Int32 {
  let lines : Array[String] = []
  let mut passed = 0
  let sphere = @mooncsg.Sdf::sphere(10.0)
  let bounds = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::splat(10.0),
  ).expand(0.5)
  let m = @mooncsg.mesh(sphere, bounds, @mooncsg.MeshOptions::new(48))
  let want = 4.0 / 3.0 * 3.141592653589793 * 1000.0
  let rel = (m.volume() - want).abs() / want
  lines.push(check("球体积误差 < 0.5%", rel < 0.005))
  if rel < 0.005 {
    passed = passed + 1
  }
  lines.push(check("水密", m.is_watertight()))
  if m.is_watertight() {
    passed = passed + 1
  }
  lines.push(check("欧拉示性数 = 2", m.euler() == 2))
  if m.euler() == 2 {
    passed = passed + 1
  }
  let round = @mooncsg.Mesh::from_stl_binary(m.to_stl_binary())
  let ok = match round {
    Some(back) =>
      back.triangle_count() == m.triangle_count() &&
      back.vertex_count() == m.vertex_count() &&
      (back.volume() - m.volume()).abs() / m.volume() < 1.0e-6
    None => false
  }
  lines.push(check("二进制 STL 往返", ok))
  if ok {
    passed = passed + 1
  }
  lines.push("三角数 \{m.triangle_count()}，体积 \{m.volume()}")
  selftest_report.val = lines.join("\n")
  passed
}

///|
/// 报告文本长度（UTF-16 码元数）。
///
/// 不直接导出 `report() -> String`：wasm-gc 里 `String` 是 GC 对象，
/// JS 侧拿到的是不透明引用，读不出字符。拆成「长度 + 逐码元」两个
/// 纯整数接口之后，宿主只需要一个 for 循环。
pub fn report_len() -> Int32 {
  selftest_report.val.length()
}

///|
/// 报告文本的第 `i` 个 UTF-16 码元。
pub fn report_code_unit(i : Int32) -> Int32 {
  match selftest_report.val.get_char(i) {
    Some(c) => c.to_int()
    None => 0
  }
}
