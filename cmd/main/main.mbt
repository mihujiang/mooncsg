///|
/// mooncsg 的命令行入口：把「形状 + 布尔」写成一条命令，模型走 stdout、
/// 指标走 stderr，于是 `> part.stl` 得到的是一份干净的文件。
///
/// 这个工具链（0.1.20261021）没有文件系统绑定，所以不提供 `--out`：
/// 重定向比在库里塞一层 FFI 更符合「零 FFI」的定位。`--out` 会在帮助里
/// 说明这一点。

///|
fn code_at(s : String, i : Int32) -> UInt16 {
  match s.get(i) {
    Some(c) => c
    None => 0
  }
}

///|
fn is_digit(c : UInt16) -> Bool {
  c >= 48 && c <= 57
}

///|
fn starts_with_dash(s : String) -> Bool {
  code_at(s, 0) == 45
}

///|
fn pow10(e : Int32) -> Double {
  let mut r = 1.0
  let mut i = 0
  let m = if e < 0 { -e } else { e }
  while i < m {
    r = r * 10.0
    i = i + 1
  }
  if e < 0 {
    1.0 / r
  } else {
    r
  }
}

///|
/// core 的这个版本没有 `Int -> Int32` 的转换方法，而 `MeshOptions::new` 收
/// `Int32`；值域只有 2..512，用计数构造比引 FFI 干净。
fn int_to_int32(v : Int32) -> Int32 {
  let mut r : Int32 = 0
  let mut i = 0
  while i < v {
    r = r + 1
    i = i + 1
  }
  r
}

///|
/// 手写十进制解析：core 的这个版本没有 `String -> Double`。
/// 只接受 `[-+]?digits[.digits][eE[+-]digits]`。
fn parse_f64(s : String) -> Double? {
  let n = s.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut sign = 1.0
  if code_at(s, 0) == 45 {
    sign = -1.0
    i = 1
  } else if code_at(s, 0) == 43 {
    i = 1
  }
  let mut mant = 0.0
  let mut digits = 0
  while i < n && is_digit(code_at(s, i)) {
    mant = mant * 10.0 + (code_at(s, i) - 48).to_int().to_double()
    digits = digits + 1
    i = i + 1
  }
  if i < n && code_at(s, i) == 46 {
    i = i + 1
    let mut frac = 0.1
    while i < n && is_digit(code_at(s, i)) {
      mant = mant + (code_at(s, i) - 48).to_int().to_double() * frac
      frac = frac * 0.1
      digits = digits + 1
      i = i + 1
    }
  }
  if digits == 0 {
    return None
  }
  let mut exp = 0
  if i < n && (code_at(s, i) == 101 || code_at(s, i) == 69) {
    i = i + 1
    let mut esign = 1
    if i < n && code_at(s, i) == 45 {
      esign = -1
      i = i + 1
    } else if i < n && code_at(s, i) == 43 {
      i = i + 1
    }
    let mut e = 0
    while i < n && is_digit(code_at(s, i)) {
      e = e * 10 + (code_at(s, i) - 48).to_int()
      i = i + 1
    }
    exp = e * esign
  }
  Some(sign * mant * pow10(exp))
}

///|
fn parse_int(s : String) -> Int32? {
  match parse_f64(s) {
    Some(v) => Some(v.to_int())
    None => None
  }
}

///|
fn substr(s : String, start : Int32, end : Int32) -> String {
  let buf : Array[Char] = []
  let mut i = start
  while i < end {
    match s.get_char(i) {
      Some(c) => buf.push(c)
      None => ()
    }
    i = i + 1
  }
  String::from_array(buf)
}

///|
fn is_value_option(a : String) -> Bool {
  a == "--res" ||
  a == "--format" ||
  a == "--name" ||
  a == "--op" ||
  a == "--k" ||
  a == "--at"
}

///|
/// `--sphere` 与 `sphere` 都接受：操作形状用前者，主形状用后者。
fn shape_name(a : String) -> String {
  if code_at(a, 0) == 45 && code_at(a, 1) == 45 {
    substr(a, 2, a.length())
  } else {
    a
  }
}

///|
fn is_shape(name : String) -> Bool {
  match name {
    "sphere" | "box" | "cyl" | "cylinder" | "cone" | "capsule" | "torus" => true
    _ => false
  }
}

