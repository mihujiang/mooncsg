///|
fn count_prefix(s : String, prefix : String) -> Int32 {
  let mut n = 0
  for line in s.split("\n") {
    if line.has_prefix(prefix) {
      n = n + 1
    }
  }
  n
}

///|
fn demo_mesh() -> @mooncsg.Mesh {
  let s = @mooncsg.Sdf::sphere(10.0).subtract(
    @mooncsg.Sdf::sphere(6.0).at(@mooncsg.Vec3::new(8.0, 0.0, 0.0)),
  )
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::splat(10.0),
  ).expand(0.5)
  @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(20))
}

///|
test "obj has one line per vertex and per triangle" {
  let m = demo_mesh()
  assert_true(!m.is_empty())
  let obj = m.to_obj("demo")
  assert_eq(count_prefix(obj, "v "), m.vertex_count())
  assert_eq(count_prefix(obj, "f "), m.triangle_count())
  assert_true(obj.has_prefix("# mooncsg demo\n"))
}

///|
test "stl repeats three vertices per facet" {
  let m = demo_mesh()
  let stl = m.to_stl("demo")
  assert_eq(count_prefix(stl, "  facet normal "), m.triangle_count())
  assert_eq(count_prefix(stl, "      vertex "), m.triangle_count() * 3)
  assert_true(stl.has_prefix("solid demo\n"))
  assert_true(stl.split("\n").count() > m.triangle_count() * 4)
}

///|
test "export is byte identical across runs" {
  let m = demo_mesh()
  let a = m.to_obj("x")
  let b = m.to_obj("x")
  assert_eq(a.length(), b.length())
  assert_true(a == b)
  let c = m.to_stl("x")
  let d = m.to_stl("x")
  assert_true(c == d)
}

///|
test "obj face indices stay in range" {
  let m = demo_mesh()
  let obj = m.to_obj("demo")
  let mut faces = 0
  for line in obj.split("\n") {
    if line.has_prefix("f ") {
      // "f i j k"：顶点索引个数固定为 3，且都是正数（无前导 '-'）
      let parts = line.split(" ").collect()
      assert_eq(parts.length(), 4)
      assert_true(!parts[1].has_prefix("-"))
      assert_true(!parts[2].has_prefix("-"))
      assert_true(!parts[3].has_prefix("-"))
      faces = faces + 1
    }
  }
  assert_eq(faces, m.triangle_count())
}

///|
test "binary stl round trip preserves counts and volume" {
  let m = @mooncsg.mesh(
    @mooncsg.Sdf::sphere(10.0),
    @mooncsg.Aabb::from_center_half(
      @mooncsg.Vec3::zero(),
      @mooncsg.Vec3::splat(10.0),
    ).expand(0.5),
    @mooncsg.MeshOptions::new(48),
  )
  let bytes = m.to_stl_binary()
  assert_eq(bytes.length(), 84 + m.triangle_count() * 50)
  match @mooncsg.Mesh::from_stl_binary(bytes) {
    Some(back) => {
      assert_eq(back.triangle_count(), m.triangle_count())
      assert_eq(back.vertex_count(), m.vertex_count())
      assert_true(back.is_watertight())
      assert_eq(back.euler(), m.euler())
      // f32 存储：体积误差应在相对 1e-6 内
      assert_true((back.volume() - m.volume()).abs() / m.volume() < 1.0e-6)
    }
    None => assert_true(false)
  }
}

///|
test "binary stl round trip keeps a concave solid closed" {
  let box = @mooncsg.Sdf::box(@mooncsg.Vec3::new(10.0, 10.0, 10.0))
  let s = box.subtract(@mooncsg.Sdf::cylinder(5.0, 12.0))
  let m = @mooncsg.mesh(
    s,
    @mooncsg.Aabb::from_center_half(
      @mooncsg.Vec3::zero(),
      @mooncsg.Vec3::splat(10.0),
    ).expand(0.5),
    @mooncsg.MeshOptions::new(32),
  )
  match @mooncsg.Mesh::from_stl_binary(m.to_stl_binary()) {
    Some(back) => {
      assert_true(back.is_watertight())
      assert_eq(back.triangle_count(), m.triangle_count())
      assert_true((back.volume() - m.volume()).abs() / m.volume() < 1.0e-6)
    }
    None => assert_true(false)
  }
}

///|
test "truncated binary stl is rejected" {
  let short = Bytes::new(10)
  match @mooncsg.Mesh::from_stl_binary(short) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "empty mesh round trips through binary stl" {
  let bytes = @mooncsg.Mesh::empty().to_stl_binary()
  assert_eq(bytes.length(), 84)
  match @mooncsg.Mesh::from_stl_binary(bytes) {
    Some(back) => assert_true(back.is_empty())
    None => assert_true(false)
  }
}
