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
  assert_true(m.is_manifold())
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
  assert_true(m.is_manifold())
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
  assert_true(m.is_manifold())
  let want = 2.0 * 3.141592653589793 * 3.141592653589793 * big * small * small
  assert_true(rel_err(m.volume(), want) < 0.02)
  assert_eq(m.euler(), 0)
  assert_eq(m.genus(), 1)
}

///|
test "cone frustum volume matches analytic" {
  let r1 = 5.0
  let r2 = 10.0
  let h = 10.0
  let s = @mooncsg.Sdf::cone(r1, r2, h)
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(r2, r2, h),
  ).expand(0.5)
  let m = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(64))
  assert_true(m.is_watertight())
  // 体积公式里的 h 是总高，构造器收的是半高
  let want = 3.141592653589793 * (2.0 * h) * (r1 * r1 + r1 * r2 + r2 * r2) / 3.0
  assert_true(rel_err(m.volume(), want) < 0.01)
  assert_eq(m.genus(), 0)
  assert_eq(m.euler(), 2)
}

///|
test "capsule volume matches analytic" {
  let r = 5.0
  let h = 5.0
  let s = @mooncsg.Sdf::capsule(r, h)
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(r, r, h + r),
  ).expand(0.5)
  let m = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(64))
  assert_true(m.is_watertight())
  let pi = 3.141592653589793
  let want = pi * r * r * 2.0 * h + 4.0 / 3.0 * pi * r * r * r
  assert_true(rel_err(m.volume(), want) < 0.01)
  assert_eq(m.genus(), 0)
  assert_eq(m.euler(), 2)
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
  assert_true(m.is_manifold())
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
  assert_eq(m.hash(), 1567319603017277365UL)
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

///|
test "two disjoint shells make genus undecidable" {
  let left = @mooncsg.Sdf::sphere(5.0).at(@mooncsg.Vec3::new(-12.0, 0.0, 0.0))
  let right = @mooncsg.Sdf::sphere(5.0).at(@mooncsg.Vec3::new(12.0, 0.0, 0.0))
  let s = left.union(right)
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(17.0, 5.0, 5.0),
  ).expand(0.5)
  let m = @mooncsg.mesh(s, b, @mooncsg.MeshOptions::new(64))
  assert_true(m.is_watertight())
  assert_true(m.is_manifold())
  // 两个闭合壳：χ = 2 + 2 = 4，(2 - χ) / 2 = -1 不是亏格，所以给 -1。
  assert_eq(m.euler(), 4)
  assert_eq(m.genus(), -1)
  assert_eq(m.shell_count(), 2)
  let parts = m.shells()
  assert_eq(parts.length(), 2)
  let want = 4.0 / 3.0 * 3.141592653589793 * 125.0
  for p in parts {
    assert_true(p.is_watertight())
    assert_eq(p.genus(), 0)
    assert_true(rel_err(p.volume(), want) < 0.01)
  }
  // 两个等大的壳：最大的那个也是合法单壳网格
  assert_true(m.largest_shell().is_watertight())
}

///|
test "two disjoint tori are two shells each of genus one" {
  // χ 分不出多壳：两个环面各 χ = 0，合起来还是 0，只看 χ 会算成「单壳亏格 1」。
  let left = @mooncsg.Sdf::torus(8.0, 3.0).at(
    @mooncsg.Vec3::new(-15.0, 0.0, 0.0),
  )
  let right = @mooncsg.Sdf::torus(8.0, 3.0).at(
    @mooncsg.Vec3::new(15.0, 0.0, 0.0),
  )
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(26.0, 11.0, 3.0),
  ).expand(0.5)
  let m = @mooncsg.mesh(left.union(right), b, @mooncsg.MeshOptions::new(64))
  assert_eq(m.euler(), 0)
  assert_eq(m.shell_count(), 2)
  assert_eq(m.genus(), -1)
  let parts = m.shells()
  assert_eq(parts.length(), 2)
  let want = 2.0 * 3.141592653589793 * 3.141592653589793 * 8.0 * 9.0
  for p in parts {
    assert_eq(p.genus(), 1)
    assert_true(rel_err(p.volume(), want) < 0.02)
  }
}

///|
test "largest shell drops floating debris" {
  let ball = @mooncsg.Sdf::sphere(10.0)
  let debris = @mooncsg.Sdf::sphere(2.0).at(@mooncsg.Vec3::new(30.0, 0.0, 0.0))
  let b = @mooncsg.Aabb::new(
    @mooncsg.Vec3::splat(-11.0),
    @mooncsg.Vec3::new(33.0, 11.0, 11.0),
  )
  let m = @mooncsg.mesh(ball.union(debris), b, @mooncsg.MeshOptions::new(48))
  assert_eq(m.shell_count(), 2)
  let big = m.largest_shell()
  assert_eq(big.shell_count(), 1)
  let want = 4.0 / 3.0 * 3.141592653589793 * 1000.0
  assert_true(rel_err(big.volume(), want) < 0.01)
}

