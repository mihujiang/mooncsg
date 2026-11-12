///|
/// 三维向量。几何内核只做静态求值，所有分量用 `Double`：
/// 这里的正确性标准是「与解析公式逐点一致」，不是跨后端逐位一致
/// （后者是 moonroll 的定点数要解决的问题）。
pub(all) struct Vec3 {
  x : Double
  y : Double
  z : Double
}

///|
pub fn Vec3::new(x : Double, y : Double, z : Double) -> Vec3 {
  { x, y, z, }
}

///|
pub fn Vec3::zero() -> Vec3 {
  { x: 0.0, y: 0.0, z: 0.0, }
}

///|
pub fn Vec3::splat(v : Double) -> Vec3 {
  { x: v, y: v, z: v, }
}

///|
pub fn Vec3::add(self : Vec3, o : Vec3) -> Vec3 {
  { x: self.x + o.x, y: self.y + o.y, z: self.z + o.z, }
}

///|
pub fn Vec3::sub(self : Vec3, o : Vec3) -> Vec3 {
  { x: self.x - o.x, y: self.y - o.y, z: self.z - o.z, }
}

///|
pub fn Vec3::neg(self : Vec3) -> Vec3 {
  { x: -self.x, y: -self.y, z: -self.z, }
}

///|
pub fn Vec3::mul(self : Vec3, s : Double) -> Vec3 {
  { x: self.x * s, y: self.y * s, z: self.z * s, }
}

///|
/// 逐分量乘。
pub fn Vec3::mul_vec(self : Vec3, o : Vec3) -> Vec3 {
  { x: self.x * o.x, y: self.y * o.y, z: self.z * o.z, }
}

///|
pub fn Vec3::div(self : Vec3, s : Double) -> Vec3 {
  { x: self.x / s, y: self.y / s, z: self.z / s, }
}

///|
pub fn Vec3::dot(self : Vec3, o : Vec3) -> Double {
  self.x * o.x + self.y * o.y + self.z * o.z
}

///|
pub fn Vec3::cross(self : Vec3, o : Vec3) -> Vec3 {
  {
    x: self.y * o.z - self.z * o.y,
    y: self.z * o.x - self.x * o.z,
    z: self.x * o.y - self.y * o.x,
  }
}

///|
pub fn Vec3::length_sq(self : Vec3) -> Double {
  self.dot(self)
}

///|
pub fn Vec3::length(self : Vec3) -> Double {
  self.length_sq().sqrt()
}

///|
/// 零向量归一化返回零向量：调用方不该靠 panic 处理退化输入。
pub fn Vec3::normalize(self : Vec3) -> Vec3 {
  let len = self.length()
  if len == 0.0 {
    self
  } else {
    self.div(len)
  }
}

///|
pub fn Vec3::abs(self : Vec3) -> Vec3 {
  {
    x: if self.x < 0.0 {
      -self.x
    } else {
      self.x
    },
    y: if self.y < 0.0 {
      -self.y
    } else {
      self.y
    },
    z: if self.z < 0.0 {
      -self.z
    } else {
      self.z
    },
  }
}

///|
/// 逐分量 `max(v, 0)`，SDF 盒公式里反复用到。
pub fn Vec3::max_zero(self : Vec3) -> Vec3 {
  {
    x: if self.x > 0.0 {
      self.x
    } else {
      0.0
    },
    y: if self.y > 0.0 {
      self.y
    } else {
      0.0
    },
    z: if self.z > 0.0 {
      self.z
    } else {
      0.0
    },
  }
}

///|
pub fn Vec3::min(self : Vec3, o : Vec3) -> Vec3 {
  {
    x: if self.x < o.x {
      self.x
    } else {
      o.x
    },
    y: if self.y < o.y {
      self.y
    } else {
      o.y
    },
    z: if self.z < o.z {
      self.z
    } else {
      o.z
    },
  }
}

