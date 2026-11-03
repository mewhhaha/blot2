#!/usr/bin/env python3
"""Independent checksum oracles; no timing or compiler calls."""

import argparse
import json
import math
import struct
import zlib
from functools import cache

MASK = 0xFFFFFFFF


@cache
def prepared_bytes(size):
    result = bytearray(size)
    state = 42
    for index in range(size):
        state = (state * 3877 + 29573) % 139968
        result[index] = state * 256 // 139968
    return bytes(result)


@cache
def fannkuch(n):
    permutation = list(range(n))
    counts = [0] * n
    rotation = n
    ordinal = 0
    checksum = 0
    maximum = 0
    while True:
        while rotation > 1:
            counts[rotation - 1] = rotation
            rotation -= 1
        work = permutation.copy()
        flips = 0
        while work[0]:
            extent = work[0] + 1
            work[:extent] = reversed(work[:extent])
            flips += 1
        maximum = max(maximum, flips)
        if ordinal % 2 == 0:
            checksum += flips
        else:
            checksum -= flips
        while True:
            if rotation == n:
                return (checksum * 100 + maximum) & MASK
            extent = rotation + 1
            permutation[:extent] = permutation[1:extent] + permutation[:1]
            counts[rotation] -= 1
            if counts[rotation] > 0:
                break
            rotation += 1
        ordinal += 1


@cache
def custom_hash(size):
    lanes = [
        0x6A09E667,
        0xBB67AE85,
        0x3C6EF372,
        0xA54FF53A,
        0x510E527F,
        0x9B05688C,
        0x1F83D9AB,
        0x5BE0CD19,
    ]
    for index, byte in enumerate(prepared_bytes(size)):
        lane = index % 8
        value = (lanes[lane] * 33 + byte) & MASK
        lanes[lane] = ((value + (value << 10)) ^ (value >> 6)) & MASK
    digest = b"".join(value.to_bytes(4, "big") for value in lanes)
    return int.from_bytes(digest[:4], "little")


@cache
def sieve(limit):
    flags = bytearray(b"\1") * (limit + 1)
    flags[:2] = b"\0\0"
    for prime in range(2, math.isqrt(limit) + 1):
        if flags[prime]:
            start = prime * prime
            flags[start::prime] = b"\0" * ((limit - start) // prime + 1)
    last = next(n for n in range(limit, 1, -1) if flags[n])
    return last + sum(flags)


@cache
def sorted_data(size):
    state = 42
    values = []
    for _ in range(size):
        state = (state * 3877 + 29573) % 139968
        values.append(int(state / 139968 * 1000000))
    return values, sorted(values), state


def sort_checksum(size, iterations, warmups):
    values, ordered, state = sorted_data(size)
    total = 0
    for count in [warmups, iterations]:
        for _ in range(count):
            state = (state * 3877 + 29573) % 139968
            total += values[int(state / 139968 * size)]
            state = (state * 3877 + 29573) % 139968
            total += ordered[int(state / 139968 * size)]
        state = 42
    return total & MASK


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


@cache
def mandelbrot_image(width, height, binary32):
    number = float
    if binary32:
        number = f32
    image = bytearray(f"P4\n{width} {height}\n".encode())
    for y in range(height):
        ci = number(number(number(2.0 * number(y)) / number(height)) - 1.0)
        accumulator = bits = 0
        for x in range(width):
            cr = number(number(number(2.0 * number(x)) / number(width)) - 1.5)
            zr = zi = tr = ti = 0.0
            for _ in range(50):
                if number(tr + ti) > 4.0:
                    break
                zi = number(number(number(2.0 * zr) * zi) + ci)
                zr = number(number(tr - ti) + cr)
                tr = number(zr * zr)
                ti = number(zi * zi)
            accumulator <<= 1
            if number(tr + ti) <= 4.0:
                accumulator |= 1
            bits += 1
            if bits == 8:
                image.append(accumulator)
                accumulator = bits = 0
            elif x == width - 1:
                image.append(accumulator << (8 - width % 8))
                accumulator = bits = 0
    return bytes(image)


def checksum(name, parameter, iterations, warmups):
    if name in ("mandelbrot_f32", "mandelbrot_f64"):
        width, height = parameter
        image = mandelbrot_image(width, height, name == "mandelbrot_f32")
        result = 5381
        for byte in image * (iterations + warmups):
            result = (result * 33 + byte) & MASK
        return result
    if isinstance(parameter, (list, tuple)):
        (parameter,) = parameter
    if name in ("sort_merge", "sort_quick"):
        return sort_checksum(parameter, iterations, warmups)
    if name == "fannkuch":
        value = fannkuch(parameter)
    elif name == "crc32":
        value = zlib.crc32(prepared_bytes(parameter))
    elif name == "custom_hash":
        value = custom_hash(parameter)
    elif name == "sieve":
        value = sieve(parameter)
    else:
        raise ValueError(name)
    return value * (iterations + warmups) & MASK


PROFILES = {
    "small": [
        ("fannkuch", 5, 3, 1, 4428),
        ("crc32", 1000, 3, 1, 3031698216),
        ("custom_hash", 1000, 3, 1, 1036619072),
        ("sieve", 1000, 3, 1, 4660),
        ("sort_merge", 100000, 2, 1, 2548773),
        ("sort_quick", 100000, 2, 1, 2548773),
        ("mandelbrot_f64", (30, 30), 3, 1, 2236342953),
        ("mandelbrot_f32", (30, 30), 3, 1, None),
    ],
    "run": [
        ("fannkuch", 8, 700, 140, 135762480),
        ("crc32", 1000000, 150, 30, 2318723244),
        ("custom_hash", 1000000, 1200, 240, 2844672256),
        ("sieve", 3000000, 270, 54, 1042248060),
        ("sort_merge", 400000, 50, 10, 61757772),
        ("sort_quick", 400000, 50, 10, 61757772),
        ("mandelbrot_f64", (400, 400), 100, 20, 3455988829),
        ("mandelbrot_f32", (400, 400), 100, 20, None),
    ],
    "bounded": [
        ("fannkuch", 8, 8, 2, None),
        ("crc32", 1000000, 4, 1, None),
        ("custom_hash", 1000000, 64, 13, None),
        ("sieve", 3000000, 4, 1, None),
        ("sort_merge", 400000, 4, 1, None),
        ("sort_quick", 400000, 4, 1, None),
        ("mandelbrot_f32", (400, 400), 4, 1, None),
    ],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES, action="append")
    args = parser.parse_args()
    selected = args.profile
    if selected is None:
        selected = list(PROFILES)
    for profile in selected:
        for name, parameter, iterations, warmups, expected in PROFILES[profile]:
            actual = checksum(name, parameter, iterations, warmups)
            if expected is not None and actual != expected:
                raise AssertionError((profile, name, expected, actual))
            parameters = [parameter]
            if isinstance(parameter, tuple):
                parameters = list(parameter)
            print(
                json.dumps(
                    {
                        "profile": profile,
                        "name": name,
                        "parameters": parameters,
                        "iterations": iterations,
                        "warmups": warmups,
                        "checksum": actual,
                    }
                )
            )


if __name__ == "__main__":
    main()
