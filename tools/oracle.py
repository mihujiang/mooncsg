#!/usr/bin/env python3
"""mooncsg 的独立解析基准。

这里只用 Python 标准库手算体积/面积，不 import 任何几何库——目的是让
「验收数字」有一个不依赖被测实现、也不依赖 MoonBit 工具链的来源。

用法:
    python tools/oracle.py           # 打印一组固定形状的解析值（JSON）
    python tools/oracle.py --cases   # 打印对拍用例：label / cmd / volume / tol_pct

`--cases` 的输出给 `tools/volume_check.mjs` 用：那边跑
`moon run cmd/main -- <cmd> --res 48 --stats` 拿到实测体积，再和这里的解析值
逐组比阈值。也就是说「解析值来自 oracle.py」这句话是可执行的，不是写在文档里
的一句话。
"""

import json
import math
import sys

PI = math.pi


def sphere(r):
    return {
        "name": "sphere",
        "params": {"r": r},
        "volume": 4.0 / 3.0 * PI * r ** 3,
        "area": 4.0 * PI * r ** 2,
        "euler": 2,
        "genus": 0,
    }


def box(x, y, z):
    return {
        "name": "box",
        "params": {"x": x, "y": y, "z": z},
        "volume": x * y * z,
        "area": 2.0 * (x * y + y * z + z * x),
        "euler": 2,
        "genus": 0,
    }


def cylinder(r, h):
    return {
        "name": "cylinder",
        "params": {"r": r, "h": h},
        "volume": PI * r ** 2 * h,
        "area": 2.0 * PI * r * (r + h),
        "euler": 2,
        "genus": 0,
    }


def cone(r1, r2, h):
    """圆台：`r2 = 0` 即圆锥；`r1 = r2` 退化成圆柱。

    V = πh(R1² + R1R2 + R2²) / 3；侧面积用母线长
    l = sqrt((R1-R2)² + h²)，S = π(R1+R2)l + πR1² + πR2²。
    """
    l = math.hypot(r1 - r2, h)
    return {
        "name": "cone",
        "params": {"r1": r1, "r2": r2, "h": h},
        "volume": PI * h * (r1 ** 2 + r1 * r2 + r2 ** 2) / 3.0,
        "area": PI * (r1 + r2) * l + PI * r1 ** 2 + PI * r2 ** 2,
        "euler": 2,
        "genus": 0,
    }


def capsule(r, h):
    """胶囊：圆柱段 + 两个半球，V = πr²h + 4/3πr³，S = 2πrh + 4πr²。"""
    return {
        "name": "capsule",
        "params": {"r": r, "h": h},
        "volume": PI * r ** 2 * h + 4.0 / 3.0 * PI * r ** 3,
        "area": 2.0 * PI * r * h + 4.0 * PI * r ** 2,
        "euler": 2,
        "genus": 0,
    }


def torus(big_r, small_r):
    return {
        "name": "torus",
        "params": {"R": big_r, "r": small_r},
        "volume": 2.0 * PI ** 2 * big_r * small_r ** 2,
        "area": 4.0 * PI ** 2 * big_r * small_r,
        "euler": 0,
        "genus": 1,
    }


def box_minus_sphere(bx, by, bz, sphere_r):
    """盒 ∖ 球：球心与盒心重合，球在 x/y 方向被盒完全包住，只在 z 方向穿出。

    注意 `sphere_r = 12` 而盒半高只有 10：挖掉的不是整球，是球被两平面
    z=±bz/2 夹住的那段「球带」：
        V = ∫_{-a}^{a} π(r² - z²) dz = 2πa(r² - a²/3),  a = bz/2
    只有当 `sphere_r <= a`（球整个在盒内）时才是 `4/3πr³`。
    """
    a = bz / 2.0
    if sphere_r <= a:
        removed = 4.0 / 3.0 * PI * sphere_r ** 3
    else:
        removed = 2.0 * PI * a * (sphere_r ** 2 - a ** 2 / 3.0)
    return {
        "name": "box_minus_sphere",
        "params": {"x": bx, "y": by, "z": bz, "r": sphere_r},
        "volume": bx * by * bz - removed,
        "area": None,
        "euler": None,
        "genus": None,
    }


def fixed_shapes():
    return [
        sphere(25.0),
        box(40.0, 30.0, 20.0),
        cylinder(20.0, 60.0),
        torus(30.0, 8.0),
        box_minus_sphere(40.0, 30.0, 20.0, 12.0),
    ]


# (标签, 解析结果, cmd/main 的形状参数, 相对误差阈值 %)
# 容差按形状给：球/盒/减球是光滑或大平面，0.5% 就够；圆台顶端是尖棱、
# 胶囊有圆柱-半球接缝、环面在内外赤道附近曲率大，marching tetrahedra 在
# 这些地方只能用细长三角逼近，给 1%。
CASES = [
    ("球 r=10", sphere(10.0), ["sphere", "10"], 0.5),
    ("立方体 边长 10", box(10.0, 10.0, 10.0), ["box", "10"], 0.5),
    ("圆台 底 8 / 高 10", cone(8.0, 0.0, 10.0), ["cone", "8", "0", "10"], 1.0),
    ("胶囊 半径 4 / 段长 10", capsule(4.0, 10.0), ["capsule", "4", "10"], 1.0),
    ("环面 管 3 / 环 10", torus(10.0, 3.0), ["torus", "10", "3"], 1.0),
    (
        "立方体 40×30×20 减球 r=12",
        box_minus_sphere(40.0, 30.0, 20.0, 12.0),
        ["box", "40", "30", "20", "--sphere", "12", "--op", "diff"],
        0.5,
    ),
]


def main(argv):
    if "--cases" in argv:
        # ensure_ascii 默认开：Windows 控制台按 GBK 输出也不会把 JSON 弄坏。
        print(
            json.dumps(
                [
                    {
                        "label": label,
                        "cmd": args,
                        "volume": shape["volume"],
                        "tol_pct": tol,
                    }
                    for label, shape, args, tol in CASES
                ],
                indent=2,
                sort_keys=True,
            )
        )
        return 0
    if len(argv) > 1:
        sys.stderr.write("用法：python tools/oracle.py [--cases]\n")
        return 2
    out = {s["name"]: s for s in fixed_shapes()}
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
