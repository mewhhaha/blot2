#!/usr/bin/env python3
"""Independent checksum oracles; no timing or compiler calls."""

import argparse
import json
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


def checksum(name, parameter, iterations, warmups):
    if name == "fannkuch":
        value = fannkuch(parameter)
    elif name == "crc32":
        value = zlib.crc32(prepared_bytes(parameter))
    elif name == "custom_hash":
        value = custom_hash(parameter)
    else:
        raise ValueError(name)
    return value * (iterations + warmups) & MASK


PROFILES = {
    "small": [
        ("fannkuch", 5, 3, 1, 4428),
        ("crc32", 1000, 3, 1, 3031698216),
        ("custom_hash", 1000, 3, 1, 1036619072),
    ],
    "run": [
        ("fannkuch", 8, 700, 140, 135762480),
        ("crc32", 1000000, 150, 30, 2318723244),
        ("custom_hash", 1000000, 1200, 240, 2844672256),
    ],
    "bounded": [
        ("fannkuch", 8, 8, 2, None),
        ("crc32", 1000000, 4, 1, None),
        ("custom_hash", 1000000, 64, 13, None),
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
            print(
                json.dumps(
                    {
                        "profile": profile,
                        "name": name,
                        "parameters": [parameter],
                        "iterations": iterations,
                        "warmups": warmups,
                        "checksum": actual,
                    }
                )
            )


if __name__ == "__main__":
    main()
