///|
/// 网格化选项。
pub(all) struct MeshOptions {
  /// 最长轴上的采样分段数（不是每轴都切这么多段）。
  resolution : Int32
  /// 是否把交点沿梯度投到零等值面。开着头顶点更贴近曲面；
  /// 关掉可用于比较「阶梯误差」与「投影残差」。
  project : Bool
  /// Newton 迭代次数。2 次足够把残差压到体素尺度的三阶。
  iterations : Int32
}

///|
pub fn MeshOptions::new(resolution : Int32) -> MeshOptions {
  { resolution, project: true, iterations: 2, }
}

///|
/// 立方体沿主对角线 `(0,0,0)-(1,1,1)` 拆成 6 个四面体。
///
/// 对角方式固定成这一种：换一种拆分，同一个 SDF 在同一个分辨率下会得到
/// 不同的三角数，体积也就不可比。这条写进 ARCHITECTURE。
let tet_table : Array[Array[Int32]] = [
  [0, 1, 3, 7],
  [0, 1, 5, 7],
  [0, 2, 3, 7],
  [0, 2, 6, 7],
  [0, 4, 5, 7],
  [0, 4, 6, 7],
]

///|
fn ceil_int(v : Double) -> Int32 {
  let i = v.to_int()
  if i.to_double() < v {
    i + 1
  } else {
    i
  }
}

///|
fn max_component(v : Vec3) -> Double {
  let a = if v.x > v.y { v.x } else { v.y }
  if a > v.z {
    a
  } else {
    v.z
  }
}

///|
/// 网格构建期的可变状态。没有用闭包，是因为闭包捕获可变数组在
/// 不同后端上的行为不该成为几何结果的一部分——显式传 `self` 更稳。
priv struct Builder {
  sdf : Sdf
  positions : Array[Vec3]
  /// 每个顶点处的外法线（SDF 梯度）。逐面定绕向时用它当参考：
  /// 梯度就在面上，比「拿某个格点当外部参考点」稳——格点可能恰好
  /// 贴着等值面，参考方向会被浮点噪声决定。
  normals : Array[Vec3]
  seen : @hashmap.HashMap[UInt64, Int32]
  project : Bool
  iterations : Int32
  /// 格点总数，用于把「格点索引对」编码成唯一键。
  slots : UInt64
}

///|
fn Builder::new(
  sdf : Sdf,
  project : Bool,
  iterations : Int32,
  slots : UInt64,
) -> Builder {
  {
    sdf,
    positions: [],
    normals: [],
    seen: @hashmap.HashMap([], capacity=1024),
    project,
    iterations,
    slots,
  }
}

///|
/// 取（或新建）一条四面体边上的交点。
///
/// 键是两个**格点索引**的 `min/max`：同一条几何边无论从哪个四面体、
/// 哪个方向被访问，算出的键相同，于是天然焊接，不需要 eps 量化。
/// 位置也统一按 `min -> max` 方向插值，避免「同一键两个浮点值」。
fn Builder::edge_vertex(
  self : Builder,
  i : Int64,
  j : Int64,
  pi : Vec3,
  fi : Double,
  pj : Vec3,
  fj : Double,
) -> Int32 {
  let a = if i < j { i } else { j }
  let b = if i < j { j } else { i }
  let key = a.reinterpret_as_uint64() * self.slots + b.reinterpret_as_uint64()
  match self.seen.get(key) {
    Some(idx) => idx
    None => {
      let pa = if i < j { pi } else { pj }
      let fa = if i < j { fi } else { fj }
      let pb = if i < j { pj } else { pi }
      let fb = if i < j { fj } else { fi }
      let mut t = if fa == fb { 0.5 } else { fa / (fa - fb) }
      // 端点恰好落在零等值面时 t 会贴到 0 或 1，产生零面积三角形。
      // 夹一个相对体素尺度的极小量，既不改变插值方向也不会漏面。
      if t < 1.0e-6 {
        t = 1.0e-6
      }
      if t > 1.0 - 1.0e-6 {
        t = 1.0 - 1.0e-6
      }
      let mut p = pa.add(pb.sub(pa).mul(t))
      if self.project {
        let mut k = 0
        while k < self.iterations {
          let d = self.sdf.eval(p)
          let g = self.sdf.gradient(p)
          let gl = g.length()
          if gl <= 1.0e-12 {
            k = self.iterations
          } else {
            // 沿单位梯度走 `d`：对精确 SDF 一步到位，对 BOX 棱边附近
            // |∇f| 偏离 1 的区域也不会过冲（牛顿步会）。
            p = p.sub(g.div(gl).mul(d))
            k = k + 1
          }
        }
      }
      let idx = self.positions.length()
      self.positions.push(p)
      self.normals.push(self.sdf.gradient(p))
      self.seen.set(key, idx)
      idx
    }
  }
}

///|
/// 追加一个三角形，并按「法线背离内部」统一绕向。
///
/// 不能只靠最后的体积符号整体翻转：同一份网格里若一部分面朝外、
/// 一部分朝内，散度体积会互相抵消，看起来只是「体积偏小」而不报错。
/// 这里用「参考点 `ref` 是已知外部点」逐面定绕向：法线应指向 `ref` 一侧。
fn Builder::emit(
  self : Builder,
  out : Array[Int32],
  a : Int32,
  b : Int32,
  c : Int32,
) -> Unit {
  let pa = self.positions[a]
  let pb = self.positions[b]
  let pc = self.positions[c]
  let n = pb.sub(pa).cross(pc.sub(pa))
  let outward = self.normals[a].add(self.normals[b]).add(self.normals[c])
  if n.dot(outward) < 0.0 {
    out.push(a)
    out.push(c)
    out.push(b)
  } else {
    out.push(a)
    out.push(b)
    out.push(c)
  }
}

