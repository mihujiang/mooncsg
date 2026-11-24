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

///|
test "torus matches analytic distance on parametric construction" {
  // 环面：母线半径 R=8、管半径 r=3。参数点
  //   P(θ, φ) = ((R + r cosφ) cosθ, (R + r cosφ) sinθ, r sinφ)
  // 的单位法向是 n = (cosφ cosθ, cosφ sinθ, sinφ)，所以 P + t·n 到环面的
  // 距离恒等于 t（带符号）。这条构造路径完全不经过被测的距离公式，只是
  // 借用了环面的几何定义。单位圆上的 (cos, sin) 用有理参数化取，不引入
  // 三角函数：u ∈ [-1, 1] 给出半圆，再随机翻一个符号补上另外半圈。
  let torus = @mooncsg.Sdf::torus(8.0, 3.0)
  let mut state = 20261116UL
  let mut i = 0
  let mut max_err = 0.0
  while i < 500 {
    state = next_state(state)
    let u1 = unit(state) * 2.0 - 1.0
    state = next_state(state)
    let u2 = unit(state) * 2.0 - 1.0
    state = next_state(state)
    let sgn1 = if unit(state) < 0.5 { 1.0 } else { -1.0 }
    state = next_state(state)
    let sgn2 = if unit(state) < 0.5 { 1.0 } else { -1.0 }
    let ct = (1.0 - u1 * u1) / (1.0 + u1 * u1)
    let st = sgn1 * 2.0 * u1 / (1.0 + u1 * u1)
    let cf = (1.0 - u2 * u2) / (1.0 + u2 * u2)
    let sf = sgn2 * 2.0 * u2 / (1.0 + u2 * u2)
    state = next_state(state)
    let t = (unit(state) - 0.5) * 2.0
    let ring = 8.0 + 3.0 * cf
    let p = @mooncsg.Vec3::new(
      ring * ct + t * cf * ct,
      ring * st + t * cf * st,
      3.0 * sf + t * sf,
    )
    let err = (torus.eval(p) - t).abs()
    if err > max_err {
      max_err = err
    }
    i = i + 1
  }
  assert_true(max_err < 1.0e-12)
}

///|
test "mat3 orthonormality check accepts rotations and rejects scaling" {
  // 单位阵的点积精确是 0 / 1，容差给 0 也应该通过。
  assert_true(@mooncsg.Mat3::identity().is_orthonormal(0.0))
  // 绕 z 轴旋转：列由半角有理参数化给出，cos² + sin² 只在末位有舍入，
  // 所以这里不猜一个容差，而是把实际偏差测出来再卡阈值。
  let mut state = 20261124UL
  let mut i = 0
  let mut worst = 0.0
  while i < 200 {
    state = next_state(state)
    let u = unit(state) * 2.0 - 1.0
    state = next_state(state)
    let sgn = if unit(state) < 0.5 { 1.0 } else { -1.0 }
    let ct = (1.0 - u * u) / (1.0 + u * u)
    let st = sgn * 2.0 * u / (1.0 + u * u)
    let rot = @mooncsg.Mat3::from_columns(
      @mooncsg.Vec3::new(ct, st, 0.0),
      @mooncsg.Vec3::new(-st, ct, 0.0),
      @mooncsg.Vec3::new(0.0, 0.0, 1.0),
    )
    assert_true(rot.is_orthonormal(1.0e-14))
    // 旋转的逆（转置）当然也是正交阵。
    assert_true(rot.transpose().is_orthonormal(1.0e-14))
    let dev = (rot.c0.dot(rot.c0) - 1.0).abs()
    if dev > worst {
      worst = dev
    }
    i = i + 1
  }
  assert_true(worst < 1.0e-14)

  // 拉伸：列长不是 1，距离场会被整体缩放。
  let stretched = @mooncsg.Mat3::from_columns(
    @mooncsg.Vec3::new(2.0, 0.0, 0.0),
    @mooncsg.Vec3::new(0.0, 1.0, 0.0),
    @mooncsg.Vec3::new(0.0, 0.0, 1.0),
  )
  assert_true(!stretched.is_orthonormal(1.0e-12))
  // 剪切：每列长度都是 1，只有两列点积不为 0，单位化救不回来。
  let sheared = @mooncsg.Mat3::from_columns(
    @mooncsg.Vec3::new(1.0, 0.0, 0.0),
    @mooncsg.Vec3::new(1.0, 1.0, 0.0).normalize(),
    @mooncsg.Vec3::new(0.0, 0.0, 1.0),
  )
  assert_true(!sheared.is_orthonormal(1.0e-12))
  // 零矩阵：列长全为 0，整个空间塌成一点。
  let zero = @mooncsg.Mat3::from_columns(
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::zero(),
    @mooncsg.Vec3::zero(),
  )
  assert_true(!zero.is_orthonormal(1.0e-12))
  // 容差是逐项比较，不是整体误差：1e-9 的拉伸在严阈值下不过、宽阈值下过。
  let nudged = @mooncsg.Mat3::from_columns(
    @mooncsg.Vec3::new(1.0 + 1.0e-9, 0.0, 0.0),
    @mooncsg.Vec3::new(0.0, 1.0, 0.0),
    @mooncsg.Vec3::new(0.0, 0.0, 1.0),
  )
  assert_true(!nudged.is_orthonormal(1.0e-12))
  assert_true(nudged.is_orthonormal(1.0e-6))
}

///|
test "gradient is unit length and advances distance one-to-one" {
  // 精确 SDF 的两条性质：|∇f| = 1，且沿法线走 t 距离正好变 t。这两条不依赖
  // 「另一个梯度实现」，所以对解析梯度与中心差分同时成立——换了实现这条
  // 测试照样有意义（中心差分的误差会顶到 1e-10 以外，测试会红）。
  let shapes : Array[@mooncsg.Sdf] = [
    @mooncsg.Sdf::sphere(10.0),
    @mooncsg.Sdf::box(@mooncsg.Vec3::new(6.0, 4.0, 5.0)),
    @mooncsg.Sdf::cylinder(5.0, 7.0),
    @mooncsg.Sdf::capsule(3.0, 5.0),
    @mooncsg.Sdf::torus(8.0, 3.0),
    // 旋转只对正交矩阵保证距离语义，这里用绕 z 轴 90° 的精确旋转。
    @mooncsg.Sdf::sphere(10.0)
    .rotate(
      @mooncsg.Mat3::from_columns(
        @mooncsg.Vec3::new(0.0, 1.0, 0.0),
        @mooncsg.Vec3::new(-1.0, 0.0, 0.0),
        @mooncsg.Vec3::new(0.0, 0.0, 1.0),
      ),
    )
    .at(@mooncsg.Vec3::new(2.0, -3.0, 1.0)),
  ]
  let step = 0.05
  for sdf in shapes {
    let mut i = 0
    while i < 200 {
      let p = sample(20261124UL, i)
      let g = sdf.gradient(p)
      let len = g.length()
      assert_true((len - 1.0).abs() < 1.0e-12)
      let n = g.div(len)
      let err = (sdf.eval(p.add(n.mul(step))) - (sdf.eval(p) + step)).abs()
      assert_true(err < 1.0e-10)
      i = i + 1
    }
  }
}
