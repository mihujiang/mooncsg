///|
/// 文本格式导出。先做 OBJ 与 ASCII STL：两者都不需要二进制打包，
/// 结果可以直接用 `diff` 比对，也就顺势成了回归测试的一部分。
/// 二进制 STL 见文件末尾：它需要位打包，但也带来一个好处——
/// 可以写回读，用「导出再导入」检验网格是不是真的没丢东西。
pub fn Mesh::to_obj(self : Mesh, name : String) -> String {
  let out = StringBuilder()
  out.write_string("# mooncsg ")
  out.write_string(name)
  out.write_string("\n")
  out.write_string("# vertices ")
  out.write_string(self.vertex_count().to_string())
  out.write_string(", triangles ")
  out.write_string(self.triangle_count().to_string())
  out.write_string("\n")
  for p in self.positions {
    out.write_string("v ")
    out.write_string(p.x.to_string())
    out.write_string(" ")
    out.write_string(p.y.to_string())
    out.write_string(" ")
    out.write_string(p.z.to_string())
    out.write_string("\n")
  }
  let mut i = 0
  while i < self.triangle_count() {
    // OBJ 索引从 1 开始
    out.write_string("f ")
    out.write_string((self.indices[i * 3] + 1).to_string())
    out.write_string(" ")
    out.write_string((self.indices[i * 3 + 1] + 1).to_string())
    out.write_string(" ")
    out.write_string((self.indices[i * 3 + 2] + 1).to_string())
    out.write_string("\n")
    i = i + 1
  }
  out.to_string()
}

///|
/// ASCII STL。STL 不带顶点索引，每个三角形重复三个顶点，
/// 所以文件通常比 OBJ 大——换来的是所有切片软件/查看器都认。
pub fn Mesh::to_stl(self : Mesh, name : String) -> String {
  let out = StringBuilder()
  out.write_string("solid ")
  out.write_string(name)
  out.write_string("\n")
  let mut i = 0
  while i < self.triangle_count() {
    let (a, b, c) = self.triangle(i)
    let n = b.sub(a).cross(c.sub(a)).normalize()
    out.write_string("  facet normal ")
    out.write_string(n.x.to_string())
    out.write_string(" ")
    out.write_string(n.y.to_string())
    out.write_string(" ")
    out.write_string(n.z.to_string())
    out.write_string("\n    outer loop\n")
    out.write_string("      vertex ")
    out.write_string(a.x.to_string())
    out.write_string(" ")
    out.write_string(a.y.to_string())
    out.write_string(" ")
    out.write_string(a.z.to_string())
    out.write_string("\n")
    out.write_string("      vertex ")
    out.write_string(b.x.to_string())
    out.write_string(" ")
    out.write_string(b.y.to_string())
    out.write_string(" ")
    out.write_string(b.z.to_string())
    out.write_string("\n")
    out.write_string("      vertex ")
    out.write_string(c.x.to_string())
    out.write_string(" ")
    out.write_string(c.y.to_string())
    out.write_string(" ")
    out.write_string(c.z.to_string())
    out.write_string("\n")
    out.write_string("    endloop\n  endfacet\n")
    i = i + 1
  }
  out.write_string("endsolid ")
  out.write_string(name)
  out.write_string("\n")
  out.to_string()
}

///|
fn write_f32(buf : @buffer.Buffer, v : Double) -> Unit {
  buf.write_uint_le(Float::from_double(v).reinterpret_as_uint())
}

///|
/// 小端读 4 字节。不用 `Bytes::unsafe_extract_uint_le`：那是实验 API，
/// 版本升级会被打断；4 个字节自己拼更稳，也不依赖字节序假设。
fn read_u32_le(data : Bytes, offset : Int32) -> UInt32 {
  data.at(offset).to_uint() |
  (data.at(offset + 1).to_uint() << 8) |
  (data.at(offset + 2).to_uint() << 16) |
  (data.at(offset + 3).to_uint() << 24)
}

///|
fn read_f32(data : Bytes, offset : Int32) -> Double {
  Float::reinterpret_from_uint(read_u32_le(data, offset)).to_double()
}