///|
test "audit reports topology and no warnings for a clean solid" {
  let m = @mooncsg.mesh(
    @mooncsg.Sdf::sphere(10.0),
    sphere_bounds(10.0),
    @mooncsg.MeshOptions::new(32),
  )
  let a = m.audit()
  assert_eq(a.shells, 1)
  assert_eq(a.euler, 2)
  assert_eq(a.genus, 0)
  assert_eq(a.open_edges, 0)
  assert_true(a.watertight)
  assert_true(a.manifold)
  assert_eq(a.warnings.length(), 0)
  assert_true(a.volume > 0.0)
  assert_true(a.area > 0.0)
  let j = a.to_json()
  assert_true(j.contains("\"shells\": 1"))
  assert_true(j.contains("\"genus\": 0"))
  assert_true(j.contains("\"watertight\": true"))
  assert_true(j.contains("\"warnings\": []"))
}

///|
test "audit warns about multiple shells and open edges" {
  // 多壳：体积很大的球 + 远处小球
  let ball = @mooncsg.Sdf::sphere(10.0)
  let debris = @mooncsg.Sdf::sphere(2.0).at(@mooncsg.Vec3::new(30.0, 0.0, 0.0))
  let b = @mooncsg.Aabb::new(
    @mooncsg.Vec3::splat(-11.0),
    @mooncsg.Vec3::new(33.0, 11.0, 11.0),
  )
  let m = @mooncsg.mesh(ball.union(debris), b, @mooncsg.MeshOptions::new(48))
  let a = m.audit()
  assert_eq(a.shells, 2)
  assert_eq(a.genus, -1)
  assert_true(a.warnings.length() >= 1)
  assert_true(a.to_json().contains("\"shells\": 2"))
  // 开口：故意把球切一半
  let clipped = @mooncsg.mesh_unchecked(
    @mooncsg.Sdf::sphere(10.0),
    @mooncsg.Aabb::new(
      @mooncsg.Vec3::new(-10.5, -10.5, -10.5),
      @mooncsg.Vec3::new(0.0, 10.5, 10.5),
    ),
    @mooncsg.MeshOptions::new(32),
  )
  let ca = clipped.audit()
  assert_true(!ca.watertight)
  assert_true(ca.open_edges > 0)
  assert_true(ca.warnings.length() >= 1)
}

///|
/// 手搓网格：两个四面体只共用 0 号顶点（焊接后是同一个点）。
fn two_tetrahedra_at_a_point() -> @mooncsg.Mesh {
  let positions : Array[@mooncsg.Vec3] = [
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(1.0, 1.0, 1.0),
    @mooncsg.Vec3::new(1.0, -1.0, -1.0),
    @mooncsg.Vec3::new(-1.0, 1.0, -1.0),
    @mooncsg.Vec3::new(3.0, 0.0, 0.0),
    @mooncsg.Vec3::new(4.0, 1.0, 1.0),
    @mooncsg.Vec3::new(4.0, -1.0, -1.0),
    @mooncsg.Vec3::new(2.0, 1.0, -1.0),
  ]
  let indices : Array[Int32] = [
    0, 1, 2, 0, 2, 3, 0, 3, 1, 1, 3, 2, 0, 5, 6, 0, 6, 7, 0, 7, 5, 5, 7, 6,
  ]
  @mooncsg.Mesh::new(positions, indices)
}

///|
test "single tetrahedron is a closed manifold" {
  let positions : Array[@mooncsg.Vec3] = [
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(1.0, 1.0, 1.0),
    @mooncsg.Vec3::new(1.0, -1.0, -1.0),
    @mooncsg.Vec3::new(-1.0, 1.0, -1.0),
  ]
  let indices : Array[Int32] = [0, 1, 2, 0, 2, 3, 0, 3, 1, 1, 3, 2]
  let m = @mooncsg.Mesh::new(positions, indices)
  assert_eq(m.triangle_count(), 4)
  assert_true(m.is_watertight())
  assert_true(m.is_manifold())
  assert_eq(m.euler(), 2)
  assert_eq(m.genus(), 0)
}

///|
test "two tetrahedra glued at one vertex are watertight but not manifold" {
  // 关键：每个顶点的 faces 与 deg 仍然相等（两瓣各自是一个环），
  // 只比度数会漏掉，必须看星形是不是「一个」环。
  let m = two_tetrahedra_at_a_point()
  assert_true(m.is_watertight())
  assert_true(!m.is_manifold())
}

