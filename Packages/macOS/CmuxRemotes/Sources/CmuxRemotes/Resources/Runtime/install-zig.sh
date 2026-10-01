#!/bin/sh
set -eu
case "$(uname -m)" in
    x86_64) platform=x86_64-linux; digest=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00 ;;
    aarch64) platform=aarch64-linux; digest=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17 ;;
    *) echo 'Unsupported build architecture' >&2; exit 1 ;;
esac
curl --fail --location --retry 3 "https://ziglang.org/download/0.16.0/zig-${platform}-0.16.0.tar.xz" -o /tmp/zig.tar.xz
echo "$digest  /tmp/zig.tar.xz" | sha256sum --check --strict
mkdir -p /opt/zig
tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1
rm /tmp/zig.tar.xz
