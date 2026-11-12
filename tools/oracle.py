#!/usr/bin/env python3
"""mooncsg 的独立解析基准。

这里只用 Python 标准库手算体积/面积，不 import 任何几何库——目的是让
「验收数字」有一个不依赖被测实现、也不依赖 MoonBit 工具链的来源。
输出是 JSON，交给 tools/acceptance.ps1 与 MoonBit 侧的体积对拍。

用法:
    python tools/oracle.py            # 打印 JSON
    python tools/oracle.py --check 球体积  # 只查一项
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

    被挖掉的是球被两平面 z=±bz/2 夹住的「球带」：
        V = ∫_{-a}^{a} π(r² - z²) dz = 2πa(r² - a²/3)
    这是可手算的闭式，不需要数值积分。
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


def main():
    shapes = [
        sphere(25.0),
        box(40.0, 30.0, 20.0),
        cylinder(20.0, 60.0),
        torus(30.0, 8.0),
        box_minus_sphere(40.0, 30.0, 20.0, 12.0),
    ]
    out = {s["name"]: s for s in shapes}
    print(json.dumps(out, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
