///|
/// 确定性伪随机：测试不要依赖 std 的随机源，否则失败无法复现。
fn next_state(state : UInt64) -> UInt64 {
  state * 6364136223846793005UL + 1442695040888963407UL
}

///|
/// 把 64 位状态映射到 `[0, 1)`。
fn unit(state : UInt64) -> Double {
  (state >> 11).to_double() / 9007199254740992.0
}

///|
/// 生成第 `i` 个采样点，坐标落在 `[-40, 40]`。
fn sample(seed : UInt64, i : Int32) -> @mooncsg.Vec3 {
  let s1 = next_state(seed + i.to_uint64() * 3UL)
  let s2 = next_state(s1)
  let s3 = next_state(s2)
  @mooncsg.Vec3::new(
    unit(s1) * 80.0 - 40.0,
    unit(s2) * 80.0 - 40.0,
    unit(s3) * 80.0 - 40.0,
  )
}

///|
test "sphere matches analytic distance on 1000 points" {
  let center = @mooncsg.Vec3::new(3.0, -4.0, 5.0)
  let radius = 25.0
  let s = @mooncsg.Sdf::sphere(radius).at(center)
  let mut i = 0
  while i < 1000 {
    let p = sample(12345UL, i)
    let d = p.sub(center).length() - radius
    assert_true((s.eval(p) - d).abs() < 1.0e-12)
    i = i + 1
  }
}

///|
test "box matches analytic distance on 1000 points" {
  let center = @mooncsg.Vec3::new(1.0, 2.0, 3.0)
  let half = @mooncsg.Vec3::new(4.0, 5.0, 6.0)
  let s = @mooncsg.Sdf::box(half).at(center)
  let mut i = 0
  while i < 1000 {
    let p = sample(999UL, i)
    let q = p.sub(center).abs().sub(half)
    let outside = @mooncsg.Vec3::new(
      if q.x > 0.0 {
        q.x
      } else {
        0.0
      },
      if q.y > 0.0 {
        q.y
      } else {
        0.0
      },
      if q.z > 0.0 {
        q.z
      } else {
        0.0
      },
    ).length()
    let inside = if q.x > q.y { q.x } else { q.y }
    let inside = if inside > q.z { inside } else { q.z }
    let d = outside + (if inside < 0.0 { inside } else { 0.0 })
    assert_true((s.eval(p) - d).abs() < 1.0e-12)
    i = i + 1
  }
}

///|
test "cylinder and plane match analytic distance" {
  let s = @mooncsg.Sdf::cylinder(7.0, 10.0)
  let plane = @mooncsg.Sdf::plane(@mooncsg.Vec3::new(0.0, 0.0, 1.0), 5.0)
  let mut i = 0
  while i < 1000 {
    let p = sample(424242UL, i)
    let radial = (p.x * p.x + p.y * p.y).sqrt() - 7.0
    let axial = p.z.abs() - 10.0
    let outside = (if radial > 0.0 { radial } else { 0.0 }) *
      (if radial > 0.0 { radial } else { 0.0 })
    let outside2 = outside +
      (if axial > 0.0 { axial } else { 0.0 }) *
      (if axial > 0.0 { axial } else { 0.0 })
    let d = if radial < 0.0 && axial < 0.0 {
      if radial > axial {
        radial
      } else {
        axial
      }
    } else {
      outside2.sqrt()
    }
    assert_true((s.eval(p) - d).abs() < 1.0e-9)
    assert_true((plane.eval(p) - (p.z - 5.0)).abs() < 1.0e-12)
    i = i + 1
  }
}

///|
test "booleans agree with min max and negation" {
  let a = @mooncsg.Sdf::sphere(25.0)
  let b = @mooncsg.Sdf::sphere(10.0).at(@mooncsg.Vec3::new(15.0, 0.0, 0.0))
  let union = a.union(b)
  let inter = a.intersect(b)
  let diff = a.subtract(b)
  let mut i = 0
  while i < 1000 {
    let p = sample(7UL, i)
    let da = a.eval(p)
    let db = b.eval(p)
    assert_true(
      (union.eval(p) - (if da < db { da } else { db })).abs() < 1.0e-12,
    )
    assert_true(
      (inter.eval(p) - (if da > db { da } else { db })).abs() < 1.0e-12,
    )
    let neg = -db
    assert_true(
      (diff.eval(p) - (if da > neg { da } else { neg })).abs() < 1.0e-12,
    )
    i = i + 1
  }
}

