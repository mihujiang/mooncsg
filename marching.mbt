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
/// 场数组的总格点上限：16.7M 个 `Double` ≈ 134 MB，是 wasm32 下还能接受的
/// 最坏情况。单轴上限 512 挡不住「三个轴都大」。
const MAX_GRID_SLOTS : Int32 = 16777216

///|
/// 某个轴上的格点数，至少 1。
fn grid_count(extent : Double, h : Double) -> Int32 {
  let n = ceil_int(extent / h)
  if n < 1 {
    1
  } else {
    n
  }
}

///|
/// 格点规划：`resolution` 先夹到 `[2, 512]`，再按总格点 `MAX_GRID_SLOTS`
/// 二次收紧（1.25 倍一步放大步长，`h` 单调增，不会死循环）。
///
/// 512 的立方包围盒原本是 513³ ≈ 1.35 亿个格点（场数组就是 1 GB 级），
/// 会被自动降到约 253³，代价是细分变粗，而不是 OOM。
///
/// 返回 `(h, nx, ny, nz)`；`mesh` 与 `grid_shape` 共用这一份，免得
/// 「请求 256、实际只有 205」这种差异只活在注释里。
fn plan_grid(size : Vec3, resolution : Int32) -> (Double, Int32, Int32, Int32) {
  let res = if resolution < 2 {
    2
  } else if resolution > 512 {
    512
  } else {
    resolution
  }
  let mut h = max_component(size) / res.to_double()
  let mut nx = grid_count(size.x, h)
  let mut ny = grid_count(size.y, h)
  let mut nz = grid_count(size.z, h)
  while (nx + 1) * (ny + 1) * (nz + 1) > MAX_GRID_SLOTS {
    h = h * 1.25
    nx = grid_count(size.x, h)
    ny = grid_count(size.y, h)
    nz = grid_count(size.z, h)
  }
  (h, nx, ny, nz)
}

///|
/// 请求 `resolution` 后**实际**会用的格点数 `(nx, ny, nz)`。
///
/// 只跟包围盒尺寸和 `resolution` 有关。想报告「真实的采样密度」时用它，
/// 而不是回显请求值——超过 `MAX_GRID_SLOTS` 时两者不一样。
pub fn grid_shape(bounds : Aabb, resolution : Int32) -> (Int32, Int32, Int32) {
  let size = bounds.size()
  if max_component(size) <= 0.0 {
    return (0, 0, 0)
  }
  let (_, nx, ny, nz) = plan_grid(size, resolution)
  (nx, ny, nz)
}

