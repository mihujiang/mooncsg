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
/// 一次排序同时数出「唯一边数」与「开口边数」。
///
/// `is_watertight` / `open_edges` / `edge_count` / `euler` / `genus` 以前各自
/// 排一次 `3F` 个 `Int64`，一次报告要好几次排序；合并成一个入口之后，
/// 拓扑查询只排一次。
fn Mesh::edge_tally(self : Mesh) -> (Int32, Int32) {
  let keys = self.edge_keys()
  let mut edges = 0
  let mut open = 0
  let mut i = 0
  while i < keys.length() {
    let mut j = i + 1
    while j < keys.length() && keys[j] == keys[i] {
      j = j + 1
    }
    edges = edges + 1
    if j - i != 2 {
      open = open + 1
    }
    i = j
  }
  (edges, open)
}

///|
/// 水密：每条无向边恰好被 2 个三角形共享。
pub fn Mesh::is_watertight(self : Mesh) -> Bool {
  let (_, open) = self.edge_tally()
  open == 0
}

///|
/// 开口边数：只被 1 个（或 3 个以上）三角形共享的边。
///
/// `is_watertight()` 只回答「是否全闭合」，这里回答「开口有多大」。用在
/// `--clip` 这种故意裁剪的场景：裁剪出来的网格不该被当成可打印实体，但
/// 开口的数量要说得出来，而不是只给一个 false。
pub fn Mesh::open_edges(self : Mesh) -> Int32 {
  let (_, open) = self.edge_tally()
  open
}

///|
fn uf_find(parent : Array[Int32], x : Int32) -> Int32 {
  let mut r = x
  while parent[r] != r {
    parent[r] = parent[parent[r]]
    r = parent[r]
  }
  r
}

///|
/// 按秩合并（这里只按「第一次出现」定根就够了）：合并成功才给顶点 `v`
/// 记一次「星形被连起来」。
fn uf_union(
  parent : Array[Int32],
  merges : Array[Int32],
  a : Int32,
  b : Int32,
  v : Int32,
) -> Unit {
  let ra = uf_find(parent, a)
  let rb = uf_find(parent, b)
  if ra != rb {
    parent[ra] = rb
    merges[v] = merges[v] + 1
  }
}

///|
/// 面 `f` 中顶点 `v` 的「角」编号 `3 * f + k`。调用者保证 `v` 是该面的顶点。
fn corner_of(indices : Array[Int32], f : Int32, v : Int32) -> Int32 {
  let b = f * 3
  if indices[b] == v {
    b
  } else if indices[b + 1] == v {
    b + 1
  } else {
    b + 2
  }
}

///|
/// 无向边编码成 `min * V + max`，与 `edge_keys()` 同一套键。
fn edge_key(a : Int32, b : Int32, nv : Int64) -> Int64 {
  if a < b {
    a.to_int64() * nv + b.to_int64()
  } else {
    b.to_int64() * nv + a.to_int64()
  }
}

///|
/// 处理一条边：第一次见到时记下所属面并累加两端度数；第二次见到时把两个面
/// 在各自端点的星形里连起来（两条边在同一端点处相邻）；第三次见到说明这条边
/// 被 3 个以上面共享，直接判否。
fn link_edge(
  parent : Array[Int32],
  merges : Array[Int32],
  deg : Array[Int32],
  indices : Array[Int32],
  first : @hashmap.HashMap[Int64, Int32],
  key : Int64,
  t : Int32,
  u : Int32,
  w : Int32,
) -> Bool {
  match first.get(key) {
    Some(g) =>
      if g < 0 {
        false
      } else {
        // 同一端点的两个角用边 `(v, w)` 或 `(v, u)` 相连；并查集只在同顶点的
        // 角之间合并，所以 `parent` 的连通块天然按顶点分组。
        uf_union(
          parent,
          merges,
          corner_of(indices, g, u),
          corner_of(indices, t, u),
          u,
        )
        uf_union(
          parent,
          merges,
          corner_of(indices, g, w),
          corner_of(indices, t, w),
          w,
        )
        first.set(key, -(g + 1))
        true
      }
    None => {
      first.set(key, t)
      deg[u] = deg[u] + 1
      deg[w] = deg[w] + 1
      true
    }
  }
}

