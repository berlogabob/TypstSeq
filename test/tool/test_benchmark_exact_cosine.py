import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import numpy as np

spec = importlib.util.spec_from_file_location(
    "bench", Path(__file__).parents[2] / "tool/benchmark_exact_cosine.py"
)
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class BenchmarkTest(unittest.TestCase):
    def test_fixture_determinism(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d) / "a.npy", Path(d) / "b.npy"
            bench.generate(a, 20, 7)
            bench.generate(b, 20, 7)
            self.assertEqual(a.read_bytes(), b.read_bytes())

    def test_mmap_order_and_ties(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "v.npy"
            values = np.zeros((20, 384), np.float32)
            values[:, 0] = 1
            np.save(p, values)
            mmap = np.load(p, mmap_mode="r")
            np.testing.assert_array_equal(
                bench.top_k(np.eye(384, dtype=np.float32)[0], mmap, 3), [0, 1, 2]
            )

    def test_metrics_and_invalid_inputs(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "v.npy"
            bench.generate(p, 20, 1)
            result = bench.benchmark(p, 3, 2)
            self.assertEqual((result["count"], result["dimension"]), (20, 384))
            self.assertGreater(result["p95_ms"], 0)
            self.assertEqual(len(result["sha256"]), 64)
            with self.assertRaisesRegex(ValueError, "invalid_k"):
                bench.top_k(np.ones(384), np.load(p, mmap_mode="r"), 21)
            with self.assertRaisesRegex(ValueError, "invalid_warm_count"):
                bench.benchmark(p, 0)

    def test_privacy_and_bad_file(self):
        with tempfile.TemporaryDirectory() as d:
            missing = Path(d) / "private-secret" / "missing.npy"
            with self.assertRaises(OSError):
                bench.benchmark(missing)
            result = subprocess.run(
                [
                    sys.executable,
                    str(Path(__file__).parents[2] / "tool/benchmark_exact_cosine.py"),
                    "benchmark",
                    str(missing),
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotIn(str(missing), result.stderr)


if __name__ == "__main__":
    unittest.main()
