#!/usr/bin/env python3
import base64
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import configure_macos_sparkle as configure
import macos_appcast as appcast

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"

TEST_KEY = base64.b64encode(b"k" * 32).decode()
TEST_SIG = base64.b64encode(b"s" * 64).decode()
TEST_FEED = "https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/latest/download/appcast.xml"


def _write(path: Path, content: bytes) -> Path:
    path.write_bytes(content)
    return path


class GenerateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.zip = _write(self.root / "tsumiru-v9.9.9-macos-universal.zip", b"z" * 4096)
        os.utime(self.zip, (1_700_000_000, 1_700_000_000))

    def _generate(self, **overrides) -> bytes:
        args = {
            "version": "9.9.9",
            "build": "9999",
            "tag": "v9.9.9",
            "repo": "Suwayomi/Suwayomi-Tsumiru",
            "archive": self.zip,
            "signature": TEST_SIG,
            "min_os": "12.0",
            "download_url": "https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/download/v9.9.9/tsumiru-v9.9.9-macos-universal.zip",
        }
        args.update(overrides)
        return appcast.generate_appcast(**args)

    def test_fields(self):
        root = ET.fromstring(self._generate())
        item = root.find("./channel/item")
        self.assertIsNotNone(item)
        self.assertEqual(
            item.findtext(f"{{{SPARKLE_NS}}}version"), "9999"
        )
        self.assertEqual(
            item.findtext(f"{{{SPARKLE_NS}}}shortVersionString"), "9.9.9"
        )
        self.assertEqual(
            item.findtext(f"{{{SPARKLE_NS}}}minimumSystemVersion"), "12.0"
        )
        self.assertEqual(item.findtext("title"), "Version 9.9.9 (9999)")
        self.assertEqual(
            item.findtext("link"),
            "https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/tag/v9.9.9",
        )
        enclosure = item.find("enclosure")
        self.assertEqual(
            enclosure.get("url"),
            "https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/download/v9.9.9/tsumiru-v9.9.9-macos-universal.zip",
        )
        self.assertEqual(enclosure.get("length"), "4096")
        self.assertEqual(enclosure.get("type"), "application/octet-stream")
        self.assertEqual(
            enclosure.get(f"{{{SPARKLE_NS}}}edSignature"), TEST_SIG
        )
        self.assertEqual(enclosure.get(f"{{{SPARKLE_NS}}}os"), "macos")
        self.assertEqual(len(root.findall("./channel/item")), 1)

    def test_deterministic_bytes(self):
        self.assertEqual(self._generate(), self._generate())

    def test_xml_escaping_round_trips(self):
        raw = self._generate(repo='O&r<g"q')
        self.assertIn(b"O&amp;r&lt;g", raw)
        root = ET.fromstring(raw)
        self.assertIn('O&r<g"q', root.findtext("./channel/item/link"))

    def test_pubdate_defaults_to_archive_mtime(self):
        root = ET.fromstring(self._generate())
        self.assertEqual(
            root.findtext("./channel/item/pubDate"), "Tue, 14 Nov 2023 22:13:20 GMT"
        )

    def test_explicit_pubdate_used(self):
        root = ET.fromstring(self._generate(pubdate="Wed, 28 Oct 2026 10:00:00 +0000"))
        self.assertEqual(
            root.findtext("./channel/item/pubDate"), "Wed, 28 Oct 2026 10:00:00 +0000"
        )

    def test_rejections(self):
        bad = [
            {"version": "9.9"},
            {"version": "v9.9.9"},
            {"build": "abc"},
            {"tag": "9.9.9"},
            {"tag": "v9.9.8"},
            # Prereleases reuse the same tag shape; suffixed tags never ship.
            {"tag": "v9.9.9-rc1"},
            {"min_os": "twelve"},
            {"min_os": "12.0.1.2"},
            {"signature": "not-base64!!"},
            {"signature": base64.b64encode(b"s" * 32).decode()},
            {"download_url": "http://example.com/a.zip"},
            {"download_url": "https://"},
            {"archive": self.root / "missing.zip"},
            {"pubdate": "not a date"},
        ]
        for kwargs in bad:
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                self._generate(**kwargs)

    def test_empty_archive_rejected(self):
        empty = _write(self.root / "empty.zip", b"")
        with self.assertRaises(ValueError):
            self._generate(archive=empty)