///|
/// 闭合 2-流形：每条无向边恰好 2 个面，且每个顶点的星形是**一个**环。
///
/// 只用 `faces(v) == deg(v)` 不够。两瓣实体只在一个顶点相触时（两个四面体共用
/// 一个顶点、STL 导入按坐标焊接后把相切的两瓣焊到同一点），那个顶点的星形是
/// 两个环，各环的 `faces` 与 `deg` 仍然相等，度数比下来照样通过。要看星形是
/// 一个环还是两个环，只能真去连：这里把每个顶点的角（面 + 顶点）用并查集按
/// 「共享一条过该顶点的边」连起来，连通块数 = 面数 - 成功合并次数，闭合流形
/// 点应恰好剩下 1 个块。
///
/// 边被 3 个以上面共享时直接返回 false，所以这个函数**蕴含** `is_watertight()`；
/// 反过来不成立（两瓣在一点相触的网格是水密的，但不是流形）。孤立顶点（不参与
/// 任何面）不算缺陷，跳过。
///
/// 代价：一次哈希建表 + 一次并查集（`α` 近似常数）；`3F` 个角各存一份父指针，
/// 100 万三角量级要多出几十 MB 临时内存、秒级时间。比 `is_watertight()` 贵一档。
pub fn Mesh::is_manifold(self : Mesh) -> Bool {
  let f_count = self.triangle_count()
  if f_count == 0 {
    return true
  }
  let n = self.vertex_count()
  if self.indices.length() != f_count * 3 {
    return false
  }
  let nc = f_count * 3
  let nv = n.to_int64()
  let parent : Array[Int32] = Array::make(nc, 0)
  let mut c = 0
  while c < nc {
    parent[c] = c
    c = c + 1
  }
  let merges : Array[Int32] = Array::make(n, 0)
  let deg : Array[Int32] = Array::make(n, 0)
  let faces : Array[Int32] = Array::make(n, 0)
  let first : @hashmap.HashMap[Int64, Int32] = @hashmap.HashMap([], capacity=nc)
  let mut t = 0
  while t < f_count {
    let ia = self.indices[t * 3]
    let ib = self.indices[t * 3 + 1]
    let ic = self.indices[t * 3 + 2]
    faces[ia] = faces[ia] + 1
    faces[ib] = faces[ib] + 1
    faces[ic] = faces[ic] + 1
    if !link_edge(
        parent,
        merges,
        deg,
        self.indices,
        first,
        edge_key(ia, ib, nv),
        t,
        ia,
        ib,
      ) {
      return false
    }
    if !link_edge(
        parent,
        merges,
        deg,
        self.indices,
        first,
        edge_key(ib, ic, nv),
        t,
        ib,
        ic,
      ) {
      return false
    }
    if !link_edge(
        parent,
        merges,
        deg,
        self.indices,
        first,
        edge_key(ic, ia, nv),
        t,
        ic,
        ia,
      ) {
      return false
    }
    t = t + 1
  }
  let mut v = 0
  while v < n {
    if faces[v] > 0 {
      // 星形的连通块数 = 面数 - 成功合并次数。闭合流形点恰好为 1。
      if deg[v] != faces[v] || faces[v] - merges[v] != 1 {
        return false
      }
    }
    v = v + 1
  }
  true
}

///|
/// 唯一边数。
pub fn Mesh::edge_count(self : Mesh) -> Int32 {
  let (edges, _) = self.edge_tally()
  edges
}

///|
/// 欧拉示性数 `V - E + F`。单个闭合曲面上等于 `2 - 2g`；`k` 个不相交的
/// 闭合壳则是 `2k - 2Σgᵢ`（示性数对壳可加）。
pub fn Mesh::euler(self : Mesh) -> Int32 {
  let (edges, _) = self.edge_tally()
  self.vertex_count() - edges + self.triangle_count()
}

///|
/// 亏格 `g = (2 - χ) / 2`，**只对单个闭合壳**有意义。
///
/// 不闭合、或壳数不为 1 时返回 `-1`，意思是「这个数为不了」，不区分具体
/// 原因。这里必须真的数壳：只看 `χ` 是分不出来的——两个环面（各 χ = 0）
/// 合起来 χ 也是 0，会被算成「单壳亏格 1」；球 + 环面 χ = 2，会被算成
/// 「单壳亏格 0」。要逐壳亏格就 `shells()` 之后对每个壳单独问。
pub fn Mesh::genus(self : Mesh) -> Int32 {
  let (edges, open) = self.edge_tally()
  if open > 0 {
    return -1
  }
  if self.shell_count() != 1 {
    return -1
  }
  let chi = self.vertex_count() - edges + self.triangle_count()
  if chi % 2 != 0 || chi > 2 {
    return -1
  }
  (2 - chi) / 2
}

