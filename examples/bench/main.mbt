///|
/// 网格化性能基线：同一份代码在 native 与 wasm-gc 上各跑一遍，
/// 数字写进 README，回归时重跑对比。
///
/// 计时用 `moonbitlang/core/bench` 的单调时钟——它按目标后端分别绑定
/// 到 native 的 `clock_gettime` / wasm 的 `time_unstable.instant_now`，
/// 所以两个后端的数字是同一口径。
///
/// 单次网格化在几十到几百毫秒量级，不需要上万次迭代取平均；这里取
/// 三次的最小值，最小值比平均值更抗 GC 抖动与调度噪声。
///
/// 注意 `monotonic_clock_end` 返回的是**微秒**，打印前除以 1000 换成毫秒。

///|
fn bench_case(name : String, s : @mooncsg.Sdf, res : Int32) -> Unit {
  let b = match s.bounds() {
    Some(a) => a.expand(0.5)
    None =>
      @mooncsg.Aabb::from_center_half(
        @mooncsg.Vec3::zero(),
        @mooncsg.Vec3::splat(1.0),
      )
  }
  let opts = @mooncsg.MeshOptions::new(res)
  // 先跑一次：冷启动的分配器与 JIT 预热不该算进基线。
  let warm = @mooncsg.mesh(s, b, opts)
  let mut best = 1.0e18
  let mut i = 0
  while i < 3 {
    let t0 = @clock.monotonic_clock_start()
    let m = @mooncsg.mesh(s, b, opts)
    let us = @clock.monotonic_clock_end(t0)
    // 保留结果，避免优化器把整段计算消掉。
    if m.triangle_count() != warm.triangle_count() {
      abort("non-deterministic triangle count on \{name}")
    }
    if us < best {
      best = us
    }
    i = i + 1
  }
  let ms = best / 1000.0
  // 打印「实际」格点数而不是回显 res：超过 MAX_GRID_SLOTS 时请求值会被收窄，
  // 只写 res=256 会让读表的人以为真的跑了 256³。
  let (nx, ny, nz) = @mooncsg.grid_shape(b, res)
  println(
    "\{name} res=\{res} grid=\{nx}x\{ny}x\{nz} tris=\{warm.triangle_count()} verts=\{warm.vertex_count()} ms=\{ms}",
  )
}

///|
fn main {
  bench_case("sphere32", @mooncsg.Sdf::sphere(10.0), 32)
  bench_case("sphere64", @mooncsg.Sdf::sphere(10.0), 64)
  bench_case(
    "boxminussphere48",
    @mooncsg.Sdf::box(@mooncsg.Vec3::new(20.0, 20.0, 20.0)).subtract(
      @mooncsg.Sdf::sphere(24.0),
    ),
    48,
  )
  bench_case(
    "torus48",
    @mooncsg.Sdf::Torus(@mooncsg.Vec3::zero(), 8.0, 3.0),
    48,
  )
  // 大分辨率那两档单独开关：js 后端跑一次要十几秒，进 CI 会把 bench
  // 这条 step 拖成分钟级。默认不跑，`moon run examples/bench --release -- big`
  // 才跑，README 里的 128³/256³ 数字是这么量出来的。
  if @env.args().contains("big") {
    bench_case("sphere128", @mooncsg.Sdf::sphere(25.0), 128)
    bench_case("sphere256", @mooncsg.Sdf::sphere(25.0), 256)
  }
}
