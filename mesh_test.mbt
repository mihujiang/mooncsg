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
test "tangent spheres stay finite" {
  // 两个球在一点相切：接触点处网格是共享顶点，拓扑上非流形，
  // 但体积必须仍然对得上，且不能出现 NaN 或 panic。
  let s = @mooncsg.Sdf::sphere(10.0).union(
    @mooncsg.Sdf::sphere(10.0).at(@mooncsg.Vec3::new(20.0, 0.0, 0.0)),
  )
  let b = @mooncsg.Aabb::new(
    @mooncsg.Vec3::new(-11.0, -11.0, -11.0),
    @mooncsg.Vec3::new(31.0, 11.0, 11.0),
  )
  let m = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(40))
  assert_true(!m.is_empty())
  let want = 2.0 * 4.0 / 3.0 * 3.141592653589793 * 1000.0
  assert_true(rel_err(m.volume(), want) < 0.01)
}

///|
test "zero thickness slab produces no runaway volume" {
  // 厚度 0.01 的板，体素 1.0：要么完全没有符号变化（空网格），
  // 要么只有一层薄壳。无论哪种，都不能出现「把整个包围盒当成实体」。
  let thin = @mooncsg.Sdf::plane(@mooncsg.Vec3::new(0.0, 0.0, 1.0), 0.005).intersect(
    @mooncsg.Sdf::plane(@mooncsg.Vec3::new(0.0, 0.0, -1.0), 0.005),
  )
  let b = @mooncsg.Aabb::new(
    @mooncsg.Vec3::splat(-10.0),
    @mooncsg.Vec3::splat(10.0),
  )
  let m = @mooncsg.mesh(thin, b, @mooncsg.MeshOptions::new(20))
  assert_true(m.volume() < 1000.0)
}

///|
test "empty intersection produces empty mesh" {
  let a = @mooncsg.Sdf::sphere(5.0)
  let c = @mooncsg.Sdf::sphere(5.0).at(@mooncsg.Vec3::new(20.0, 0.0, 0.0))
  let b = @mooncsg.Aabb::new(
    @mooncsg.Vec3::splat(-6.0),
    @mooncsg.Vec3::splat(6.0),
  )
  let m = @mooncsg.mesh(a.intersect(c), b, @mooncsg.MeshOptions::new(12))
  assert_true(m.is_empty())
  assert_eq(m.volume(), 0.0)
}

///|
test "surface exactly on grid points stays watertight" {
  // 盒半长 10，包围盒正好 [-10, 10]，resolution 20 时格距 1：
  // 六个面全部落在格点上（f == 0，按约定归外部）。
  let s = @mooncsg.Sdf::box(@mooncsg.Vec3::splat(10.0))
  let b = @mooncsg.Aabb::new(
    @mooncsg.Vec3::splat(-10.0),
    @mooncsg.Vec3::splat(10.0),
  )
  let m = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(20))
  assert_true(m.is_watertight())
  assert_true(rel_err(m.volume(), 8000.0) < 0.01)
  assert_eq(m.euler(), 2)
}

///|
test "degenerate bounds yield an empty mesh" {
  let p = @mooncsg.Vec3::new(1.0, 2.0, 3.0)
  let m = @mooncsg.mesh(
    @mooncsg.Sdf::sphere(10.0),
    @mooncsg.Aabb::new(p, p),
    @mooncsg.MeshOptions::new(8),
  )
  assert_true(m.is_empty())
}

///|
test "resolution below two is clamped" {
  let m = @mooncsg.mesh(
    @mooncsg.Sdf::sphere(10.0),
    sphere_bounds(10.0),
    @mooncsg.MeshOptions::new(1),
  )
  assert_true(!m.is_empty())
  assert_true(m.volume() > 0.0)
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

///|
test "mesh hash is stable across backends" {
  let m = @mooncsg.mesh(
    @mooncsg.Sdf::sphere(10.0),
    @mooncsg.Aabb::from_center_half(
      @mooncsg.Vec3::zero(),
      @mooncsg.Vec3::splat(10.0),
    ).expand(0.5),
    @mooncsg.MeshOptions::new(32),
  )
  // 该常量在 native / js / wasm-gc 三个后端都必须一致；任一后端出现
  // 不同的浮点结果或不同的遍历顺序，这个断言就会炸。
  assert_eq(m.hash(), 7885752854646016839UL)
}

///|
test "mesh hash distinguishes different inputs" {
  let s = @mooncsg.Sdf::sphere(10.0)
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::splat(10.0),
  ).expand(0.5)
  let fine = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(32))
  let coarse = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(16))
  assert_true(fine.hash() != coarse.hash())
  // 翻转朝向只改索引顺序，指纹必须随之变化，否则指纹覆盖不住拓扑。
  assert_true(fine.hash() != fine.flipped().hash())
}