///|
test "subtract keeps inside points negative and hole points positive" {
  let a = @mooncsg.Sdf::sphere(25.0)
  let b = @mooncsg.Sdf::sphere(10.0).at(@mooncsg.Vec3::new(15.0, 0.0, 0.0))
  let cut = a.subtract(b)
  // A 内、B 外
  assert_true(cut.eval(@mooncsg.Vec3::new(-10.0, 0.0, 0.0)) < 0.0)
  // 落在 B 里：被挖掉
  assert_true(cut.eval(@mooncsg.Vec3::new(15.0, 0.0, 0.0)) > 0.0)
  // A 外
  assert_true(cut.eval(@mooncsg.Vec3::new(60.0, 0.0, 0.0)) > 0.0)
  assert_true(!cut.is_inside(@mooncsg.Vec3::new(15.0, 0.0, 0.0)))
}

///|
test "translate rotate scale compose correctly" {
  // 绕 z 轴 90°：x -> y, y -> -x
  let rot = @mooncsg.Mat3::from_columns(
    @mooncsg.Vec3::new(0.0, 1.0, 0.0),
    @mooncsg.Vec3::new(-1.0, 0.0, 0.0),
    @mooncsg.Vec3::new(0.0, 0.0, 1.0),
  )
  let s = @mooncsg.Sdf::Box(
    @mooncsg.Vec3::new(0.0, 0.0, 0.0),
    @mooncsg.Vec3::new(10.0, 2.0, 3.0),
  )
  let placed = @mooncsg.Sdf::Rotate(
    @mooncsg.Sdf::Translate(
      @mooncsg.Sdf::Scale(s, 2.0),
      @mooncsg.Vec3::new(5.0, 0.0, 0.0),
    ),
    rot,
  )
  // 世界点先转回局部、再减平移、再除缩放，与被测实现等价
  let p = @mooncsg.Vec3::new(1.0, 7.0, 0.5)
  let lp = rot.transpose().mul_vec(p).sub(@mooncsg.Vec3::new(5.0, 0.0, 0.0))
  let expect = s.eval(lp.div(2.0)) * 2.0
  assert_true((placed.eval(p) - expect).abs() < 1.0e-12)
  // 缩放后局部 x 半长是 20，且内层平移量是 5：世界 y=23 对应局部 x=9，
  // 世界 y=26 对应局部 x=10.5，一个在内一个在外。
  assert_true(placed.eval(@mooncsg.Vec3::new(0.0, 23.0, 0.0)) < 0.0)
  assert_true(placed.eval(@mooncsg.Vec3::new(0.0, 26.0, 0.0)) > 0.0)
}

///|
test "bounds cover the solid and follow booleans" {
  let sphere = @mooncsg.Sdf::sphere(25.0)
  let b = sphere.bounds()
  assert_true(b is Some(_))
  match b {
    Some(b) => {
      assert_true(b.min.x < -25.0 + 1.0e-9)
      assert_true(b.max.z > 25.0 - 1.0e-9)
      assert_true(b.contains(@mooncsg.Vec3::new(0.0, 0.0, 0.0)))
      assert_true(!b.contains(@mooncsg.Vec3::new(30.0, 0.0, 0.0)))
    }
    None => fail("sphere must have bounds")
  }
  // 半空间没有有限包围盒
  assert_true(
    @mooncsg.Sdf::plane(@mooncsg.Vec3::new(0.0, 0.0, 1.0), 0.0).bounds() is None,
  )
  // 差集只受被减体约束
  let cut = sphere.subtract(
    @mooncsg.Sdf::sphere(10.0).at(@mooncsg.Vec3::new(15.0, 0.0, 0.0)),
  )
  match cut.bounds() {
    Some(b) => assert_true((b.max.x - 25.0).abs() < 1.0e-9)
    None => fail("subtract must keep the left bounds")
  }
}

