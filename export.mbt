///|
/// 文本格式导出。先做 OBJ 与 ASCII STL：两者都不需要二进制打包，
/// 结果可以直接用 `diff` 比对，也就顺势成了回归测试的一部分。
/// 二进制 STL 留到需要进切片软件时再加。
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
