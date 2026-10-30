#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $# -gt 0 ]] || fail 'Usage: sign-android-apks.sh <apk>...'
for variable in OLD_KEYSTORE OLD_KEYSTORE_PASSWORD OLD_KEY_ALIAS OLD_KEY_PASSWORD \
  NEW_KEYSTORE NEW_KEYSTORE_PASSWORD NEW_KEY_ALIAS NEW_KEY_PASSWORD \
  SIGNING_LINEAGE OLD_CERT_SHA256 NEW_CERT_SHA256; do
  [[ -n ${!variable:-} ]] || fail "Missing environment variable: $variable"
done
for variable in OLD_CERT_SHA256 NEW_CERT_SHA256; do
  [[ ${!variable} =~ ^[0-9a-f]{64}$ ]] || fail "$variable must be 64 lowercase hex characters"
done

if [[ -z ${APKSIGNER:-} ]]; then
  APKSIGNER=apksigner
  if [[ -n ${ANDROID_HOME:-} && -d $ANDROID_HOME/build-tools ]]; then
    candidates=()
    for candidate in "$ANDROID_HOME"/build-tools/*/apksigner; do
      [[ ! -x $candidate ]] || candidates+=("$candidate")
    done
    if [[ ${#candidates[@]} -gt 0 ]]; then
      APKSIGNER=$(printf '%s\n' "${candidates[@]}" | sort -V | tail -n 1)
    fi
  fi
fi
command -v "$APKSIGNER" >/dev/null || fail "apksigner not found: $APKSIGNER"

require_line() {
  local output=$1 expected=$2
  grep -Fxq -- "$expected" <<< "$output" || fail "$apk: expected $expected"
}

verify_apk() {
  local apk=$1 old_output new_output lineage_output
  if ! old_output=$("$APKSIGNER" verify --max-sdk-version 27 --print-certs -v "$apk" 2>&1); then
    printf '%s\n' "$old_output" >&2
    fail "$apk: verification for API <=27 failed"
  fi
  printf '%s\n' "$old_output"
  require_line "$old_output" 'Number of signers: 1'
  require_line "$old_output" "Signer #1 certificate SHA-256 digest: $OLD_CERT_SHA256"
  require_line "$old_output" 'Verified using v2 scheme (APK Signature Scheme v2): true'

  if ! new_output=$("$APKSIGNER" verify --min-sdk-version 28 --print-certs -v "$apk" 2>&1); then
    printf '%s\n' "$new_output" >&2
    fail "$apk: verification for API >=28 failed"
  fi
  printf '%s\n' "$new_output"
  require_line "$new_output" 'Number of signers: 1'
  require_line "$new_output" "Signer #1 certificate SHA-256 digest: $NEW_CERT_SHA256"
  require_line "$new_output" 'Verified using v3 scheme (APK Signature Scheme v3): true'
  for output in "$old_output" "$new_output"; do
    require_line "$output" 'Verified using v1 scheme (JAR signing): false'
    require_line "$output" 'Verified using v4 scheme (APK Signature Scheme v4): false'
  done

  if ! lineage_output=$("$APKSIGNER" lineage --in "$apk" --print-certs -v 2>&1); then
    printf '%s\n' "$lineage_output" >&2
    fail "$apk: reading signing lineage failed"
  fi
  printf '%s\n' "$lineage_output"
  for fingerprint in "$OLD_CERT_SHA256" "$NEW_CERT_SHA256"; do
    grep -Eq "^Signer #[0-9]+ in lineage certificate SHA-256 digest: $fingerprint$" \
      <<< "$lineage_output" || fail "$apk: lineage missing certificate $fingerprint"
  done
  printf 'PASS: %s has old-key v2, new-key v3, and both lineage certificates\n' "$apk"
}

for apk in "$@"; do
  [[ -f $apk ]] || fail "APK not found: $apk"
  "$APKSIGNER" sign \
    --ks "$OLD_KEYSTORE" --ks-key-alias "$OLD_KEY_ALIAS" \
    --ks-pass env:OLD_KEYSTORE_PASSWORD --key-pass env:OLD_KEY_PASSWORD \
    --next-signer --ks "$NEW_KEYSTORE" --ks-key-alias "$NEW_KEY_ALIAS" \
    --ks-pass env:NEW_KEYSTORE_PASSWORD --key-pass env:NEW_KEY_PASSWORD \
    --lineage "$SIGNING_LINEAGE" --rotation-min-sdk-version 28 \
    --v1-signing-enabled false --v2-signing-enabled true \
    --v3-signing-enabled true --v4-signing-enabled false "$apk"
  verify_apk "$apk"
done
