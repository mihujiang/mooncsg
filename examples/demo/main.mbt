///|
/// 盒减球：一个不需要外部资源、又能同时验证「凹面 + 水密 + 体积」的小模型。
fn main {
  let half = @mooncsg.Vec3::new(20.0, 15.0, 10.0)
  let sdf = @mooncsg.Sdf::box(half).subtract(@mooncsg.Sdf::sphere(12.0))
  let bounds = @mooncsg.Aabb::from_center_half(@mooncsg.Vec3::zero(), half).expand(
    0.5,
  )
  let m = @mooncsg.mesh(sdf, bounds, @mooncsg.MeshOptions::new(64))
  println("triangles:  \{m.triangle_count()}")
  println("vertices:   \{m.vertex_count()}")
  println("volume:     \{m.volume()}")
  println("area:       \{m.area()}")
  println("watertight: \{m.is_watertight()}")
  println("euler:      \{m.euler()} (genus \{m.genus()})")
  let obj = m.to_obj("box_minus_sphere")
  let stl = m.to_stl("box_minus_sphere")
  println("obj bytes:  \{obj.length()}")
  println("stl bytes:  \{stl.length()}")
  println("")
  println("预期体积（解析）：24000 - 2*pi*10*(144 - 100/3) = 17046.6")
}