///|
/// 二进制 STL：80 字节头 + `uint32` 三角形数 + 每三角形 50 字节
/// （法线 12 字节 + 三顶点 36 字节 + 属性 2 字节）。全部小端。
///
/// 头 80 字节留空。很多工具往里塞模型名，但格式本身不规定，
/// 空着头反而省掉一次「名字超过 80 字节怎么办」的讨论。
/// 顶点坐标按 `f32` 存储，这是格式本身的限制。往返测试因此用
/// 「相对误差 < 1e-6」而不是逐位相等：`f32` 只有 24 位有效数字。
pub fn Mesh::to_stl_binary(self : Mesh) -> Bytes {
  let buf = @buffer.Buffer()
  let mut i = 0
  while i < 80 {
    buf.write_byte(b'\x00')
    i = i + 1
  }
  buf.write_uint_le(self.triangle_count().reinterpret_as_uint())
  let mut t = 0
  while t < self.triangle_count() {
    let (a, b, c) = self.triangle(t)
    let raw = b.sub(a).cross(c.sub(a))
    let len = raw.length()
    let n = if len > 0.0 { raw.div(len) } else { Vec3::zero() }
    write_f32(buf, n.x)
    write_f32(buf, n.y)
    write_f32(buf, n.z)
    write_f32(buf, a.x)
    write_f32(buf, a.y)
    write_f32(buf, a.z)
    write_f32(buf, b.x)
    write_f32(buf, b.y)
    write_f32(buf, b.z)
    write_f32(buf, c.x)
    write_f32(buf, c.y)
    write_f32(buf, c.z)
    buf.write_byte(b'\x00')
    buf.write_byte(b'\x00')
    t = t + 1
  }
  buf.to_bytes()
}

///|
/// STL 顶点的分桶键：三个 `f32` 位模式用 FNV-1a 混成一个 64 位数。
///
/// 只用来分桶；桶里还要按坐标逐个精确比较，所以哈希碰撞不会把两个
/// 不同顶点合并（碰撞只会让桶变长）。

///|
/// 两个坐标的 `f32` 位模式是否相同。用位模式而不是 `==`：`-0.0 == 0.0`
/// 为真但位模式不同，而位模式才是「导出时写下的是同一个值」的判据。
fn same_f32_bits(a : Double, b : Double) -> Bool {
  Float::from_double(a).reinterpret_as_uint() ==
  Float::from_double(b).reinterpret_as_uint()
}

///|
fn stl_vertex_key(x : Double, y : Double, z : Double) -> UInt64 {
  let mut h : UInt64 = 0xcbf29ce484222325UL
  h = fnv1a(h, Float::from_double(x).reinterpret_as_uint().to_uint64())
  h = fnv1a(h, Float::from_double(y).reinterpret_as_uint().to_uint64())
  h = fnv1a(h, Float::from_double(z).reinterpret_as_uint().to_uint64())
  h
}

///|
/// 二进制 STL 回读。
///
/// STL 没有索引，同一个顶点会在每个相邻三角形里重复出现。这里按
/// `f32` 位模式做精确去重（不是 eps 距离）：同一位置写出去时位模式
/// 相同，读回来也相同，所以能还原原始顶点数。这个等价关系只在
/// 「导出后未经过任何编辑」时成立，正好是往返测试要的性质。
///
/// 实现上按 `UInt64` 哈希分桶、桶内比坐标：早期版本给每个顶点拼一个
/// `String` 当键，十几万面的 STL 要构造几十万个字符串，回读时间和
/// 内存都被这一项主导。
pub fn Mesh::from_stl_binary(data : Bytes) -> Mesh? {
  if data.length() < 84 {
    return None
  }
  let tri = read_u32_le(data, 80).reinterpret_as_int()
  if tri < 0 || tri > 10000000 {
    return None
  }
  if data.length() < 84 + tri * 50 {
    return None
  }
  let positions : Array[Vec3] = []
  let indices : Array[Int32] = []
  let seen : @hashmap.HashMap[UInt64, Array[Int32]] = @hashmap.HashMap(
    [],
    capacity=1024,
  )
  let mut t = 0
  while t < tri {
    let base = 84 + t * 50
    let mut k = 0
    while k < 3 {
      let off = base + 12 + k * 12
      let x = read_f32(data, off)
      let y = read_f32(data, off + 4)
      let z = read_f32(data, off + 8)
      let key = stl_vertex_key(x, y, z)
      let mut idx : Int32 = -1
      match seen.get(key) {
        Some(bucket) => {
          let mut j = 0
          while j < bucket.length() && idx < 0 {
            let p = positions[bucket[j]]
            if same_f32_bits(p.x, x) &&
              same_f32_bits(p.y, y) &&
              same_f32_bits(p.z, z) {
              idx = bucket[j]
            }
            j = j + 1
          }
        }
        None => ()
      }
      if idx < 0 {
        idx = positions.length()
        positions.push(Vec3::new(x, y, z))
        match seen.get(key) {
          Some(bucket) => bucket.push(idx)
          None => {
            let bucket : Array[Int32] = [idx]
            seen.set(key, bucket)
          }
        }
      }
      indices.push(idx)
      k = k + 1
    }
    t = t + 1
  }
  Some(Mesh::new(positions, indices))
}
