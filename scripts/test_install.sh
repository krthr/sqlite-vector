#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' 0
trap 'exit 1' HUP INT TERM
project=$temp/project\ with\ spaces
mkdir -p "$project/scripts" "$temp/tools" "$temp/fixture"
cp "$root/scripts/install.sh" "$project/scripts/"
printf 'test extension\n' > "$temp/fixture/vector.dylib"
cp "$temp/fixture/vector.dylib" "$temp/fixture/vector.so"
printf 'do not install\n' > "$temp/fixture/unrelated"
tar -czf "$temp/fixture.tar.gz" -C "$temp/fixture" ./vector.dylib ./vector.so ./unrelated
if command -v sha256sum >/dev/null 2>&1; then
  checksum=$(sha256sum "$temp/fixture.tar.gz")
else
  checksum=$(shasum -a 256 "$temp/fixture.tar.gz")
fi
while read -r _ asset; do
  printf '%s  %s\n' "${checksum%% *}" "$asset"
done < "$root/scripts/checksums.sha256" > "$project/scripts/checksums.sha256"

cat > "$temp/tools/uname" <<'SH'
#!/bin/sh
case "$1" in -s) echo "$TEST_OS" ;; -m) echo "$TEST_ARCH" ;; esac
SH
cat > "$temp/tools/ldd" <<'SH'
#!/bin/sh
echo "$TEST_LIBC"
case "$TEST_LIBC" in *musl*) exit 1 ;; esac
SH
cat > "$temp/tools/curl" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output=$2; shift ;;
    https:*) url=$1 ;;
  esac
  shift
done
printf 'curl %s\n' "$url" >> "$TEST_LOG"
cp "$TEST_ARCHIVE" "$output"
case "$TEST_FAILURE" in
  download) exit 22 ;;
  checksum) printf 'corrupted' >> "$output" ;;
esac
SH
cat > "$temp/tools/tar" <<'SH'
#!/bin/sh
echo tar >> "$TEST_LOG"
[ "$TEST_FAILURE" != tar ] || exit 2
exec "$REAL_TAR" "$@"
SH
chmod +x "$temp/tools/"*
export REAL_TAR=$(command -v tar)
export PATH="$temp/tools:$PATH"
export TEST_ARCHIVE="$temp/fixture.tar.gz" TEST_LOG="$temp/log"
export TEST_OS TEST_ARCH TEST_LIBC TEST_FAILURE=

run_install() {
  : > "$TEST_LOG"
  sh "$project/scripts/install.sh" > "$temp/output" 2>&1
}
assert_clean() {
  if find "$project/native" -name '.install.*' -print | grep -q .; then
    echo "Installer left temporary files" >&2
    exit 1
  fi
}
expect_failure() {
  if run_install; then echo "Expected failure: $1" >&2; exit 1; fi
  grep -q "$1" "$temp/output" || { cat "$temp/output"; exit 1; }
  assert_clean
}

while read -r TEST_OS TEST_ARCH TEST_LIBC platform; do
  run_install || { cat "$temp/output"; exit 1; }
  case "$TEST_OS" in Darwin) library=vector.dylib ;; *) library=vector.so ;; esac
  cmp "$temp/fixture/$library" "$project/native/$platform/$library"
  grep -q "/1.1.2/vector-$platform-1.1.2.tar.gz" "$TEST_LOG"
  [ "$(find "$project/native/$platform" -type f | wc -l | tr -d ' ')" = 1 ]
  assert_clean
done <<'CASES'
Darwin arm64 unused macos-arm64
Darwin x86_64 unused macos-x86_64
Linux aarch64 GLIBC linux-arm64
Linux x86_64 GLIBC linux-x86_64
Linux aarch64 musl linux-musl-arm64
Linux x86_64 musl linux-musl-x86_64
CASES

TEST_OS=Darwin TEST_ARCH=arm64
run_install
cmp "$temp/fixture/vector.dylib" "$project/native/macos-arm64/vector.dylib"
assert_clean
TEST_ARCH=riscv64
expect_failure 'unsupported architecture'
TEST_ARCH=arm64 TEST_OS=FreeBSD
expect_failure 'unsupported operating system'
TEST_OS=Linux TEST_LIBC=unknown
expect_failure 'cannot identify Linux libc'

TEST_OS=Darwin
for TEST_FAILURE in download checksum tar; do
  case "$TEST_FAILURE" in
    download) message='download failed' ;;
    checksum) message='SHA-256 mismatch' ;;
    tar) message='could not extract' ;;
  esac
  expect_failure "$message"
  cmp "$temp/fixture/vector.dylib" "$project/native/macos-arm64/vector.dylib"
  if [ "$TEST_FAILURE" != tar ]; then
    if grep -q '^tar$' "$TEST_LOG"; then
      echo "Extracted before verifying download" >&2
      exit 1
    fi
  fi
done
rm "$project/native/macos-arm64/vector.dylib"
for TEST_FAILURE in download checksum tar; do
  if run_install; then echo "Expected fresh installation to fail" >&2; exit 1; fi
  [ ! -e "$project/native/macos-arm64/vector.dylib" ]
  assert_clean
done
printf 'Installer tests passed (six platforms, repeat install, unsupported hosts, and failure cleanup).\n'