///|
/// 用已采好的场值建面：每个体素拆 6 个四面体，按四面体的顶点符号取出
/// 0/1/2 个三角形，交点在格点边上插值、按**格点索引对**焊接，逐面按
/// 梯度定绕向，最后用散度体积兜底整体翻转。
///
/// 这里不校验采样域与实体的关系——那一步在 `check_field` 里。要「保证
/// 闭合」的调用方请走 `mesh_checked`。
fn assemble_mesh(
  sdf : Sdf,
  bounds : Aabb,
  h : Double,
  nx : Int32,
  ny : Int32,
  nz : Int32,
  field : Array[Double],
  opts : MeshOptions,
) -> Mesh {
  let nx1 = nx + 1
  let ny1 = ny + 1
  let nz1 = nz + 1
  let slots = (nx1 * ny1 * nz1).to_uint64()
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

///|
/// 网格化的拒绝原因。
///
/// `mesh_checked` 只在「采样域严格包住实体、场值处处有限」时返回网格，
/// 其余情况明确拒绝。原因很直接：marching tetrahedra 只能在采样域内部
/// 把曲面闭合起来，曲面一旦碰到采样域边界，那里的面必然被截断成开口。
/// 那种网格体积偏小、切片软件会当成「有漏的实体」。宁可报错，也不返回
/// 一个看起来能用、实际不可打印的网格。
pub(all) enum MeshError {
  /// 没有有限包围盒：半空间，或含半空间的组合（`bounds()` 返回 `None`）。
  Unbounded
  /// 采样域退化：某个轴长度 <= 0，或边界坐标非有限。
  DegenerateBounds
  /// 采样到 NaN / Inf 场值，附带首次出现的位置。
  NonFiniteField(Vec3)
  /// 采样域边界上出现 `f <= 0`：实体穿过或贴住采样域，网格必然开口。
  /// 附带该点与它的场值。
  SurfaceClipped(Vec3, Double)
  /// 采样域里一个内部点都没有（`f > 0` 处处成立），出来是空网格。
  NoSurface
}

///|
/// 拒绝原因的可读描述。CLI、测试、文档共用这一份，免得三处口径不一致。
pub fn MeshError::describe(self : MeshError) -> String {
  match self {
    Unbounded => "没有有限包围盒（半空间不能直接网格化）"
    DegenerateBounds =>
      "采样域退化：某个轴长度为 0 或坐标非有限"
    NonFiniteField(p) =>
      "场值非有限（NaN/Inf），首次出现在 (\{p.x}, \{p.y}, \{p.z})"
    SurfaceClipped(p, f) =>
      "采样域被实体穿过：边界点 (\{p.x}, \{p.y}, \{p.z}) 的场值是 \{f}，网格会开口"
    NoSurface => "采样域内没有曲面（f > 0 处处成立）"
  }
}

///|
/// 有限性判断。`v == v` 抓 NaN（NaN 与任何值都不相等），上界抓 Inf。
/// 这个 core 版本没有 `Double::is_nan` / `is_inf`。
fn f64_finite(v : Double) -> Bool {
  v == v && v.abs() <= 1.0e308
}

///|
fn vec3_finite(v : Vec3) -> Bool {
  f64_finite(v.x) && f64_finite(v.y) && f64_finite(v.z)
}

///|
/// 规则格点采样，`slot = x + nx1 * (y + ny1 * z)`，与 `assemble_mesh` 的
/// 取法一致。
fn sample_field(
  sdf : Sdf,
  bounds : Aabb,
  h : Double,
  nx : Int32,
  ny : Int32,
  nz : Int32,
) -> Array[Double] {
  let nx1 = nx + 1
  let ny1 = ny + 1
  let nz1 = nz + 1
  let field : Array[Double] = []
  let mut zi = 0
  while zi < nz1 {
    let mut yi = 0
    while yi < ny1 {
      let mut xi = 0
      while xi < nx1 {
        field.push(
          sdf.eval(
            Vec3::new(
              bounds.min.x + xi.to_double() * h,
              bounds.min.y + yi.to_double() * h,
              bounds.min.z + zi.to_double() * h,
            ),
          ),
        )
        xi = xi + 1
      }
      yi = yi + 1
    }
    zi = zi + 1
  }
  field
}

///|
/// 检查采样结果能否保证「闭合、可切片」：
///
/// 1. 每个格点的场值必须有限——NaN/Inf 会被插值放大成垃圾三角形；
/// 2. 采样域 6 个面上的每个格点必须 `f > 0`。
///
/// 第 2 条不是保守估计，而是这一实现下的充要条件：三角形只在相邻四面体
/// 之间按**格点索引对**配对焊接，曲面上的每个顶点都落在一条两端格点异号
/// 的边上。若某条边的两端都贴着采样域边界，曲面就从边界穿出，那个顶点
/// 找不到对侧三角形，边界处留下开口。反之边界全正意味着曲面整块在内部，
/// 每个顶点都能在域内找到对侧三角形，于是「每条边恰好 2 面」是被构造
/// 保证的，不是概率性的。
fn check_field(
  bounds : Aabb,
  h : Double,
  nx : Int32,
  ny : Int32,
  nz : Int32,
  field : Array[Double],
) -> MeshError? {
  let nx1 = nx + 1
  let ny1 = ny + 1
  let nz1 = nz + 1
  let mut zi = 0
  while zi < nz1 {
    let mut yi = 0
    while yi < ny1 {
      let mut xi = 0
      while xi < nx1 {
        let slot = xi + nx1 * (yi + ny1 * zi)
        let f = field[slot]
        if !f64_finite(f) {
          return Some(
            NonFiniteField(
              Vec3::new(
                bounds.min.x + xi.to_double() * h,
                bounds.min.y + yi.to_double() * h,
                bounds.min.z + zi.to_double() * h,
              ),
            ),
          )
        }
        let on_boundary = xi == 0 ||
          xi == nx ||
          yi == 0 ||
          yi == ny ||
          zi == 0 ||
          zi == nz
        if on_boundary && f <= 0.0 {
          return Some(
            SurfaceClipped(
              Vec3::new(
                bounds.min.x + xi.to_double() * h,
                bounds.min.y + yi.to_double() * h,
                bounds.min.z + zi.to_double() * h,
              ),
              f,
            ),
          )
        }
        xi = xi + 1
      }
      yi = yi + 1
    }
    zi = zi + 1
  }
  None
}

///|
/// 生成三角网格，**不校验**采样域与实体的关系。
///
/// 采样域小于实体、实体贴住域边界、场值含 NaN 时它照样返回网格——那种
/// 网格会开口或含垃圾三角形。只在「前提已经确认成立」时用它（比如故意
/// 要给半空间做裁剪网格）。要保证闭合请用 `mesh_checked`。
///
/// `resolution` 的口径见 `plan_grid`：先夹到 `[2, 512]`，再按总格点收紧。
pub fn mesh_unchecked(sdf : Sdf, bounds : Aabb, opts : MeshOptions) -> Mesh {
  let size = bounds.size()
  if max_component(size) <= 0.0 {
    return Mesh::empty()
  }
  let (h, nx, ny, nz) = plan_grid(size, opts.resolution)
  let field = sample_field(sdf, bounds, h, nx, ny, nz)
  assemble_mesh(sdf, bounds, h, nx, ny, nz, field, opts)
}

///|
/// 带前置检查的网格化：要么返回一块**闭合、可直接切片**的网格，要么返回
/// 拒绝原因，不存在「看起来能用、其实漏面」的第三种结果。
///
/// 通过检查时输出满足：每条无向边恰好被 2 个三角形共享（`is_watertight`），
/// 朝向逐面由梯度决定、以体积符号兜底，空网格不会被当成成功返回。
///
/// 检查覆盖：
///
/// - 采样域必须体积为正、坐标有限（`DegenerateBounds`）；
/// - 场值必须处处有限（`NonFiniteField`）；
/// - 实体必须**严格位于**采样域内部：6 个面上的采样点全部 `f > 0`
///   （`SurfaceClipped`）——半空间、被裁剪的实体、与域面相切的实体都在
///   这里被拒；
/// - 采样域内必须真有曲面（`NoSurface`）。
///
/// 它不保证的（属于采样精度或输入合法性，不是拓扑问题）：
///
/// - 壁厚小于 2 个体素的薄壳：两个格点可能同号，整片壳被漏掉，结果是空
///   网格（`NoSurface`）或体积明显偏小；
/// - `|∇f|` 明显偏离 1 的非精确 SDF：体积与法线有偏差，拓扑仍闭合；
/// - 自交实体（如管半径大于母线半径的环面）：输出闭合但不可打印。
pub fn mesh_checked(
  sdf : Sdf,
  bounds : Aabb,
  opts : MeshOptions,
) -> Result[Mesh, MeshError] {
  if !vec3_finite(bounds.min) || !vec3_finite(bounds.max) {
    return Err(DegenerateBounds)
  }
  let size = bounds.size()
  if size.x <= 0.0 || size.y <= 0.0 || size.z <= 0.0 {
    return Err(DegenerateBounds)
  }
  let (h, nx, ny, nz) = plan_grid(size, opts.resolution)
  let field = sample_field(sdf, bounds, h, nx, ny, nz)
  match check_field(bounds, h, nx, ny, nz, field) {
    Some(e) => Err(e)
    None => {
      let m = assemble_mesh(sdf, bounds, h, nx, ny, nz, field, opts)
      if m.is_empty() {
        Err(NoSurface)
      } else {
        Ok(m)
      }
    }
  }
}

///|
/// `mesh_unchecked` 的旧名字，保留给 0.1.x 的调用方。
///
/// 它**不做**前置检查；要「保证闭合可切片」请用 `mesh_checked`。
pub fn mesh(sdf : Sdf, bounds : Aabb, opts : MeshOptions) -> Mesh {
  mesh_unchecked(sdf, bounds, opts)
}
