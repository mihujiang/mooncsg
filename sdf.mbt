///|
/// 有符号距离场（SDF）。
///
/// 约定：实体内部为负、外部为正、边界为 0。所有原语与布尔都保持这个约定，
/// 因为它们只由 `min` / `max` / `-` 组合，而这三个运算保号。
///
/// 树是公开的（`pub(all)`）：调用方可以直接构造，也可以把自己的节点
/// 写进 `eval` 之外的分析（例如 `bounds`）。递归节点不做共享引用，
/// 同一棵子树被复用两次就是两份拷贝——几何树很小，不做引用计数。
pub(all) enum Sdf {
  /// 球：`center` + `radius`。
  Sphere(Vec3, Double)
  /// 盒：`center` + 逐轴半长 `half`。
  Box(Vec3, Vec3)
  /// 半空间：`dot(p, normal) = offset`，法线朝外（正侧是外部）。
  /// `normal` 在构造时归一化，直接字面量构造则按传入值计算。
  Plane(Vec3, Double)
  /// 圆柱：轴沿 z，`center` + `radius` + 半高 `half_height`。
  Cylinder(Vec3, Double, Double)
  /// 环面：轴沿 z，`center` + 母线半径 `big` + 管半径 `small`。
  Torus(Vec3, Double, Double)
  /// 平移：先减去 `t` 再求值。
  Translate(Sdf, Vec3)
  /// 旋转：`m` 的列是局部基，求值时用转置把世界坐标拉回局部。
  Rotate(Sdf, Mat3)
  /// 均匀缩放。非正值视为空实体（SDF 恒为 0，网格化会得到空结果）。
  Scale(Sdf, Double)
  /// 并：`min(a, b)`。
  Union(Sdf, Sdf)
  /// 交：`max(a, b)`。
  Intersect(Sdf, Sdf)
  /// 差：`max(a, -b)`，`b` 是刀具。
  Subtract(Sdf, Sdf)
  /// 平滑并，`k` 是过渡带宽度；`k <= 0` 退化为硬并。
  SmoothUnion(Sdf, Sdf, Double)
}

///|
pub fn Sdf::sphere(radius : Double) -> Sdf {
  Sphere(Vec3::zero(), radius)
}

///|
pub fn Sdf::box(half : Vec3) -> Sdf {
  Box(Vec3::zero(), half)
}

///|
/// 法线在这里归一化：`Plane` 的距离公式要求 `|normal| = 1`，
/// 否则返回值会被整体缩放。
pub fn Sdf::plane(normal : Vec3, offset : Double) -> Sdf {
  Plane(normal.normalize(), offset)
}

///|
pub fn Sdf::cylinder(radius : Double, half_height : Double) -> Sdf {
  Cylinder(Vec3::zero(), radius, half_height)
}

///|
pub fn Sdf::at(self : Sdf, center : Vec3) -> Sdf {
  Translate(self, center)
}

///|
pub fn Sdf::union(self : Sdf, o : Sdf) -> Sdf {
  Union(self, o)
}

///|
pub fn Sdf::intersect(self : Sdf, o : Sdf) -> Sdf {
  Intersect(self, o)
}

///|
pub fn Sdf::subtract(self : Sdf, o : Sdf) -> Sdf {
  Subtract(self, o)
}

///|
pub fn Sdf::smooth_union(self : Sdf, o : Sdf, k : Double) -> Sdf {
  SmoothUnion(self, o, k)
}

///|
pub fn Sdf::scale(self : Sdf, s : Double) -> Sdf {
  Scale(self, s)
}

///|
fn max3(v : Vec3) -> Double {
  let m = if v.x > v.y { v.x } else { v.y }
  if m > v.z {
    m
  } else {
    v.z
  }
}

///|
fn clamp01(v : Double) -> Double {
  if v < 0.0 {
    0.0
  } else if v > 1.0 {
    1.0
  } else {
    v
  }
}

///|
fn len2(a : Double, b : Double) -> Double {
  (a * a + b * b).sqrt()
}

///|
/// 求有符号距离。这是整个内核唯一的「真相来源」：网格化、体积、法线
/// 全部由它派生，所以每个原语都直接照抄解析公式，不做近似。
pub fn Sdf::eval(self : Sdf, p : Vec3) -> Double {
  match self {
    Sphere(c, r) => p.sub(c).length() - r
    Box(c, half) => {
      let q = p.sub(c).abs().sub(half)
      let inside = max3(q)
      q.max_zero().length() + (if inside < 0.0 { inside } else { 0.0 })
    }
    Plane(n, d) => p.dot(n) - d
    Cylinder(c, r, h) => {
      let q = p.sub(c)
      let radial = len2(q.x, q.y) - r
      let axial = (if q.z < 0.0 { -q.z } else { q.z }) - h
      if radial < 0.0 && axial < 0.0 {
        if radial > axial {
          radial
        } else {
          axial
        }
      } else {
        len2(
          if radial > 0.0 {
            radial
          } else {
            0.0
          },
          if axial > 0.0 {
            axial
          } else {
            0.0
          },
        )
      }
    }
    Torus(c, big, small) => {
      let q = p.sub(c)
      len2(len2(q.x, q.y) - big, q.z) - small
    }
    Translate(s, t) => s.eval(p.sub(t))
    Rotate(s, m) => s.eval(m.transpose().mul_vec(p))
    Scale(s, k) => if k <= 0.0 { 0.0 } else { s.eval(p.div(k)) * k }
    Union(a, b) => {
      let da = a.eval(p)
      let db = b.eval(p)
      if da < db {
        da
      } else {
        db
      }
    }
    Intersect(a, b) => {
      let da = a.eval(p)
      let db = b.eval(p)
      if da > db {
        da
      } else {
        db
      }
    }
    Subtract(a, b) => {
      let da = a.eval(p)
      let db = -b.eval(p)
      if da > db {
        da
      } else {
        db
      }
    }
    SmoothUnion(a, b, k) =>
      if k <= 0.0 {
        let da = a.eval(p)
        let db = b.eval(p)
        if da < db {
          da
        } else {
          db
        }
      } else {
        let da = a.eval(p)
        let db = b.eval(p)
        let h = clamp01(0.5 + 0.5 * (db - da) / k)
        db + (da - db) * h - k * h * (1.0 - h)
      }
  }
}