///|
/// 尺寸全部按「全长 / 半径」给：`box 40 30 20` 是 40×30×20，
/// `cyl 5 20` 是半径 5、高 20，`cone 0 5 20` 是顶半径 0、底半径 5、高 20。
fn make_shape(name : String, vals : Array[Double]) -> @mooncsg.Sdf? {
  let n = vals.length()
  match name {
    "sphere" => if n >= 1 { Some(@mooncsg.Sdf::sphere(vals[0])) } else { None }
    "box" =>
      if n >= 3 {
        Some(
          @mooncsg.Sdf::box(
            @mooncsg.Vec3::new(vals[0] * 0.5, vals[1] * 0.5, vals[2] * 0.5),
          ),
        )
      } else if n == 1 {
        Some(@mooncsg.Sdf::box(@mooncsg.Vec3::splat(vals[0] * 0.5)))
      } else {
        None
      }
    "cyl" | "cylinder" =>
      if n >= 2 {
        Some(@mooncsg.Sdf::cylinder(vals[0], vals[1] * 0.5))
      } else {
        None
      }
    "cone" =>
      if n >= 3 {
        Some(@mooncsg.Sdf::cone(vals[0], vals[1], vals[2] * 0.5))
      } else {
        None
      }
    "capsule" =>
      if n >= 2 {
        Some(@mooncsg.Sdf::capsule(vals[0], vals[1] * 0.5))
      } else {
        None
      }
    "torus" =>
      if n >= 2 {
        Some(@mooncsg.Sdf::Torus(@mooncsg.Vec3::zero(), vals[0], vals[1]))
      } else {
        None
      }
    _ => None
  }
}

///|
fn apply_op(
  a : @mooncsg.Sdf,
  b : @mooncsg.Sdf,
  op : String,
  k : Double,
) -> @mooncsg.Sdf {
  match op {
    "union" => a.union(b)
    "inter" | "intersect" => a.intersect(b)
    "smooth" => a.smooth_union(b, k)
    _ => a.subtract(b)
  }
}

///|
fn print_help() -> Unit {
  println("mooncsg — SDF 实体建模内核的命令行入口")
  println("")
  println("用法：")
  println(
    "  moon run cmd/main -- <主形状> [尺寸...] [--<操作形状> 尺寸...] [--op OP]",
  )
  println("")
  println("形状（尺寸是全长或半径）：")
  println("  sphere R              球，半径 R")
  println("  box X Y Z | box S     盒，三边或正方体边长")
  println("  cyl R H               圆柱，半径 R、高 H")
  println(
    "  cone R1 R2 H          圆台，下半径 R1、上半径 R2、高 H",
  )
  println("  capsule R H           胶囊，半径 R、圆心段长 H")
  println("  torus R r             环面，母线半径 R、管半径 r")
  println("")
  println("选项：")
  println(
    "  --op diff|union|inter|smooth   与操作形状的布尔（默认 diff）",
  )
  println("  --k 2.0                        smooth 的过渡带宽度")
  println("  --at x,y,z                     最终结果平移")
  println(
    "  --res 64                       网格分辨率（上限 512，总格点另行收紧）",
  )
  println(
    "  --format stl|obj               输出格式（默认 stl，即 ASCII STL）",
  )
  println("  --name NAME                    模型名，写进 solid/对象行")
  println(
    "  --stats                        只打印三角数、体积、面积、拓扑",
  )
  println("")
  println(
    "输出：模型写 stdout。本工具链没有文件系统绑定，用重定向落盘；",
  )
  println(
    "又因为 `%eprintln` 与 stdout 同流，`--stats` 与模型输出互斥：",
  )
  println("  moon run cmd/main -- box 40 --sphere 26 --op diff > part.stl")
  println("  moon run cmd/main -- cone 0 10 20 --format obj > part.obj")
  println("  moon run cmd/main -- box 40 30 20 --sphere 12 --stats")
}

