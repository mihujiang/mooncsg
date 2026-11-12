///|
/// 三角网格：位置数组 + 索引数组（每 3 个索引一个三角形）。
///
/// 顶点是焊接过的——同一个几何位置只出现一次，否则「每条边恰好 2 面」
/// 这个水密判据会被重复顶点破坏。索引用 `Int`，`Int` 在 wasm-gc 是 32 位，
/// 顶点数上限 2^31 对建模场景足够。
pub(all) struct Mesh {
  positions : Array[Vec3]
  indices : Array[Int32]
}

///|
pub fn Mesh::new(positions : Array[Vec3], indices : Array[Int32]) -> Mesh {
  { positions, indices, }
}

///|
pub fn Mesh::empty() -> Mesh {
  { positions: [], indices: [], }
}

///|
pub fn Mesh::triangle_count(self : Mesh) -> Int32 {
  self.indices.length() / 3
}

///|
pub fn Mesh::vertex_count(self : Mesh) -> Int32 {
  self.positions.length()
}

///|
pub fn Mesh::is_empty(self : Mesh) -> Bool {
  self.indices.length() == 0
}

///|
/// 第 `i` 个三角形的三个顶点。
pub fn Mesh::triangle(self : Mesh, i : Int32) -> (Vec3, Vec3, Vec3) {
  let a = self.positions[self.indices[i * 3]]
  let b = self.positions[self.indices[i * 3 + 1]]
  let c = self.positions[self.indices[i * 3 + 2]]
  (a, b, c)
}

///|
/// 散度定理求体积：`V = Σ a · (b × c) / 6`。
///
/// 朝向正确时结果为正，所以这个数同时充当朝向自检——不需要再单独
/// 遍历面判法线。
pub fn Mesh::volume(self : Mesh) -> Double {
  let mut six_v = 0.0
  let mut i = 0
  while i < self.triangle_count() {
    let (a, b, c) = self.triangle(i)
    six_v = six_v + a.dot(b.cross(c))
    i = i + 1
  }
  six_v / 6.0
}

///|
pub fn Mesh::area(self : Mesh) -> Double {
  let mut sum = 0.0
  let mut i = 0
  while i < self.triangle_count() {
    let (a, b, c) = self.triangle(i)
    sum = sum + b.sub(a).cross(c.sub(a)).length() * 0.5
    i = i + 1
  }
  sum
}

///|
/// 翻转全部三角形。朝向统一翻，不逐面判断——逐面判断在凹面上会被
/// 数值梯度的噪声带偏。
pub fn Mesh::flipped(self : Mesh) -> Mesh {
  let out : Array[Int32] = []
  let mut i = 0
  while i < self.triangle_count() {
    out.push(self.indices[i * 3])
    out.push(self.indices[i * 3 + 2])
    out.push(self.indices[i * 3 + 1])
    i = i + 1
  }
  { positions: self.positions, indices: out, }
}

///|
/// 归并排序（整型键）。不用标准库的排序，是因为这里要的是「排序结果与
/// 输入顺序无关、且同输入逐字节可复现」；自己写一份反而是最省心的保证。
fn sort_i64(a : Array[Int64]) -> Array[Int64] {
  let n = a.length()
  if n <= 1 {
    return a
  }
  let mid = n / 2
  let left : Array[Int64] = []
  let right : Array[Int64] = []
  let mut i = 0
  while i < mid {
    left.push(a[i])
    i = i + 1
  }
  while i < n {
    right.push(a[i])
    i = i + 1
  }
  let l = sort_i64(left)
  let r = sort_i64(right)
  let out : Array[Int64] = []
  let mut p = 0
  let mut q = 0
  while p < l.length() && q < r.length() {
    if l[p] <= r[q] {
      out.push(l[p])
      p = p + 1
    } else {
      out.push(r[q])
      q = q + 1
    }
  }
  while p < l.length() {
    out.push(l[p])
    p = p + 1
  }
  while q < r.length() {
    out.push(r[q])
    q = q + 1
  }
  out
}

///|
/// 每条边编码成 `min * V + max` 后的升序数组。`V` 是顶点数，
/// 所以编码无歧义；`V` 不会超过 2^31，乘积在 `Int64` 内。
pub fn Mesh::edge_keys(self : Mesh) -> Array[Int64] {
  let n = self.vertex_count().to_int64()
  let keys : Array[Int64] = []
  let mut i = 0
  while i < self.triangle_count() {
    let a = self.indices[i * 3].to_int64()
    let b = self.indices[i * 3 + 1].to_int64()
    let c = self.indices[i * 3 + 2].to_int64()
    keys.push((if a < b { a } else { b }) * n + (if a < b { b } else { a }))
    keys.push((if b < c { b } else { c }) * n + (if b < c { c } else { b }))
    keys.push((if c < a { c } else { a }) * n + (if c < a { a } else { c }))
    i = i + 1
  }
  sort_i64(keys)
}

///|
/// 水密：每条无向边恰好被 2 个三角形共享。
pub fn Mesh::is_watertight(self : Mesh) -> Bool {
  let keys = self.edge_keys()
  let mut i = 0
  while i < keys.length() {
    let mut j = i + 1
    while j < keys.length() && keys[j] == keys[i] {
      j = j + 1
    }
    if j - i != 2 {
      return false
    }
    i = j
  }
  true
}

///|
/// 唯一边数。
pub fn Mesh::edge_count(self : Mesh) -> Int32 {
  let keys = self.edge_keys()
  let mut count = 0
  let mut i = 0
  while i < keys.length() {
    let mut j = i + 1
    while j < keys.length() && keys[j] == keys[i] {
      j = j + 1
    }
    count = count + 1
    i = j
  }
  count
}

///|
/// 欧拉示性数 `V - E + F`。闭合曲面上等于 `2 - 2g`。
pub fn Mesh::euler(self : Mesh) -> Int32 {
  self.vertex_count() - self.edge_count() + self.triangle_count()
}

///|
/// 亏格。欧拉示性数为奇数说明网格不闭合或不连通处有共享顶点，
/// 返回 `-1` 而不是编一个数。
pub fn Mesh::genus(self : Mesh) -> Int32 {
  let chi = self.euler()
  if chi % 2 != 0 {
    return -1
  }
  (2 - chi) / 2
}

///|
pub fn Mesh::bounds(self : Mesh) -> Aabb {
  if self.positions.length() == 0 {
    return Aabb::new(Vec3::zero(), Vec3::zero())
  }
  let mut lo = self.positions[0]
  let mut hi = self.positions[0]
  for p in self.positions {
    lo = lo.min(p)
    hi = hi.max(p)
  }
  Aabb::new(lo, hi)
}
