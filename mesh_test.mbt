///|
fn rel_err(got : Double, want : Double) -> Double {
  (got - want).abs() / want
}

///|
fn sphere_bounds(r : Double) -> @mooncsg.Aabb {
  @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::splat(r),
  ).expand(0.5)
}

///|
test "sphere meshes watertight with small volume error" {
  let r = 25.0
  let s = @mooncsg.Sdf::sphere(r)
  let m = @mooncsg.mesh(s, sphere_bounds(r), @mooncsg.MeshOptions::new(128))
  assert_true(!m.is_empty())
  assert_true(m.is_watertight())
  assert_true(m.volume() > 0.0)
  let want = 4.0 / 3.0 * 3.141592653589793 * r * r * r
  assert_true(rel_err(m.volume(), want) < 0.005)
  assert_eq(m.genus(), 0)
  assert_eq(m.euler(), 2)
}

///|
test "box volume and topology" {
  let half = @mooncsg.Vec3::new(20.0, 15.0, 10.0)
  let s = @mooncsg.Sdf::box(half)
  let b = @mooncsg.Aabb::from_center_half(@mooncsg.Vec3::zero(), half).expand(
    0.5,
  )
  let m = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(40))
  assert_true(m.is_watertight())
  let want = 40.0 * 30.0 * 20.0
  assert_true(rel_err(m.volume(), want) < 0.01)
  assert_eq(m.genus(), 0)
  assert_eq(m.euler(), 2)
}

///|
test "torus has genus one" {
  let big = 30.0
  let small = 8.0
  let s = @mooncsg.Sdf::Torus(@mooncsg.Vec3::zero(), big, small)
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(big + small, big + small, small),
  ).expand(0.5)
  let m = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(48))
  assert_true(m.is_watertight())
  let want = 2.0 * 3.141592653589793 * 3.141592653589793 * big * small * small
  assert_true(rel_err(m.volume(), want) < 0.02)
  assert_eq(m.euler(), 0)
  assert_eq(m.genus(), 1)
}

///|
test "box minus sphere matches analytic volume" {
  let box = @mooncsg.Sdf::box(@mooncsg.Vec3::new(20.0, 15.0, 10.0))
  let ball = @mooncsg.Sdf::sphere(12.0)
  let s = box.subtract(ball)
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(20.0, 15.0, 10.0),
  ).expand(0.5)
  let m = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(48))
  assert_true(m.is_watertight())
  // 球带体积：2πa(r² - a²/3)，a = 10，r = 12
  let a = 10.0
  let removed = 2.0 * 3.141592653589793 * a * (12.0 * 12.0 - a * a / 3.0)
  let want = 40.0 * 30.0 * 20.0 - removed
  assert_true(rel_err(m.volume(), want) < 0.005)
}

///|
test "two through holes give genus two" {
  let box = @mooncsg.Sdf::box(@mooncsg.Vec3::new(20.0, 15.0, 10.0))
  let left = @mooncsg.Sdf::cylinder(5.0, 12.0).at(
    @mooncsg.Vec3::new(-8.0, 0.0, 0.0),
  )
  let right = @mooncsg.Sdf::cylinder(5.0, 12.0).at(
    @mooncsg.Vec3::new(8.0, 0.0, 0.0),
  )
  let s = box.subtract(left).subtract(right)
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(20.0, 15.0, 10.0),
  ).expand(0.5)
  let m = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(48))
  assert_true(m.is_watertight())
  // 两个圆柱各自贯穿 z 方向：挖掉 2 * π r² * 20
  let want = 24000.0 - 2.0 * 3.141592653589793 * 5.0 * 5.0 * 20.0
  assert_true(rel_err(m.volume(), want) < 0.005)
  assert_eq(m.euler(), -2)
  assert_eq(m.genus(), 2)
}

///|
test "fully subtracted solid produces empty mesh" {
  let small = @mooncsg.Sdf::sphere(5.0)
  let big = @mooncsg.Sdf::sphere(30.0)
  let m = @mooncsg.mesh(
    small.subtract(big),
    sphere_bounds(5.5),
    @mooncsg.MeshOptions::new(16),
  )
  assert_true(m.is_empty())
  assert_eq(m.triangle_count(), 0)
  assert_true(!m.is_watertight() || m.is_empty())
}

///|
test "meshing is deterministic for the same input" {
  let s = @mooncsg.Sdf::sphere(10.0).subtract(
    @mooncsg.Sdf::box(@mooncsg.Vec3::new(20.0, 20.0, 20.0)),
  )
  let b = sphere_bounds(10.0)
  let a = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(24))
  let c = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(24))
  assert_eq(a.vertex_count(), c.vertex_count())
  assert_eq(a.triangle_count(), c.triangle_count())
  assert_eq(a.volume(), c.volume())
  let mut i = 0
  while i < a.vertex_count() {
    assert_eq(a.positions[i].x, c.positions[i].x)
    assert_eq(a.positions[i].y, c.positions[i].y)
    assert_eq(a.positions[i].z, c.positions[i].z)
    i = i + 1
  }
}