///|
/// 内部/外部判定。`f >= 0` 一律算外部：`f == 0` 的抖动会让网格化漏面或重面，
/// 所以边界点统一归到外部，由采样偏置处理（见 ARCHITECTURE）。
pub fn Sdf::is_inside(self : Sdf, p : Vec3) -> Bool {
  self.eval(p) < 0.0
}

///|
/// 数值梯度（中心差分）指向距离增大方向，也就是实体外部。
///
/// 步长随坐标尺度放大，避免在远处把差分吃掉；这里只用 `+ - * / sqrt`，
/// 不引入三角函数，保证同一输入的梯度在任何后端一致。
pub fn Sdf::gradient(self : Sdf, p : Vec3) -> Vec3 {
  let h = 1.0e-5 * (1.0 + p.length())
  let dx = self.eval(p.add(Vec3::new(h, 0.0, 0.0))) -
    self.eval(p.sub(Vec3::new(h, 0.0, 0.0)))
  let dy = self.eval(p.add(Vec3::new(0.0, h, 0.0))) -
    self.eval(p.sub(Vec3::new(0.0, h, 0.0)))
  let dz = self.eval(p.add(Vec3::new(0.0, 0.0, h))) -
    self.eval(p.sub(Vec3::new(0.0, 0.0, h)))
  Vec3::new(dx, dy, dz).div(2.0 * h)
}

///|
/// 保守包围盒：只做「不会漏掉实体」的放大，不求紧。
/// 半空间没有有限包围盒，参与 `Union` 时整体返回 `None`，
/// 参与 `Intersect` 时由另一侧决定，做刀具时被忽略。
pub fn Sdf::bounds(self : Sdf) -> Aabb? {
  match self {
    Sphere(c, r) => Some(Aabb::from_center_half(c, Vec3::splat(r)))
    Box(c, half) => Some(Aabb::from_center_half(c, half))
    Plane(_, _) => None
    Cylinder(c, r, h) => {
      let rr = if r < 0.0 { 0.0 } else { r }
      Some(Aabb::from_center_half(c, Vec3::new(rr, rr, h)))
    }
    Torus(c, big, small) =>
      Some(
        Aabb::from_center_half(
          c,
          Vec3::new(
            (if big > 0.0 { big } else { 0.0 }) +
            (if small > 0.0 { small } else { 0.0 }),
            (if big > 0.0 { big } else { 0.0 }) +
            (if small > 0.0 { small } else { 0.0 }),
            if small > 0.0 {
              small
            } else {
              0.0
            },
          ),
        ),
      )
    Translate(s, t) =>
      match s.bounds() {
        Some(b) => Some(Aabb::new(b.min.add(t), b.max.add(t)))
        None => None
      }
    Rotate(s, m) =>
      match s.bounds() {
        Some(b) => {
          // 旋转后的 AABB 取包围盒八个角点的包络。
          let mut out = Aabb::new(Vec3::splat(1.0e300), Vec3::splat(-1.0e300))
          let mut i = 0
          while i < 8 {
            let p = Vec3::new(
              if (i & 1) == 0 {
                b.min.x
              } else {
                b.max.x
              },
              if (i & 2) == 0 {
                b.min.y
              } else {
                b.max.y
              },
              if (i & 4) == 0 {
                b.min.z
              } else {
                b.max.z
              },
            )
            let q = m.mul_vec(p)
            out = Aabb::new(out.min.min(q), out.max.max(q))
            i = i + 1
          }
          Some(out)
        }
        None => None
      }
    Scale(s, k) =>
      match s.bounds() {
        Some(b) =>
          if k <= 0.0 {
            None
          } else {
            Some(Aabb::new(b.min.mul(k), b.max.mul(k)))
          }
        None => None
      }
    Union(a, b) =>
      match (a.bounds(), b.bounds()) {
        (Some(x), Some(y)) => Some(x.union(y))
        _ => None
      }
    SmoothUnion(a, b, k) =>
      match (a.bounds(), b.bounds()) {
        // 平滑并会让过渡带稍微鼓出，包围盒按 k/2 外扩。
        (Some(x), Some(y)) =>
          Some(x.union(y).expand(if k > 0.0 { k * 0.5 } else { 0.0 }))
        _ => None
      }
    Intersect(a, b) =>
      match (a.bounds(), b.bounds()) {
        (Some(x), Some(y)) => {
          let r = x.intersect(y)
          if r.is_empty() {
            None
          } else {
            Some(r)
          }
        }
        (Some(x), None) => Some(x)
        (None, Some(y)) => Some(y)
        (None, None) => None
      }
    Subtract(a, _) => a.bounds()
  }
}
