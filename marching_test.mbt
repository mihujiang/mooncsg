///|
/// `grid_shape` 报的是**实际**格点数：`MAX_GRID_SLOTS`（16.7M）收紧之后
/// 的值，而不是回显请求的 `resolution`。bench 与 demo 的分辨率显示都靠它。
test "grid_shape clamps to MAX_GRID_SLOTS" {
  let b = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::splat(25.0),
  ).expand(0.5)
  // 小分辨率不被收紧：三条轴都是 2。
  let (x2, y2, z2) = @mooncsg.grid_shape(b, 2)
  assert_eq(x2, 2)
  assert_eq(y2, 2)
  assert_eq(z2, 2)
  // 128 立方：129³ ≈ 2.1M 个采样点，远低于上限，三轴都是 128。
  let (x128, _, _) = @mooncsg.grid_shape(b, 128)
  assert_eq(x128, 128)
  // 512 立方原本是 513³ ≈ 1.35 亿，必须被收到上限以内。
  let (x, y, z) = @mooncsg.grid_shape(b, 512)
  assert_true(x > 0 && x < 512)
  let slots = (x + 1).to_uint64() * (y + 1).to_uint64() * (z + 1).to_uint64()
  assert_true(slots <= 16777216UL)
}

///|
/// 退化成一点的包围盒没有格点可采，返回 `(0, 0, 0)` 而不是崩或除零。
test "grid_shape on degenerate bounds" {
  let point = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::zero(),
  )
  let (x, y, z) = @mooncsg.grid_shape(point, 32)
  assert_eq(x, 0)
  assert_eq(y, 0)
  assert_eq(z, 0)
}

///|
/// 通过检查时给出的保证就是「可打印」的定义：闭合、无开口边、体积为正。
test "mesh_checked guarantees a closed mesh" {
  let sphere = @mooncsg.Sdf::sphere(10.0)
  let bounds = match sphere.bounds() {
    Some(b) => b.expand(0.5)
    None => {
      fail("球必须有包围盒")
      @mooncsg.Aabb::new(@mooncsg.Vec3::zero(), @mooncsg.Vec3::zero())
    }
  }
  match @mooncsg.mesh_checked(sphere, bounds, @mooncsg.MeshOptions::new(32)) {
    Ok(m) => {
      assert_true(m.is_watertight())
      assert_eq(m.open_edges(), 0)
      assert_true(m.volume() > 0.0)
    }
    Err(e) => fail(e.describe())
  }
}

///|
/// 相切：球盒不加 expand，曲面正好落在采样域的 6 个面上（边界采样 f == 0）。
/// 这种输入必须被拒——它产生的正是一个被切成半球、边缘全开的网格。
test "mesh_checked rejects a surface touching the sampling box" {
  let sphere = @mooncsg.Sdf::sphere(10.0)
  let bounds = match sphere.bounds() {
    Some(b) => b
    None => {
      fail("球必须有包围盒")
      @mooncsg.Aabb::new(@mooncsg.Vec3::zero(), @mooncsg.Vec3::zero())
    }
  }
  match @mooncsg.mesh_checked(sphere, bounds, @mooncsg.MeshOptions::new(16)) {
    Ok(_) => fail("与采样域相切的实体必须被拒绝")
    Err(@mooncsg.MeshError::SurfaceClipped(_, _)) => ()
    Err(e) => fail(e.describe())
  }
}

///|
/// 裁剪：采样域只盖住球的一半多一点。`mesh_unchecked` 会给出开口网格
/// （这就是「不可直接切片」的具体样子），`mesh_checked` 则拒绝。
test "clipped domain is open when unchecked, rejected when checked" {
  let sphere = @mooncsg.Sdf::sphere(10.0)
  let half = @mooncsg.Aabb::new(
    @mooncsg.Vec3::new(-10.5, -10.5, -10.5),
    @mooncsg.Vec3::new(2.0, 10.5, 10.5),
  )
  let opts = @mooncsg.MeshOptions::new(24)
  let open = @mooncsg.mesh_unchecked(sphere, half, opts)
  assert_true(open.triangle_count() > 0)
  assert_true(!open.is_watertight())
  assert_true(open.open_edges() > 0)
  match @mooncsg.mesh_checked(sphere, half, opts) {
    Ok(_) => fail("裁剪过的采样域必须被拒绝")
    Err(@mooncsg.MeshError::SurfaceClipped(_, _)) => ()
    Err(e) => fail(e.describe())
  }
}

