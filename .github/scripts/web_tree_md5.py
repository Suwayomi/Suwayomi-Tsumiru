#!/usr/bin/env python3
import argparse
import hashlib
import os
from pathlib import Path


def tree_md5(directory: Path) -> str:
    files = [
        Path(root) / name
        for root, _, names in os.walk(directory, followlinks=True)
        for name in names
        if (Path(root) / name).is_file()
    ]
    # Kotlin sorts full paths by UTF-16 code units; the root prefix is shared.
    files.sort(key=lambda path: str(path).encode("utf-16-be", "surrogatepass"))
    digest = hashlib.md5()
    for path in files:
        file_digest = hashlib.md5()
        with path.open("rb") as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b""):
                file_digest.update(chunk)
        digest.update(file_digest.hexdigest().encode("utf-8"))
    return digest.hexdigest()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Compute the Suwayomi web tree MD5.")
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    if not args.directory.is_dir():
        parser.error(f"not a directory: {args.directory}")
    print(tree_md5(args.directory))
