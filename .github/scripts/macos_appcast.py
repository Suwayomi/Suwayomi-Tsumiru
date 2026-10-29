#!/usr/bin/env python3
"""Generate the single-item macOS Sparkle appcast for a tagged release."""

import argparse
import base64
import binascii
import email.utils
import os
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ENCLOSURE_TYPE = "application/octet-stream"
ENCLOSURE_OS = "macos"

VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
BUILD_RE = re.compile(r"^[0-9]+$")
MIN_OS_RE = re.compile(r"^\d+(?:\.\d+){0,2}$")
TAG_RE = re.compile(r"^v(\d+\.\d+\.\d+)$")


def validate_signature(raw: str) -> bytes:
    try:
        decoded = base64.b64decode(raw, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError("signature is not valid base64")
    if len(decoded) != 64:
        raise ValueError(f"signature decodes to {len(decoded)} bytes, expected 64")
    return decoded


def validate_https_url(raw: str, what: str) -> str:
    if not raw:
        raise ValueError(f"{what} is empty")
    try:
        raw.encode("ascii")
    except UnicodeEncodeError:
        raise ValueError(f"{what} must be ASCII")
    if any(char.isspace() or ord(char) < 0x20 or ord(char) == 0x7F for char in raw):
        raise ValueError(f"{what} contains whitespace or control characters")
    parsed = urllib.parse.urlsplit(raw)
    if parsed.scheme.lower() != "https":
        raise ValueError(f"{what} must use https")
    if not parsed.hostname:
        raise ValueError(f"{what} has no host")
    return raw


def validate_release(version: str, build: str, tag: str, min_os: str) -> None:
    if not VERSION_RE.match(version):
        raise ValueError(f"version {version!r} is not short X.Y.Z")
    if not BUILD_RE.match(build):
        raise ValueError(f"build {build!r} is not numeric")
    match = TAG_RE.match(tag)
    if not match or match.group(1) != version:
        raise ValueError(f"tag {tag!r} does not match version {version!r}")
    if not MIN_OS_RE.match(min_os):
        raise ValueError(f"minimum OS {min_os!r} is not numeric dotted")


def _tag_url(repo: str, tag: str) -> str:
    return f"https://github.com/{repo}/releases/tag/{tag}"


def generate_appcast(
    *,
    version: str,
    build: str,
    tag: str,
    repo: str,
    archive: Path,
    signature: str,
    min_os: str,
    download_url: str,
    pubdate: str | None = None,
) -> bytes:
    validate_release(version, build, tag, min_os)
    validate_https_url(download_url, "download URL")
    validate_signature(signature)
    if not archive.is_file():
        raise ValueError(f"archive not found: {archive}")
    size = archive.stat().st_size
    if size <= 0:
        raise ValueError(f"archive is empty: {archive}")
    if pubdate is None:
        pubdate = email.utils.formatdate(archive.stat().st_mtime, usegmt=True)
    elif email.utils.parsedate_to_datetime(pubdate) is None:
        raise ValueError(f"pubdate {pubdate!r} is not RFC 2822")

    ET.register_namespace("sparkle", SPARKLE_NS)

    def qname(name: str) -> str:
        return f"{{{SPARKLE_NS}}}{name}"

    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Tsumiru"
    ET.SubElement(channel, "link").text = f"https://github.com/{repo}/releases"
    ET.SubElement(channel, "description").text = "Tsumiru releases for macOS"
    ET.SubElement(channel, "language").text = "en"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Version {version} ({build})"
    ET.SubElement(item, "link").text = _tag_url(repo, tag)
    ET.SubElement(item, qname("version")).text = build
    ET.SubElement(item, qname("shortVersionString")).text = version
    ET.SubElement(item, "pubDate").text = pubdate
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": download_url,
            "length": str(size),
            "type": ENCLOSURE_TYPE,
            qname("edSignature"): signature,
            qname("os"): ENCLOSURE_OS,
        },
    )
    ET.SubElement(item, qname("minimumSystemVersion")).text = min_os

    tree = ET.ElementTree(rss)
    ET.indent(tree)
    return ET.tostring(tree.getroot(), encoding="utf-8", xml_declaration=True)


def write_output(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_bytes(content)
    os.replace(tmp, path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate the macOS Sparkle appcast.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    gen = sub.add_parser("generate", help="write dist/appcast.xml for a tagged release")
    gen.add_argument("--version", required=True, help="short version, e.g. 1.6.2")
    gen.add_argument("--build", required=True, help="CFBundleVersion, e.g. 5003")
    gen.add_argument("--tag", required=True, help="release tag, e.g. v1.6.2")
    gen.add_argument("--repo", default="Suwayomi/Suwayomi-Tsumiru")
    gen.add_argument("--zip", type=Path, required=True, help="signed release archive")
    gen.add_argument("--signature", required=True, help="base64 Ed25519 signature of the archive")
    gen.add_argument("--min-os", required=True, help="minimum macOS version, e.g. 12.0")
    gen.add_argument("--download-url", required=True, help="exact tagged asset URL of the archive")
    gen.add_argument("--pubdate", default=None, help="RFC 2822 date (default: archive mtime in UTC)")
    gen.add_argument("--output", type=Path, required=True, help="appcast path, e.g. dist/appcast.xml")

    meta = sub.add_parser(
        "validate-metadata",
        help="check built Info.plist version/build/min-OS without signing",
    )
    meta.add_argument("--version", required=True, help="short version, e.g. 1.6.2")
    meta.add_argument("--build", required=True, help="CFBundleVersion, e.g. 5003")
    meta.add_argument("--tag", required=True, help="release tag, e.g. v1.6.2")
    meta.add_argument("--min-os", required=True, help="minimum macOS version, e.g. 12.0")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "validate-metadata":
            validate_release(args.version, args.build, args.tag, args.min_os)
            print(f"metadata valid: {args.version} ({args.build}) tag {args.tag}")
            return 0
        content = generate_appcast(
            version=args.version,
            build=args.build,
            tag=args.tag,
            repo=args.repo,
            archive=args.zip,
            signature=args.signature,
            min_os=args.min_os,
            download_url=args.download_url,
            pubdate=args.pubdate,
        )
        write_output(args.output, content)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    print(f"appcast written to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
