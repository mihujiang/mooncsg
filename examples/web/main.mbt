///|
/// 浏览器验收壳的入口。
///
/// 这些函数会被 `moon build --target wasm-gc` 导出成 wasm 函数，
/// 由 `examples/web/index.html` 里的按钮调用。它们只做两件事：
/// 跑一遍「网格化 + 导出 + 回读」，然后给出可读的结论。
let selftest_report : Ref[String] = { val: "" }

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
pub fn selftest() -> Int {
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
pub fn report_len() -> Int {
  selftest_report.val.length()
}

///|
/// 报告文本的第 `i` 个 UTF-16 码元。
pub fn report_code_unit(i : Int) -> Int {
  match selftest_report.val.get_char(i) {
    Some(c) => c.to_int()
    None => 0
  }
}