///|
test "zero thickness and empty cases stay finite" {
  // 完全包含：A 被 B 包住 -> 处处为正
  let small = @mooncsg.Sdf::sphere(5.0)
  let big = @mooncsg.Sdf::sphere(30.0)
  let empty = small.subtract(big)
  assert_true(empty.eval(@mooncsg.Vec3::new(0.0, 0.0, 0.0)) > 0.0)
  assert_true(empty.bounds() is Some(_))
  // 自减：同样处处非负
  let same = big.subtract(big)
  let mut i = 0
  while i < 100 {
    let p = sample(31UL, i)
    assert_true(same.eval(p) >= -1.0e-12)
    i = i + 1
  }
}

///|
test "cone degenerates to cylinder when radii match" {
  let cone = @mooncsg.Sdf::cone(7.0, 7.0, 10.0)
  let cyl = @mooncsg.Sdf::cylinder(7.0, 10.0)
  let mut i = 0
  while i < 1000 {
    let p = sample(2024UL, i)
    assert_true((cone.eval(p) - cyl.eval(p)).abs() < 1.0e-12)
    i = i + 1
  }
}

///|
test "cone matches analytic distance on the axis and the apex" {
  // 圆锥：z=-10 处半径 0（顶点），z=+10 处半径 5。
  // 侧棱在 (radial, axial) 平面是直线 4*radial - axial - 10 = 0，
  // 原点到这条直线的距离是 10/sqrt(17)。
  let cone = @mooncsg.Sdf::cone(0.0, 5.0, 10.0)
  assert_true(
    (cone.eval(@mooncsg.Vec3::new(0.0, 0.0, 0.0)) + 2.4253562503633324).abs() <
    1.0e-12,
  )
  // 顶点正下方 1 个单位
  assert_true(
    (cone.eval(@mooncsg.Vec3::new(0.0, 0.0, -11.0)) - 1.0).abs() < 1.0e-12,
  )
  // 顶点本身
  assert_true(cone.eval(@mooncsg.Vec3::new(0.0, 0.0, -10.0)).abs() < 1.0e-12)
}

///|
test "capsule matches analytic distance and degenerates to sphere" {
  let ball = @mooncsg.Sdf::sphere(7.0)
  let degenerate = @mooncsg.Sdf::capsule(7.0, 0.0)
  let mut i = 0
  while i < 1000 {
    let p = sample(5150UL, i)
    assert_true((degenerate.eval(p) - ball.eval(p)).abs() < 1.0e-12)
    i = i + 1
  }
  let cap = @mooncsg.Sdf::capsule(3.0, 5.0)
  assert_true(
    (cap.eval(@mooncsg.Vec3::new(0.0, 0.0, 9.0)) - 1.0).abs() < 1.0e-12,
  )
  assert_true(
    (cap.eval(@mooncsg.Vec3::new(0.0, 0.0, -9.0)) - 1.0).abs() < 1.0e-12,
  )
  assert_true(
    (cap.eval(@mooncsg.Vec3::new(4.0, 0.0, 3.0)) - 1.0).abs() < 1.0e-12,
  )
  assert_true(
    (cap.eval(@mooncsg.Vec3::new(0.0, 0.0, 0.0)) + 3.0).abs() < 1.0e-12,
  )
  // 精确 SDF 的梯度模长为 1
  assert_true(
    (cap.gradient(@mooncsg.Vec3::new(10.0, 0.0, 0.0)).length() - 1.0).abs() <
    1.0e-6,
  )
}

///|
test "cone and capsule bounds cover the solid" {
  match @mooncsg.Sdf::cone(2.0, 9.0, 10.0).bounds() {
    Some(b) => {
      assert_true((b.max.x - 9.0).abs() < 1.0e-12)
      assert_true((b.max.z - 10.0).abs() < 1.0e-12)
      assert_true(b.contains(@mooncsg.Vec3::new(0.0, 0.0, 9.0)))
      assert_true(!b.contains(@mooncsg.Vec3::new(9.5, 0.0, 0.0)))
    }
    None => fail("cone must have bounds")
  }
  match @mooncsg.Sdf::capsule(3.0, 5.0).bounds() {
    Some(b) => assert_true((b.max.z - 8.0).abs() < 1.0e-12)
    None => fail("capsule must have bounds")
  }
}
