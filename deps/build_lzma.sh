#!/bin/bash
set -e

# ============================================================================
# liblzma (xz-utils) Build Script for iOS arm64
# ============================================================================
# Cross-compiles liblzma as a static library so the app can decompress
# .tar.xz mini-rootfs archives (iSH-AOK ships .tar.xz tarballs).
#
# Usage:
#   ./build_lzma.sh [clean]
#
# Output:
#   deps/libs/liblzma.a
#   deps/lzma-build/include/lzma.h
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XZ_VERSION="5.6.3"
XZ_TARBALL="xz-${XZ_VERSION}.tar.gz"
XZ_SRC_DIR="$SCRIPT_DIR/xz-${XZ_VERSION}"
XZ_BUILD_DIR="$SCRIPT_DIR/lzma-build"
OUTPUT_LIBS="$SCRIPT_DIR/libs"
OUTPUT_INCLUDE="$SCRIPT_DIR/include"

IOS_DEPLOYMENT_TARGET="14.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; exit 1; }

# ============================================================================
# Clean
# ============================================================================
if [ "$1" == "clean" ]; then
    log_info "Cleaning liblzma build artifacts..."
    rm -rf "$XZ_SRC_DIR" "$XZ_BUILD_DIR" "$OUTPUT_LIBS/liblzma.a"
    log_success "Clean completed"
    exit 0
fi

# ============================================================================
# Download source
# ============================================================================
if [ ! -d "$XZ_SRC_DIR" ]; then
    log_info "Downloading xz-utils ${XZ_VERSION}..."
    cd "$SCRIPT_DIR"
    if [ ! -f "$XZ_TARBALL" ]; then
        curl -fL -o "$XZ_TARBALL" \
            "https://tukaani.org/xz/xz-${XZ_VERSION}.tar.gz" || \
            curl -fL -o "$XZ_TARBALL" \
            "https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.gz"
    fi
    tar xzf "$XZ_TARBALL"
    rm -f "$XZ_TARBALL"
    log_success "xz source extracted"
else
    log_info "xz source already present, skipping download"
fi

# ============================================================================
# Cross-compile for iOS arm64
# ============================================================================
log_info "Configuring liblzma for iOS arm64..."

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC="$(xcrun --sdk iphoneos -f clang)"

export CC
export CFLAGS="-arch arm64 -miphoneos-version-min=$IOS_DEPLOYMENT_TARGET -isysroot $IOS_SDK -fembed-bitcode -Oz -fPIC -Wno-implicit-function-declaration"
export LDFLAGS="-arch arm64 -miphoneos-version-min=$IOS_DEPLOYMENT_TARGET -isysroot $IOS_SDK"

cd "$XZ_SRC_DIR"

# Build only liblzma (no xz/gzip CLI tools, no docs). Pure C, no deps.
./configure \
    --prefix="$XZ_BUILD_DIR" \
    --host=aarch64-apple-darwin \
    --disable-shared \
    --enable-static \
    --disable-xzdec \
    --disable-lzmadec \
    --disable-xz \
    --disable-lzmainfo \
    --disable-scripts \
    --disable-doc \
    --disable-nls \
    --with-pic

log_info "Building liblzma..."
make -j$(sysctl -n hw.ncpu)

# install copies headers + the static lib into XZ_BUILD_DIR
make install

cd "$SCRIPT_DIR"

# ============================================================================
# Copy artifacts into deps/libs and deps/include
# ============================================================================
mkdir -p "$OUTPUT_LIBS" "$OUTPUT_INCLUDE"
cp "$XZ_BUILD_DIR/lib/liblzma.a" "$OUTPUT_LIBS/liblzma.a"
cp -R "$XZ_BUILD_DIR/include/lzma" "$OUTPUT_INCLUDE/" 2>/dev/null || true
cp "$XZ_BUILD_DIR/include/lzma.h" "$OUTPUT_INCLUDE/" 2>/dev/null || true

# ============================================================================
# Verify
# ============================================================================
if [ -f "$OUTPUT_LIBS/liblzma.a" ]; then
    log_success "liblzma built successfully"
    echo ""
    echo "  Static library: $OUTPUT_LIBS/liblzma.a"
    echo "  Headers:        $OUTPUT_INCLUDE/lzma.h"
    echo ""
    file "$OUTPUT_LIBS/liblzma.a"
else
    log_error "Build failed — liblzma.a not found"
fi
