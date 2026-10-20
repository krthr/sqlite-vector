#!/bin/sh
set -eu

fail() { printf 'sqlite-vector: %s\n' "$*" >&2; exit 1; }

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=1.1.2
os=$(uname -s)
arch=$(uname -m)
case "$arch" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=x86_64 ;;
  *) fail "unsupported architecture: $arch" ;;
esac
case "$os" in
  Darwin) platform=macos-$arch; library=vector.dylib ;;
  Linux)
    libc=$(ldd --version 2>&1 || :)
    case "$libc" in
      *musl*) platform=linux-musl-$arch ;;
      *GLIBC*|*"GNU libc"*) platform=linux-$arch ;;
      *) fail "cannot identify Linux libc; expected glibc or musl (ldd --version)" ;;
    esac
    library=vector.so
    ;;
  *) fail "unsupported operating system: $os" ;;
esac

asset=vector-$platform-$version.tar.gz
expected=
while read -r checksum filename; do
  if [ "$filename" = "$asset" ]; then expected=$checksum; break; fi
done < "$root/scripts/checksums.sha256"
[ -n "$expected" ] || fail "no checksum for $asset"

mkdir -p "$root/native"
temp=$(mktemp -d "$root/native/.install.XXXXXX")
trap 'rm -rf "$temp"' 0
trap 'exit 1' HUP INT TERM
archive=$temp/$asset
url=https://github.com/sqliteai/sqlite-vector/releases/download/$version/$asset
curl --fail --location --silent --show-error --output "$archive" "$url" ||
  fail "download failed: $url"
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$archive")
elif command -v shasum >/dev/null 2>&1; then
  actual=$(shasum -a 256 "$archive")
else
  fail "install sha256sum or shasum to verify the download"
fi
[ "${actual%% *}" = "$expected" ] || fail "SHA-256 mismatch for $asset"

tar -xzf "$archive" -C "$temp" "./$library" ||
  fail "could not extract $library from $asset"
[ -f "$temp/$library" ] && [ ! -L "$temp/$library" ] ||
  fail "archive did not contain a regular $library"
mkdir -p "$root/native/$platform"
mv -f "$temp/$library" "$root/native/$platform/$library"
printf 'Installed SQLite Vector %s for %s\n' "$version" "$platform"
