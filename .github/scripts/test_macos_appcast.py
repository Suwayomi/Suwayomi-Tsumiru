#!/usr/bin/env python3
import base64
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import configure_macos_sparkle as configure
TEST_KEY = base64.b64encode(b"k" * 32).decode()


def _write(path: Path, content: bytes) -> Path:
    path.write_bytes(content)
    return path


@unittest.skipUnless(sys.platform == "darwin", "CryptoKit verification needs macOS")
class SparkleVerifyHelperTest(unittest.TestCase):
    HELPER = Path(__file__).resolve().parent / "sparkle_verify_signature.swift"
    # sign_update fixture over PROBE_BYTES with the RFC 8032 7.1 test seed (public, not production).
    PROBE_BYTES = b"sparkle interop probe v1"
    PROBE_PUBLIC_KEY = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
    PROBE_SIGNATURE = (
        "x9xQmkmY6I3YjdGJJTD6O3KDvBSeSew1BiHzKD1TENaJK2XZ8glH77pxZSgc7TP+"
        "CD7VDnNa+5mSW/qKy4IRAA=="
    )
    RFC_SEED_B64 = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc not available")
        cls._tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls._tmp.cleanup)
        cls.verifier = str(Path(cls._tmp.name) / "sparkle_verify")
        compiled = subprocess.run(
            ["swiftc", "-o", cls.verifier, str(cls.HELPER)],
            capture_output=True, text=True, timeout=300,
        )
        if compiled.returncode != 0:
            raise AssertionError(f"swiftc failed:\n{compiled.stderr}")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def _verify(self, *, public_key: str, path: Path, signature: str):
        return subprocess.run(
            [self.verifier, "--public-key", public_key,
             "--zip", str(path), "--signature", signature],
            capture_output=True, text=True, timeout=120,
        )

    @staticmethod
    def _find_sign_update() -> Path | None:
        env = os.environ.get("SPARKLE_SIGN_UPDATE")
        if env and Path(env).is_file() and os.access(env, os.X_OK):
            return Path(env)
        pods = (
            Path(configure.repo_root()) / "macos" / "Pods" / "Sparkle"
            / "bin" / "sign_update"
        )
        if pods.is_file() and os.access(pods, os.X_OK):
            return pods
        which = shutil.which("sign_update")
        return Path(which) if which else None

    def test_modified_archive_rejected(self):
        target = _write(self.root / "probe.bin", self.PROBE_BYTES + b"!")
        result = self._verify(
            public_key=self.PROBE_PUBLIC_KEY, path=target,
            signature=self.PROBE_SIGNATURE,
        )
        self.assertEqual(result.returncode, 1)

    def test_mismatched_key_rejected(self):
        target = _write(self.root / "probe.bin", self.PROBE_BYTES)
        result = self._verify(
            public_key=TEST_KEY, path=target, signature=self.PROBE_SIGNATURE,
        )
        self.assertEqual(result.returncode, 1)

    def test_live_sign_update_roundtrip(self):
        sign_update = self._find_sign_update()
        if sign_update is None:
            self.skipTest("sign_update not available (runs after pod install)")
        target = _write(self.root / "live.bin", b"live roundtrip payload")
        signed = subprocess.run(
            [str(sign_update), "--ed-key-file", "-", "-p", str(target)],
            input=self.RFC_SEED_B64, capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(signed.returncode, 0, signed.stderr)
        signature = signed.stdout.strip()
        self.assertEqual(len(base64.b64decode(signature)), 64)
        accepted = self._verify(
            public_key=self.PROBE_PUBLIC_KEY, path=target, signature=signature,
        )
        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        target.write_bytes(b"live roundtrip payload, tampered")
        rejected = self._verify(
            public_key=self.PROBE_PUBLIC_KEY, path=target, signature=signature,
        )
        self.assertEqual(rejected.returncode, 1)


if __name__ == "__main__":
    unittest.main()
