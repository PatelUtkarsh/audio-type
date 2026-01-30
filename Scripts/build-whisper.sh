#!/bin/bash
#
# Build whisper.cpp with Metal support
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHISPER_DIR="$PROJECT_DIR/whisper.cpp"

echo "Building whisper.cpp..."
echo "Project directory: $PROJECT_DIR"
echo "Whisper directory: $WHISPER_DIR"

cd "$WHISPER_DIR"

# Clean previous build
rm -rf build

# Create build directory
mkdir -p build
cd build

# Configure with CMake
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_METAL=ON \
    -DWHISPER_COREML=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0

# Build
cmake --build . --config Release -j$(sysctl -n hw.ncpu)

echo ""
echo "Build complete!"
echo "Libraries:"
ls -la src/libwhisper.a 2>/dev/null || echo "  libwhisper.a not found in src/"
ls -la libwhisper.a 2>/dev/null || echo "  libwhisper.a not found in build root"
ls -la ggml/src/libggml.a 2>/dev/null || echo "  libggml.a not found"

echo ""
echo "To use with Swift Package Manager, libraries are at:"
echo "  $WHISPER_DIR/build/src/libwhisper.a"
echo "  $WHISPER_DIR/build/ggml/src/libggml.a"
