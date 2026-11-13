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
/// 欧拉示性数 `V - E + F`。单个闭合曲面上等于 `2 - 2g`；`k` 个不相交的
/// 闭合壳则是 `2k - 2Σgᵢ`（示性数对壳可加）。
pub fn Mesh::euler(self : Mesh) -> Int32 {
  self.vertex_count() - self.edge_count() + self.triangle_count()
}

///|
/// 亏格 `g = (2 - χ) / 2`。
///
/// 只对**单个闭合壳**是真正的亏格。多壳时返回值是 `1 - k + Σgᵢ`：`k` 个球
/// 给出 `1 - k`，看起来像负数——所以这里把「不闭合 / 多壳」一并返回 `-1`
/// （`χ` 为奇数说明不闭合，或顶点只被部分面共享），意义是「这个数为不了」，
/// 不区分具体原因。要逐壳统计得先做连通分量拆分，本雏版不做。
pub fn Mesh::genus(self : Mesh) -> Int32 {
  let chi = self.euler()
  // 单壳闭合面的 χ 是偶数且不超过 2（球 2、环面 0、双环面 -2…）；
  // χ > 2 只可能是多个壳叠在一起，此时 (2 - χ) / 2 为负，不是亏格。
  if chi % 2 != 0 || chi > 2 {
    return -1
  }
  (2 - chi) / 2
}

///|
fn fnv1a(h : UInt64, v : UInt64) -> UInt64 {
  (h ^ v) * 0x100000001b3UL
}

///|
/// 网格内容的 64 位指纹：顶点坐标的位模式（按存储顺序）+ 索引序列。
///
/// 「同输入两次网格化逐位相同」只能证明同后端内确定；把指纹写成测试
/// 常量之后，wasm-gc / js / native 任意后端算出的值都必须是同一个，
/// 这才叫跨后端确定性。顶点与索引的顺序本身是确定性的产物，所以指纹
/// 也顺带覆盖了遍历顺序。
pub fn Mesh::hash(self : Mesh) -> UInt64 {
  let mut h : UInt64 = 0xcbf29ce484222325UL
  for p in self.positions {
    h = fnv1a(h, p.x.reinterpret_as_uint64())
    h = fnv1a(h, p.y.reinterpret_as_uint64())
    h = fnv1a(h, p.z.reinterpret_as_uint64())
  }
  for i in self.indices {
    h = fnv1a(h, i.to_uint64())
  }
  h
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