///|
test "three faces on one edge are not manifold" {
  // 四面体 + 挂在新顶点上的一个面，与底边 (0,1) 共享边：该边 3 个面。
  let positions : Array[@mooncsg.Vec3] = [
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(1.0, 1.0, 1.0),
    @mooncsg.Vec3::new(1.0, -1.0, -1.0),
    @mooncsg.Vec3::new(-1.0, 1.0, -1.0),
    @mooncsg.Vec3::new(0.0, 0.0, 2.0),
  ]
  let indices : Array[Int32] = [0, 1, 2, 0, 2, 3, 0, 3, 1, 1, 3, 2, 0, 1, 4]
  let m = @mooncsg.Mesh::new(positions, indices)
  assert_true(!m.is_watertight())
  assert_true(!m.is_manifold())
}

///|
test "open surface is not manifold" {
  // 四面体去掉一个面：出现边界，不能再算闭合流形。
  let positions : Array[@mooncsg.Vec3] = [
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::new(1.0, 1.0, 1.0),
    @mooncsg.Vec3::new(1.0, -1.0, -1.0),
    @mooncsg.Vec3::new(-1.0, 1.0, -1.0),
  ]
  let indices : Array[Int32] = [0, 1, 2, 0, 2, 3, 0, 3, 1]
  let m = @mooncsg.Mesh::new(positions, indices)
  assert_true(!m.is_watertight())
  assert_true(!m.is_manifold())
}

///|
/// 已知限制的可执行记录：壁厚小于 1 个体素时，格点采样漏掉壁内负区，内腔
/// 表面被当成实体边界——体积**偏大**（不是偏小），而网格仍然水密、仍然流形。
/// 哪天改成自适应细分或加薄壁检测，这条会红，提醒同步文档与 audit 告警。
test "thin wall inflates volume while staying watertight" {
  let outer = @mooncsg.Sdf::box(@mooncsg.Vec3::splat(10.0))
  let inner = @mooncsg.Sdf::box(@mooncsg.Vec3::splat(9.8))
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::splat(10.0),
  ).expand(0.5)
  let side = 2.0 * 9.8
  let want = 8000.0 - side * side * side
  let m = @mooncsg.mesh(outer.subtract(inner), b, @mooncsg.MeshOptions::new(32))
  assert_true(m.is_watertight())
  assert_true(m.is_manifold())
  assert_eq(m.shell_count(), 2)
  assert_true(m.volume() > 10.0 * want)
  assert_true(m.audit().warnings.length() >= 1)
  // 同一形状把体素压到壁厚以下（res 128 时 h ≈ 0.16）就回到正轨。
  let fine = @mooncsg.mesh(
    outer.subtract(inner),
    b,
    @mooncsg.MeshOptions::new(128),
  )
  assert_true(rel_err(fine.volume(), want) < 0.05)
}

///|
test "empty mesh and mesh without triangles are manifold" {
  assert_true(@mooncsg.Mesh::empty().is_manifold())
  // 只有顶点、没有面：没有拓扑可违反，孤立顶点不算缺陷。
  let positions : Array[@mooncsg.Vec3] = [@mooncsg.Vec3::zero()]
  let m = @mooncsg.Mesh::new(positions, [])
  assert_true(m.is_manifold())
}

///|
test "shell helpers and audit handle empty, split and non-finite meshes" {
  // 空网格：没有壳，`largest_shell` 返回空网格而不是越界。
  let empty = @mooncsg.Mesh::empty()
  assert_eq(empty.shell_count(), 0)
  assert_eq(empty.shells().length(), 0)
  assert_true(empty.largest_shell().is_empty())
  // 两个三角形只共用一个顶点：按「共享一条边」判是两个壳，各自重编顶点后
  // 只留下自己用到的 3 个顶点（原网格 5 个）。
  let positions : Array[@mooncsg.Vec3] = [
    @mooncsg.Vec3::new(0.0, 0.0, 0.0),
    @mooncsg.Vec3::new(1.0, 0.0, 0.0),
    @mooncsg.Vec3::new(0.0, 1.0, 0.0),
    @mooncsg.Vec3::new(0.0, -1.0, 0.0),
    @mooncsg.Vec3::new(-1.0, 0.0, 0.0),
  ]
  let split = @mooncsg.Mesh::new(positions, [0, 1, 2, 0, 3, 4])
  assert_eq(split.shell_count(), 2)
  let parts = split.shells()
  assert_eq(parts.length(), 2)
  for part in parts {
    assert_eq(part.triangle_count(), 1)
    assert_eq(part.vertex_count(), 3)
  }
  // 非有限值必须写成 JSON 的 null，否则 `--audit` 产出的是非法 JSON。
  // 1e308 的坐标让叉积溢出成 Inf，正好走到 `json_num` 的另一条分支。
  let huge = @mooncsg.Mesh::new(
    [
      @mooncsg.Vec3::splat(1.0e308),
      @mooncsg.Vec3::splat(-1.0e308),
      @mooncsg.Vec3::splat(1.0e308),
    ],
    [0, 1, 2],
  )
  assert_true(huge.audit().to_json().contains("\"volume\": null"))
}
