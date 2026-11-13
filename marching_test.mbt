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