///|
/// 从 SDF 生成水密三角网格。
///
/// 采样在包围盒内做规则体素网格，每个体素拆 6 个四面体，按四面体顶点的
/// 符号取出 0/1/2 个三角形，交点在格点边上插值、按边键焊接。
/// 输出朝向由散度体积统一校正：体积为负就整体翻转。
pub fn mesh(sdf : Sdf, bounds : Aabb, opts : MeshOptions) -> Mesh {
  let res = if opts.resolution < 2 {
    2
  } else if opts.resolution > 512 {
    512
  } else {
    opts.resolution
  }
  let size = bounds.size()
  let longest = max_component(size)
  if longest <= 0.0 {
    return Mesh::empty()
  }
  let h = longest / res.to_double()
  let nx = if ceil_int(size.x / h) < 1 { 1 } else { ceil_int(size.x / h) }
  let ny = if ceil_int(size.y / h) < 1 { 1 } else { ceil_int(size.y / h) }
  let nz = if ceil_int(size.z / h) < 1 { 1 } else { ceil_int(size.z / h) }
  let nx1 = nx + 1
  let ny1 = ny + 1
  let nz1 = nz + 1
  let slots = (nx1 * ny1 * nz1).to_uint64()
  let field : Array[Double] = []
  let mut zi = 0
  while zi < nz1 {
    let mut yi = 0
    while yi < ny1 {
      let mut xi = 0
      while xi < nx1 {
        let p = Vec3::new(
          bounds.min.x + xi.to_double() * h,
          bounds.min.y + yi.to_double() * h,
          bounds.min.z + zi.to_double() * h,
        )
        field.push(sdf.eval(p))
        xi = xi + 1
      }
      yi = yi + 1
    }
    zi = zi + 1
  }
  let g = Array::make(8, 0L)
  let fv = Array::make(8, 0.0)
  let pv = Array::make(8, Vec3::zero())
  let ins = Array::make(4, 0)
  let outs = Array::make(4, 0)
  let b = Builder::new(sdf, opts.project, opts.iterations, slots)
  let tris : Array[Int32] = []
  let mut z = 0
  while z < nz {
    let mut y = 0
    while y < ny {
      let mut x = 0
      while x < nx {
        // 8 个角点：bit0 = x, bit1 = y, bit2 = z
        let mut c = 0
        while c < 8 {
          let cx = x + (c & 1)
          let cy = y + ((c >> 1) & 1)
          let cz = z + ((c >> 2) & 1)
          let slot = cx + nx1 * (cy + ny1 * cz)
          g[c] = slot.to_int64()
          fv[c] = field[slot]
          pv[c] = Vec3::new(
            bounds.min.x + cx.to_double() * h,
            bounds.min.y + cy.to_double() * h,
            bounds.min.z + cz.to_double() * h,
          )
          c = c + 1
        }
        let mut t = 0
        while t < 6 {
          let tet = tet_table[t]
          let mut ni = 0
          let mut no = 0
          let mut k = 0
          while k < 4 {
            let slot = tet[k]
            if fv[slot] < 0.0 {
              ins[ni] = slot
              ni = ni + 1
            } else {
              outs[no] = slot
              no = no + 1
            }
            k = k + 1
          }
          if ni == 1 {
            let a = ins[0]
            let v0 = b.edge_vertex(
              g[a],
              g[outs[0]],
              pv[a],
              fv[a],
              pv[outs[0]],
              fv[outs[0]],
            )
            let v1 = b.edge_vertex(
              g[a],
              g[outs[1]],
              pv[a],
              fv[a],
              pv[outs[1]],
              fv[outs[1]],
            )
            let v2 = b.edge_vertex(
              g[a],
              g[outs[2]],
              pv[a],
              fv[a],
              pv[outs[2]],
              fv[outs[2]],
            )
            b.emit(tris, v0, v1, v2)
          } else if ni == 3 {
            let o = outs[0]
            let v0 = b.edge_vertex(
              g[o],
              g[ins[0]],
              pv[o],
              fv[o],
              pv[ins[0]],
              fv[ins[0]],
            )
            let v1 = b.edge_vertex(
              g[o],
              g[ins[1]],
              pv[o],
              fv[o],
              pv[ins[1]],
              fv[ins[1]],
            )
            let v2 = b.edge_vertex(
              g[o],
              g[ins[2]],
              pv[o],
              fv[o],
              pv[ins[2]],
              fv[ins[2]],
            )
            b.emit(tris, v0, v1, v2)
          } else if ni == 2 {
            let p = ins[0]
            let q = ins[1]
            let a = outs[0]
            let d = outs[1]
            let v0 = b.edge_vertex(g[p], g[a], pv[p], fv[p], pv[a], fv[a])
            let v1 = b.edge_vertex(g[p], g[d], pv[p], fv[p], pv[d], fv[d])
            let v2 = b.edge_vertex(g[q], g[d], pv[q], fv[q], pv[d], fv[d])
            let v3 = b.edge_vertex(g[q], g[a], pv[q], fv[q], pv[a], fv[a])
            b.emit(tris, v0, v1, v2)
            b.emit(tris, v0, v2, v3)
          }
          t = t + 1
        }
        x = x + 1
      }
      y = y + 1
    }
    z = z + 1
  }
  let out = Mesh::new(b.positions, tris)
  if out.is_empty() {
    return out
  }
  if out.volume() < 0.0 {
    out.flipped()
  } else {
    out
  }
}