///|
/// 半空间：没有有限包围盒，所以 CLI 层面的处置是「直接拒绝、要求给域」。
/// 一旦硬给一个有界域，采样域边界上必然出现 f <= 0，仍然被拒。
test "half space has no bounds and cannot be meshed" {
  let plane = @mooncsg.Sdf::plane(@mooncsg.Vec3::new(0.0, 0.0, 1.0), 0.0)
  match plane.bounds() {
    None => ()
    Some(_) => fail("半空间不该有有限包围盒")
  }
  let cube = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::splat(10.0),
  )
  match @mooncsg.mesh_checked(plane, cube, @mooncsg.MeshOptions::new(16)) {
    Ok(_) => fail("半空间在有界域内必须被拒绝")
    Err(@mooncsg.MeshError::SurfaceClipped(_, _)) => ()
    Err(e) => fail(e.describe())
  }
}

///|
/// 退化参数：`scale(0)` 让场值变成 Inf/NaN，插值会把它放大成垃圾三角形，
/// 所以必须在采样阶段就抓出来，而不是等切片软件报错。
test "non-finite field is rejected" {
  let degenerate = @mooncsg.Sdf::sphere(1.0).scale(0.0)
  let bounds = @mooncsg.Aabb::from_center_half(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::splat(2.0),
  )
  match
    @mooncsg.mesh_checked(degenerate, bounds, @mooncsg.MeshOptions::new(12)) {
    Ok(_) => fail("非有限场值必须被拒绝")
    Err(@mooncsg.MeshError::NonFiniteField(_)) => ()
    Err(@mooncsg.MeshError::SurfaceClipped(_, _)) => ()
    Err(e) => fail(e.describe())
  }
}

///|
/// 采样域与实体完全不重叠：不是错误输入，但也不是「可打印实体」，报
/// `NoSurface` 比返回空网格更容易被调用方正确处理。
test "domain far from the solid is rejected as empty" {
  let sphere = @mooncsg.Sdf::sphere(1.0)
  let far = @mooncsg.Aabb::new(
    @mooncsg.Vec3::splat(100.0),
    @mooncsg.Vec3::splat(110.0),
  )
  match @mooncsg.mesh_checked(sphere, far, @mooncsg.MeshOptions::new(12)) {
    Ok(_) => fail("空域必须被拒绝")
    Err(@mooncsg.MeshError::NoSurface) => ()
    Err(e) => fail(e.describe())
  }
}

///|
/// 退化采样域（零体积）：直接报 `DegenerateBounds`，不去算 `1/h`。
test "degenerate sampling box is rejected" {
  let sphere = @mooncsg.Sdf::sphere(1.0)
  let point = @mooncsg.Aabb::new(@mooncsg.Vec3::zero(), @mooncsg.Vec3::zero())
  match @mooncsg.mesh_checked(sphere, point, @mooncsg.MeshOptions::new(12)) {
    Ok(_) => fail("零体积采样域必须被拒绝")
    Err(@mooncsg.MeshError::DegenerateBounds) => ()
    Err(e) => fail(e.describe())
  }
}

///|
/// 「自动采样的默认做法」必须真的给出保证：60 个随机实体，包围盒取
/// `bounds().expand(0.5)`，全部通过检查且闭合。这条测试是 `mesh_checked`
/// 承诺的实证，不是文档里的形容词。
test "checked meshing stays closed over random solids" {
  let mut state = 424242UL
  let mut i = 0
  let mut closed = 0
  while i < 60 {
    state = next_state(state)
    let r = 2.0 + unit(state) * 8.0
    state = next_state(state)
    let kind = (unit(state) * 5.0).to_int()
    let solid = match kind {
      0 => @mooncsg.Sdf::sphere(r)
      1 => @mooncsg.Sdf::box(@mooncsg.Vec3::splat(r))
      2 => @mooncsg.Sdf::cylinder(r * 0.5, r)
      3 => @mooncsg.Sdf::cone(0.0, r * 0.6, r)
      _ => @mooncsg.Sdf::capsule(r * 0.4, r * 0.8)
    }
    state = next_state(state)
    let sdf = solid.at(@mooncsg.Vec3::new(unit(state) * 4.0 - 2.0, 0.0, 0.0))
    let bounds = match sdf.bounds() {
      Some(b) => b.expand(0.5)
      None => {
        fail("实体必须有包围盒")
        @mooncsg.Aabb::new(@mooncsg.Vec3::zero(), @mooncsg.Vec3::zero())
      }
    }
    match @mooncsg.mesh_checked(sdf, bounds, @mooncsg.MeshOptions::new(20)) {
      Ok(m) =>
        if m.is_watertight() && m.open_edges() == 0 && m.volume() > 0.0 {
          closed = closed + 1
        }
      Err(_) => ()
    }
    i = i + 1
  }
  assert_eq(closed, 60)
}
