#!/usr/bin/env bash
# Usage: tool/add_metainfo_release.sh [--check] [YYYY-MM-DD]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' "$ROOT/pubspec.yaml")"
FILES=(
  "$ROOT/flatpak/app.tsumiru.Tsumiru.metainfo.xml"
  "$ROOT/flatpak/io.github.aaronbamblett.tsumiru.metainfo.xml"
)

if [[ -z "$VERSION" ]]; then
  echo "could not read version from $ROOT/pubspec.yaml" >&2
  exit 1
fi

if [[ "${1:-}" == "--check" ]]; then
  failed=0
  for f in "${FILES[@]}"; do
    newest="$(grep -m1 '<release ' "$f" | sed -n 's/.*version="\([^"]*\)".*/\1/p')"
    if [[ "$newest" != "$VERSION" ]]; then
      echo "$f: newest release is $newest, pubspec is $VERSION. Run tool/add_metainfo_release.sh <release date> and commit." >&2
      failed=1
    fi
  done
  exit "$failed"
fi

DATE="${1:-$(date -u +%F)}"

for f in "${FILES[@]}"; do
  newest="$(grep -m1 '<release ' "$f" | sed -n 's/.*version="\([^"]*\)".*/\1/p')"
  if [[ "$newest" == "$VERSION" ]]; then
    continue
  fi
  VERSION="$VERSION" DATE="$DATE" perl -0pi -e \
    's|<releases>|<releases>\n    <release version="$ENV{VERSION}" date="$ENV{DATE}">\n      <url type="details">https://github.com/Suwayomi/Suwayomi-Tsumiru/releases/tag/v$ENV{VERSION}</url>\n    </release>|' \
    "$f"
done

exit 0