///|
/// 每个三角形所属的连通壳编号（`0 .. shell_count-1`，按三角形首次出现的
/// 顺序编号，因此同输入逐次可复现）。
///
/// 连通判据是**共享一条无向边**，不是共享顶点：两瓣实体只在一个顶点相触时
/// 会被拆成两个壳，而不是并成一个——这与 `is_manifold()` 的顶点判据互补。
fn Mesh::face_components(self : Mesh) -> Array[Int32] {
  let f = self.triangle_count()
  let ids : Array[Int32] = Array::make(f, -1)
  if f == 0 {
    return ids
  }
  let parent : Array[Int32] = Array::make(f, 0)
  let mut i = 0
  while i < f {
    parent[i] = i
    i = i + 1
  }
  let nv = self.vertex_count().to_int64()
  let seen : @hashmap.HashMap[Int64, Int32] = @hashmap.HashMap(
    [],
    capacity=f * 2 + 8,
  )
  let mut t = 0
  while t < f {
    let a = self.indices[t * 3]
    let b = self.indices[t * 3 + 1]
    let c = self.indices[t * 3 + 2]
    link_face(parent, seen, edge_key(a, b, nv), t)
    link_face(parent, seen, edge_key(b, c, nv), t)
    link_face(parent, seen, edge_key(c, a, nv), t)
    t = t + 1
  }
  let label : @hashmap.HashMap[Int32, Int32] = @hashmap.HashMap([], capacity=f)
  let mut count = 0
  let mut k = 0
  while k < f {
    let r = uf_find(parent, k)
    match label.get(r) {
      Some(id) => ids[k] = id
      None => {
        label.set(r, count)
        ids[k] = count
        count = count + 1
      }
    }
    k = k + 1
  }
  ids
}

///|
fn link_face(
  parent : Array[Int32],
  seen : @hashmap.HashMap[Int64, Int32],
  key : Int64,
  t : Int32,
) -> Unit {
  match seen.get(key) {
    Some(g) => {
      let ra = uf_find(parent, g)
      let rb = uf_find(parent, t)
      if ra != rb {
        parent[ra] = rb
      }
    }
    None => seen.set(key, t)
  }
}

///|
/// 连通壳数。空网格为 0；多实体、或薄壁漏采把内腔也当成了实体时 `> 1`。
pub fn Mesh::shell_count(self : Mesh) -> Int32 {
  let ids = self.face_components()
  let mut count = 0
  for id in ids {
    if id >= count {
      count = id + 1
    }
  }
  count
}

///|
/// 拆成互不连通的壳，每壳是一个独立网格（顶点重排、索引重编）。
///
/// 顺序按「该壳里第一个三角形的原始下标」升序，所以同输入两次拆分结果逐位
/// 相同。拆完之后 `genus()` 才逐壳有意义——整体 `genus()` 在多壳时给 -1。
pub fn Mesh::shells(self : Mesh) -> Array[Mesh] {
  let ids = self.face_components()
  let f = self.triangle_count()
  let mut count = 0
  for id in ids {
    if id >= count {
      count = id + 1
    }
  }
  let out : Array[Mesh] = []
  let nv = self.vertex_count()
  let mut s = 0
  while s < count {
    let remap : Array[Int32] = Array::make(nv, -1)
    let positions : Array[Vec3] = []
    let indices : Array[Int32] = []
    let mut t = 0
    while t < f {
      if ids[t] == s {
        let mut j = 0
        while j < 3 {
          let old = self.indices[t * 3 + j]
          let mut idx = remap[old]
          if idx < 0 {
            idx = positions.length()
            remap[old] = idx
            positions.push(self.positions[old])
          }
          indices.push(idx)
          j = j + 1
        }
      }
      t = t + 1
    }
    if indices.length() > 0 {
      out.push(Mesh::new(positions, indices))
    }
    s = s + 1
  }
  out
}

