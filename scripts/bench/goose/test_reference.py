"""Independent official checksums and precision/retained-output boundaries."""

import unittest

from reference import PROFILES, checksum, mandelbrot_image


class ReferenceTests(unittest.TestCase):
    def test_official_small_and_production_checksums(self):
        for profile in ["small", "run"]:
            for name, parameter, iterations, warmups, expected in PROFILES[profile]:
                if expected is None:
                    continue
                with self.subTest(profile=profile, case=name):
                    self.assertEqual(
                        checksum(name, parameter, iterations, warmups), expected
                    )

    def test_binary32_pbm_padding_and_retained_warmups(self):
        # Cross-checked against the explicit F32 Goose control and executed Blot.
        rows = [
            ((1, 1), 1, 0, 234277983),
            ((7, 5), 2, 1, 1948218797),
            ((8, 3), 1, 2, 1723907054),
            ((9, 7), 2, 0, 3494862677),
            ((13, 11), 2, 2, 3653072549),
            ((40, 30), 1, 1, 3998479799),
        ]
        for dimensions, iterations, warmups, expected in rows:
            with self.subTest(dimensions=dimensions):
                self.assertEqual(
                    checksum("mandelbrot_f32", dimensions, iterations, warmups),
                    expected,
                )
                width, height = dimensions
                header = f"P4\n{width} {height}\n".encode()
                image = mandelbrot_image(width, height, True)
                self.assertEqual(image[: len(header)], header)
                self.assertEqual(len(image), len(header) + height * ((width + 7) // 8))

    def test_binary32_is_a_control_not_the_original_binary64_workload(self):
        self.assertEqual(checksum("mandelbrot_f32", (400, 400), 100, 20), 3340890973)
        self.assertNotEqual(
            mandelbrot_image(400, 400, True), mandelbrot_image(400, 400, False)
        )


if __name__ == "__main__":
    unittest.main()