///|
pub fn Vec3::max(self : Vec3, o : Vec3) -> Vec3 {
  {
    x: if self.x > o.x {
      self.x
    } else {
      o.x
    },
    y: if self.y > o.y {
      self.y
    } else {
      o.y
    },
    z: if self.z > o.z {
      self.z
    } else {
      o.z
    },
  }
}

///|
pub fn Vec3::lerp(self : Vec3, o : Vec3, t : Double) -> Vec3 {
  self.add(o.sub(self).mul(t))
}

///|
/// 3×3 矩阵，按列存：`c0`/`c1`/`c2` 是三个基向量。
///
/// 按列存是为了 `mul_vec` 写成一次线性组合——这也是后面做旋转
/// 与梯度变换时唯一需要的方向。
pub(all) struct Mat3 {
  c0 : Vec3
  c1 : Vec3
  c2 : Vec3
}

///|
pub fn Mat3::identity() -> Mat3 {
  {
    c0: Vec3::new(1.0, 0.0, 0.0),
    c1: Vec3::new(0.0, 1.0, 0.0),
    c2: Vec3::new(0.0, 0.0, 1.0),
  }
}

///|
pub fn Mat3::from_columns(c0 : Vec3, c1 : Vec3, c2 : Vec3) -> Mat3 {
  { c0, c1, c2, }
}

///|
pub fn Mat3::mul_vec(self : Mat3, v : Vec3) -> Vec3 {
  self.c0.mul(v.x).add(self.c1.mul(v.y)).add(self.c2.mul(v.z))
}

///|
/// 转置：旋转的逆。SDF 变换里要用它把世界坐标拉回局部坐标。
pub fn Mat3::transpose(self : Mat3) -> Mat3 {
  {
    c0: Vec3::new(self.c0.x, self.c1.x, self.c2.x),
    c1: Vec3::new(self.c0.y, self.c1.y, self.c2.y),
    c2: Vec3::new(self.c0.z, self.c1.z, self.c2.z),
  }
}

///|
/// 轴对齐包围盒。`min` 逐分量小于等于 `max` 才是有效盒。
pub(all) struct Aabb {
  min : Vec3
  max : Vec3
}

///|
pub fn Aabb::new(min : Vec3, max : Vec3) -> Aabb {
  { min, max, }
}

///|
pub fn Aabb::from_center_half(center : Vec3, half : Vec3) -> Aabb {
  { min: center.sub(half), max: center.add(half), }
}

///|
pub fn Aabb::center(self : Aabb) -> Vec3 {
  self.min.add(self.max).mul(0.5)
}

///|
pub fn Aabb::size(self : Aabb) -> Vec3 {
  self.max.sub(self.min)
}

///|
/// 空盒用「min > max」表示，不额外加标志位。
pub fn Aabb::is_empty(self : Aabb) -> Bool {
  self.min.x > self.max.x || self.min.y > self.max.y || self.min.z > self.max.z
}

///|
pub fn Aabb::union(self : Aabb, o : Aabb) -> Aabb {
  { min: self.min.min(o.min), max: self.max.max(o.max), }
}

///|
pub fn Aabb::intersect(self : Aabb, o : Aabb) -> Aabb {
  { min: self.min.max(o.min), max: self.max.min(o.max), }
}

///|
/// 各方向等比外扩 `r`，网格化时用来给采样留一圈边界。
pub fn Aabb::expand(self : Aabb, r : Double) -> Aabb {
  { min: self.min.sub(Vec3::splat(r)), max: self.max.add(Vec3::splat(r)), }
}

///|
pub fn Aabb::contains(self : Aabb, p : Vec3) -> Bool {
  p.x >= self.min.x &&
  p.y >= self.min.y &&
  p.z >= self.min.z &&
  p.x <= self.max.x &&
  p.y <= self.max.y &&
  p.z <= self.max.z
}

///|
pub fn Aabb::diagonal(self : Aabb) -> Double {
  self.size().length()
}