///|
/// 体积最大的壳（按 `|volume|` 比，容忍朝向反了的情况）。空网格返回空网格。
///
/// 这是工程上最常用的一步：3D 打印里浮空的碎屑要么删掉、要么单独检查，
/// 不能和主体混在同一个文件里。
pub fn Mesh::largest_shell(self : Mesh) -> Mesh {
  let parts = self.shells()
  if parts.length() == 0 {
    return Mesh::empty()
  }
  let mut best = parts[0]
  let mut best_v = best.volume().abs()
  let mut i = 1
  while i < parts.length() {
    let v = parts[i].volume().abs()
    if v > best_v {
      best = parts[i]
      best_v = v
    }
    i = i + 1
  }
  best
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

///|
/// 网格体检报告：一次算完拓扑与几何指标，`warnings` 放「需要人看一眼」的项。
///
/// 单独调 `is_watertight()` / `open_edges()` / `euler()` / `genus()` /
/// `shell_count()` 会各自遍历一遍边表（每次 `O(F log F)` 排序），体检要的
/// 是所有指标，所以给一个合并入口。`genus` 只在「闭合且单壳」时有意义，
/// 否则为 `-1`（多壳时整体亏格没有定义）。
pub(all) struct MeshAudit {
  vertices : Int32
  triangles : Int32
  edges : Int32
  open_edges : Int32
  shells : Int32
  euler : Int32
  genus : Int32
  watertight : Bool
  manifold : Bool
  volume : Double
  area : Double
  hash : UInt64
  bounds : Aabb
  warnings : Array[String]
}

///|
/// JSON 数字：非有限值写 `null`，免得产出非法 JSON。
fn json_num(v : Double) -> String {
  if v == v && v.abs() <= 1.0e308 {
    "\{v}"
  } else {
    "null"
  }
}

///|
/// 一次体检。`warnings` 里的判断都来自实测出的失败模式，不是泛泛的提醒：
///
/// - 开口：某条边的相邻面数不是 2（裁剪、域没包住实体、场有奇点）；
/// - 非流形顶点：两瓣实体只在一个顶点相触（`is_watertight` 抓不到）；
/// - 多壳：互不连通的壳多于 1 个。薄壁（壁厚小于 1~2 个体素）时采样会漏掉
///   壁内的负区，把内腔的表面也当成实体边界，体积因此**偏大**而不是偏小
///   （实测壁厚 0.2、体素 0.656 时体积是解析值的 29 倍）；
/// - 体积非正：整体朝向反了。
pub fn Mesh::audit(self : Mesh) -> MeshAudit {
  let f = self.triangle_count()
  let v = self.vertex_count()
  let (edges, open) = self.edge_tally()
  let shells = self.shell_count()
  let euler = v - edges + f
  let watertight = open == 0
  let manifold = self.is_manifold()
  let genus = if watertight && shells == 1 && euler % 2 == 0 && euler <= 2 {
    (2 - euler) / 2
  } else {
    -1
  }
  let volume = self.volume()
  let warnings : Array[String] = []
  if f > 0 {
    if !watertight {
      warnings.push("开口：\{open} 条边的相邻面数不是 2")
    }
    if watertight && !manifold {
      warnings.push("非流形顶点：有两瓣只在一个顶点相触")
    }
    if shells > 1 {
      warnings.push(
        "多壳：\{shells} 个互不连通的壳。内腔与多实体都会这样；若壁厚小于约 1 个体素，内腔表面可能被当成实体边界，体积会偏大（实测壁厚 0.2、体素 0.66 时是解析值的 29 倍）",
      )
    }
    if volume <= 0.0 {
      warnings.push("体积非正：网格朝向可能整体反了")
    }
  }
  {
    vertices: v,
    triangles: f,
    edges,
    open_edges: open,
    shells,
    euler,
    genus,
    watertight,
    manifold,
    volume,
    area: self.area(),
    hash: self.hash(),
    bounds: self.bounds(),
    warnings,
  }
}

///|
/// 单行可解析的 JSON。`warnings` 是库自己生成的固定文案（不含引号与反斜杠），
/// 所以直接拼接，不做转义。
pub fn MeshAudit::to_json(self : MeshAudit) -> String {
  let b = self.bounds
  let mut out = "{\n"
  out = out + "  \"vertices\": \{self.vertices},\n"
  out = out + "  \"triangles\": \{self.triangles},\n"
  out = out + "  \"edges\": \{self.edges},\n"
  out = out + "  \"open_edges\": \{self.open_edges},\n"
  out = out + "  \"shells\": \{self.shells},\n"
  out = out + "  \"euler\": \{self.euler},\n"
  out = out + "  \"genus\": \{self.genus},\n"
  out = out + "  \"watertight\": \{self.watertight},\n"
  out = out + "  \"manifold\": \{self.manifold},\n"
  out = out + "  \"volume\": \{json_num(self.volume)},\n"
  out = out + "  \"area\": \{json_num(self.area)},\n"
  out = out + "  \"hash\": \{self.hash},\n"
  out = out +
    "  \"bounds\": {\"min\": [\{json_num(b.min.x)}, \{json_num(b.min.y)}, \{json_num(b.min.z)}], \"max\": [\{json_num(b.max.x)}, \{json_num(b.max.y)}, \{json_num(b.max.z)}]},\n"
  out = out + "  \"warnings\": ["
  let mut i = 0
  while i < self.warnings.length() {
    if i > 0 {
      out = out + ", "
    }
    out = out + "\"" + self.warnings[i] + "\""
    i = i + 1
  }
  out = out + "]\n}\n"
  out
}