class ValidateMetadataTest(unittest.TestCase):
    def _run(self, **overrides) -> int:
        args = {
            "--version": "9.9.9",
            "--build": "9999",
            "--tag": "v9.9.9",
            "--min-os": "12.0",
        }
        for key, value in overrides.items():
            args[f"--{key.replace('_', '-')}"] = value
        argv = ["validate-metadata"]
        for key, value in args.items():
            argv += [key, value]
        return appcast.main(argv)

    def test_valid_metadata_exits_zero(self):
        self.assertEqual(self._run(), 0)

    def test_tag_mismatch_fails(self):
        self.assertEqual(self._run(tag="v9.9.8"), 2)

    def test_bad_version_or_build_fails(self):
        self.assertEqual(self._run(version="9.9"), 2)
        self.assertEqual(self._run(build="abc"), 2)
        self.assertEqual(self._run(min_os="twelve"), 2)


class ConfigureTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.output = Path(self.tmp.name) / "Sparkle.xcconfig"
        self.old_env = dict(os.environ)
        os.environ.pop(configure.FEED_URL_ENV, None)
        os.environ.pop(configure.PUBLIC_KEY_ENV, None)
        self.addCleanup(os.environ.update, self.old_env)
        for key in (configure.FEED_URL_ENV, configure.PUBLIC_KEY_ENV):
            if key not in self.old_env:
                self.addCleanup(os.environ.pop, key, None)

    def test_escape_breaks_double_slash(self):
        self.assertEqual(
            configure.escape_xcconfig_value(TEST_FEED),
            "https:/$()/$()github.com/$()Suwayomi/$()Suwayomi-Tsumiru"
            "/$()releases/$()latest/$()download/$()appcast.xml",
        )
        # Xcode expands the empty variable back, so the value round-trips.
        self.assertEqual(
            configure.escape_xcconfig_value(TEST_FEED).replace("/$()", "/"),
            TEST_FEED,
        )

    def test_feed_url_rejections(self):
        for raw in [
            "",
            "http://example.com/appcast.xml",
            "https://",
            "https:///path-only",
            "https://user@example.com/appcast.xml",
            "https://example.com/has space.xml",
            "https://example.com/line\nbreak.xml",
            "https://example.com/$(LEAK).xml",
            'https://example.com/"quoted".xml',
            "https://exämple.com/appcast.xml",
        ]:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                configure.validate_feed_url(raw)

    def test_public_key_validation(self):
        self.assertEqual(configure.validate_public_key(TEST_KEY), TEST_KEY)
        for raw in [
            "",
            "not-base64!!",
            base64.b64encode(b"k" * 31).decode(),
            base64.b64encode(b"k" * 33).decode(),
            TEST_KEY + "\n",
        ]:
            with self.subTest(raw=raw[:20]), self.assertRaises(ValueError):
                configure.validate_public_key(raw)

    def test_disabled_when_neither_set(self):
        code = configure.main(["--output", str(self.output)])
        self.assertEqual(code, 0)
        content = self.output.read_text()
        self.assertIn("SPARKLE_FEED_URL = \n", content)
        self.assertIn("SPARKLE_PUBLIC_KEY = \n", content)
        self.assertIn("disabled", content)

    def test_partial_config_fails(self):
        with self.assertRaises(SystemExit) as context:
            configure.main(
                ["--feed-url", TEST_FEED, "--output", str(self.output)]
            )
        self.assertNotEqual(context.exception.code, 0)
        with self.assertRaises(SystemExit):
            configure.main(
                ["--public-key", TEST_KEY, "--output", str(self.output)]
            )
        self.assertFalse(self.output.exists())

    def test_invalid_values_fail(self):
        with self.assertRaises(SystemExit):
            configure.main(
                [
                    "--feed-url", "http://example.com/a.xml",
                    "--public-key", TEST_KEY,
                    "--output", str(self.output),
                ]
            )
        self.assertFalse(self.output.exists())

    def test_configured_writes_escaped_values(self):
        code = configure.main(
            [
                "--feed-url", TEST_FEED,
                "--public-key", TEST_KEY,
                "--output", str(self.output),
            ]
        )
        self.assertEqual(code, 0)
        content = self.output.read_text()
        self.assertIn("SPARKLE_FEED_URL = https:/$()/$()github.com/", content)
        self.assertIn(f"SPARKLE_PUBLIC_KEY = {TEST_KEY}\n", content)

    def test_public_key_with_double_slash_survives_xcconfig(self):
        key = base64.b64encode(bytes([255]) * 32).decode()
        self.assertIn("//", key)
        code = configure.main(
            [
                "--feed-url", TEST_FEED,
                "--public-key", key,
                "--output", str(self.output),
            ]
        )
        self.assertEqual(code, 0)
        values = {}
        for line in self.output.read_text().splitlines():
            if line.startswith("SPARKLE_FEED_URL = "):
                values["feed"] = line.split(" = ", 1)[1]
            elif line.startswith("SPARKLE_PUBLIC_KEY = "):
                values["key"] = line.split(" = ", 1)[1]
        # Raw `//` would truncate the value as an xcconfig comment.
        self.assertNotIn("//", values["key"])
        self.assertNotIn("//", values["feed"])
        # Simulates Xcode expanding the empty variable: exact round-trip.
        self.assertEqual(values["key"].replace("/$()", "/"), key)
        self.assertEqual(values["feed"].replace("/$()", "/"), TEST_FEED)

    def test_environment_inputs(self):
        os.environ[configure.FEED_URL_ENV] = TEST_FEED
        os.environ[configure.PUBLIC_KEY_ENV] = TEST_KEY
        code = configure.main(["--output", str(self.output)])
        self.assertEqual(code, 0)
        self.assertIn("https:/$()/$()github.com/", self.output.read_text())

    def test_arguments_win_over_environment(self):
        os.environ[configure.FEED_URL_ENV] = "https://env.example.com/appcast.xml"
        os.environ[configure.PUBLIC_KEY_ENV] = TEST_KEY
        code = configure.main(
            [
                "--feed-url", TEST_FEED,
                "--public-key", TEST_KEY,
                "--output", str(self.output),
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn("https:/$()/$()github.com/", self.output.read_text())

    def test_explicit_empty_argument_overrides_environment(self):
        os.environ[configure.FEED_URL_ENV] = TEST_FEED
        os.environ[configure.PUBLIC_KEY_ENV] = TEST_KEY
        with self.assertRaises(SystemExit):
            configure.main(["--feed-url", "", "--output", str(self.output)])
        self.assertFalse(self.output.exists())
        code = configure.main(
            ["--feed-url", "", "--public-key", "", "--output", str(self.output)]
        )
        self.assertEqual(code, 0)
        self.assertIn("SPARKLE_PUBLIC_KEY = \n", self.output.read_text())


@unittest.skipUnless(sys.platform == "darwin", "CryptoKit verification needs macOS")
class SparkleVerifyHelperTest(unittest.TestCase):
    HELPER = Path(__file__).resolve().parent / "sparkle_verify_signature.swift"
    # Fixture signed by Sparkle 2.10.1 sign_update over PROBE_BYTES with the
    # RFC 8032 section 7.1 test seed (public, NOT production credentials).
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

    def test_sign_update_fixture_accepted(self):
        target = _write(self.root / "probe.bin", self.PROBE_BYTES)
        result = self._verify(
            public_key=self.PROBE_PUBLIC_KEY, path=target,
            signature=self.PROBE_SIGNATURE,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

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

    def test_malformed_inputs_fail(self):
        target = _write(self.root / "probe.bin", self.PROBE_BYTES)
        bad_key = self._verify(
            public_key="not-base64!!", path=target, signature=self.PROBE_SIGNATURE,
        )
        self.assertEqual(bad_key.returncode, 2)
        missing = self._verify(
            public_key=self.PROBE_PUBLIC_KEY, path=self.root / "missing.bin",
            signature=self.PROBE_SIGNATURE,
        )
        self.assertEqual(missing.returncode, 2)

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