///|
fn main {
  let args = @env.args()
  let n = args.length()
  let mut res = 64
  let mut format = "stl"
  let mut name = "mooncsg"
  let mut want_stats = false
  let mut op = "diff"
  let mut k = 2.0
  // 主形状与后接的操作形状
  let mut base : @mooncsg.Sdf? = None
  let tools : Array[@mooncsg.Sdf] = []
  let mut offset : @mooncsg.Vec3? = None
  let mut i = 1
  while i < n {
    let a = args[i]
    if a == "--help" || a == "-h" {
      print_help()
      return
    } else if a == "--stats" {
      want_stats = true
      i = i + 1
    } else if is_value_option(a) {
      if i + 1 >= n {
        eprintln("错误：\{a} 需要一个值")
        return
      }
      let v = args[i + 1]
      if a == "--res" {
        match parse_int(v) {
          Some(r) => res = r
          None => {
            eprintln("错误：--res 需要整数，收到 \{v}")
            return
          }
        }
      } else if a == "--format" {
        format = v
      } else if a == "--name" {
        name = v
      } else if a == "--op" {
        op = v
      } else if a == "--k" {
        match parse_f64(v) {
          Some(x) => k = x
          None => {
            eprintln("错误：--k 需要数字，收到 \{v}")
            return
          }
        }
      } else {
        // --at x,y,z
        let parts : Array[String] = []
        let mut start = 0
        let mut j = 0
        while j <= v.length() {
          if j == v.length() || code_at(v, j) == 44 {
            let mut seg = ""
            let mut t = start
            while t < j {
              seg = seg + substr(v, t, t + 1)
              t = t + 1
            }
            parts.push(seg)
            start = j + 1
          }
          j = j + 1
        }
        if parts.length() != 3 {
          eprintln("错误：--at 需要 x,y,z，收到 \{v}")
          return
        }
        let xyz : Array[Double] = []
        for p in parts {
          match parse_f64(p) {
            Some(d) => xyz.push(d)
            None => {
              eprintln("错误：--at 里的 \{p} 不是数字")
              return
            }
          }
        }
        offset = Some(@mooncsg.Vec3::new(xyz[0], xyz[1], xyz[2]))
      }
      i = i + 2
    } else if is_shape(shape_name(a)) {
      let vals : Array[Double] = []
      let mut j = i + 1
      while j < n && !starts_with_dash(args[j]) {
        match parse_f64(args[j]) {
          Some(d) => {
            vals.push(d)
            j = j + 1
          }
          None => break
        }
      }
      match make_shape(shape_name(a), vals) {
        Some(s) =>
          match base {
            Some(_) => tools.push(s)
            None => base = Some(s)
          }
        None => {
          eprintln("错误：\{a} 的尺寸不够，看 --help")
          return
        }
      }
      i = j
    } else if starts_with_dash(a) {
      eprintln("错误：未知选项 \{a}，看 --help")
      return
    } else {
      eprintln("错误：未知形状 \{a}，看 --help")
      return
    }
  }
  let mut sdf = match base {
    Some(s) => s
    None => {
      print_help()
      return
    }
  }
  let mut ti = 0
  while ti < tools.length() {
    sdf = apply_op(sdf, tools[ti], op, k)
    ti = ti + 1
  }
  sdf = match offset {
    Some(o) => sdf.at(o)
    None => sdf
  }
  let bounds = match sdf.bounds() {
    Some(b) => b.expand(0.5)
    None => {
      eprintln(
        "错误：这个组合没有有限包围盒（半空间？），无法自动网格化",
      )
      return
    }
  }
  if res < 2 {
    eprintln("错误：--res 至少是 2")
    return
  }
  let m = @mooncsg.mesh(
    sdf,
    bounds,
    @mooncsg.MeshOptions::new(int_to_int32(res)),
  )
  // 这个工具链的 `%eprintln` 与 stdout 同流（实测重定向后 stderr 是 0 字节），
  // 所以指标和模型只能二选一：`--stats` 时只输出指标，stdout 才不会混进
  // 指标行、重定向得到的才是干净文件。
  if want_stats {
    println("triangles:  \{m.triangle_count()}")
    println("vertices:   \{m.vertex_count()}")
    println("volume:     \{m.volume()}")
    println("area:       \{m.area()}")
    println("watertight: \{m.is_watertight()}")
    println("euler:      \{m.euler()} (genus \{m.genus()})")
    println(
      "bounds:     \{bounds.min.x},\{bounds.min.y},\{bounds.min.z} .. \{bounds.max.x},\{bounds.max.y},\{bounds.max.z}",
    )
    return
  }
  if format == "obj" {
    println(m.to_obj(name))
  } else if format == "stl" || format == "ascii-stl" {
    println(m.to_stl(name))
  } else {
    eprintln("错误：--format 只支持 stl / obj，收到 \{format}")
  }
}
