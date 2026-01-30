# AudioType Makefile
# Voice-to-text macOS application using whisper.cpp

.PHONY: all build clean run app whisper model lint format help

# Default target
all: whisper build app

# Build whisper.cpp with Metal support
whisper:
	@echo "Building whisper.cpp..."
	@cd whisper.cpp && \
		mkdir -p build && \
		cd build && \
		cmake .. \
			-DCMAKE_BUILD_TYPE=Release \
			-DGGML_METAL=ON \
			-DWHISPER_BUILD_EXAMPLES=ON && \
		cmake --build . --config Release -j$$(sysctl -n hw.ncpu)
	@echo "whisper.cpp built successfully"

# Build Swift app
build:
	@echo "Building AudioType..."
	@swift build
	@echo "Build complete"

# Build release version
release:
	@echo "Building AudioType (release)..."
	@swift build -c release
	@echo "Release build complete"

# Create app bundle
app: build
	@echo "Creating app bundle..."
	@mkdir -p AudioType.app/Contents/MacOS AudioType.app/Contents/Resources
	@cp .build/debug/AudioType AudioType.app/Contents/MacOS/
	@cp whisper.cpp/build/bin/whisper-cli AudioType.app/Contents/MacOS/
	@# Copy dylibs
	@cp whisper.cpp/build/src/libwhisper.1.dylib AudioType.app/Contents/MacOS/
	@cp whisper.cpp/build/ggml/src/libggml.0.dylib AudioType.app/Contents/MacOS/
	@cp whisper.cpp/build/ggml/src/libggml-base.0.dylib AudioType.app/Contents/MacOS/
	@cp whisper.cpp/build/ggml/src/libggml-cpu.0.dylib AudioType.app/Contents/MacOS/
	@cp whisper.cpp/build/ggml/src/ggml-blas/libggml-blas.0.dylib AudioType.app/Contents/MacOS/
	@cp whisper.cpp/build/ggml/src/ggml-metal/libggml-metal.0.dylib AudioType.app/Contents/MacOS/
	@cp whisper.cpp/build/bin/ggml-metal.metal AudioType.app/Contents/MacOS/ 2>/dev/null || true
	@cp whisper.cpp/build/bin/ggml-common.h AudioType.app/Contents/MacOS/ 2>/dev/null || true
	@# Fix library paths to use @executable_path
	@install_name_tool -change @rpath/libwhisper.1.dylib @executable_path/libwhisper.1.dylib AudioType.app/Contents/MacOS/whisper-cli 2>/dev/null || true
	@install_name_tool -change @rpath/libggml.0.dylib @executable_path/libggml.0.dylib AudioType.app/Contents/MacOS/whisper-cli 2>/dev/null || true
	@install_name_tool -change @rpath/libggml-cpu.0.dylib @executable_path/libggml-cpu.0.dylib AudioType.app/Contents/MacOS/whisper-cli 2>/dev/null || true
	@install_name_tool -change @rpath/libggml-blas.0.dylib @executable_path/libggml-blas.0.dylib AudioType.app/Contents/MacOS/whisper-cli 2>/dev/null || true
	@install_name_tool -change @rpath/libggml-metal.0.dylib @executable_path/libggml-metal.0.dylib AudioType.app/Contents/MacOS/whisper-cli 2>/dev/null || true
	@install_name_tool -change @rpath/libggml-base.0.dylib @executable_path/libggml-base.0.dylib AudioType.app/Contents/MacOS/whisper-cli 2>/dev/null || true
	@# Fix dylib inter-dependencies
	@install_name_tool -change @rpath/libggml-base.0.dylib @executable_path/libggml-base.0.dylib AudioType.app/Contents/MacOS/libwhisper.1.dylib 2>/dev/null || true
	@install_name_tool -change @rpath/libggml.0.dylib @executable_path/libggml.0.dylib AudioType.app/Contents/MacOS/libwhisper.1.dylib 2>/dev/null || true
	@install_name_tool -change @rpath/libggml-base.0.dylib @executable_path/libggml-base.0.dylib AudioType.app/Contents/MacOS/libggml.0.dylib 2>/dev/null || true
	@install_name_tool -change @rpath/libggml-base.0.dylib @executable_path/libggml-base.0.dylib AudioType.app/Contents/MacOS/libggml-cpu.0.dylib 2>/dev/null || true
	@install_name_tool -change @rpath/libggml-base.0.dylib @executable_path/libggml-base.0.dylib AudioType.app/Contents/MacOS/libggml-blas.0.dylib 2>/dev/null || true
	@install_name_tool -change @rpath/libggml-base.0.dylib @executable_path/libggml-base.0.dylib AudioType.app/Contents/MacOS/libggml-metal.0.dylib 2>/dev/null || true
	@cp Resources/Info.plist AudioType.app/Contents/Info.plist
	@cp Resources/AppIcon.icns AudioType.app/Contents/Resources/
	@# Sign the bundle
	@codesign --force --deep --sign - AudioType.app 2>/dev/null || true
	@echo "App bundle created: AudioType.app"

# Download whisper model
model:
	@echo "Downloading whisper model (base.en)..."
	@./Scripts/download-model.sh base.en
	@echo "Model downloaded"

# Run the app
run: app
	@echo "Starting AudioType..."
	@open AudioType.app

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf .build
	@rm -rf AudioType.app
	@rm -rf whisper.cpp/build
	@echo "Clean complete"

# Clean only Swift build
clean-swift:
	@echo "Cleaning Swift build..."
	@rm -rf .build
	@rm -rf AudioType.app
	@echo "Swift clean complete"

# Lint Swift code using swiftlint (if installed)
lint:
	@echo "Linting Swift code..."
	@if command -v swiftlint &> /dev/null; then \
		swiftlint lint --path AudioType --path WhisperWrapper; \
	else \
		echo "swiftlint not installed. Install with: brew install swiftlint"; \
	fi

# Format Swift code using swift-format (if installed)
format:
	@echo "Formatting Swift code..."
	@if command -v swift-format &> /dev/null; then \
		swift-format -i -r AudioType WhisperWrapper; \
	else \
		echo "swift-format not installed. Install with: brew install swift-format"; \
	fi

# Install development dependencies
setup:
	@echo "Installing development dependencies..."
	@brew install cmake swiftlint swift-format || true
	@echo "Setup complete"

# Show help
help:
	@echo "AudioType Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all          Build everything (whisper + app)"
	@echo "  build        Build Swift app only"
	@echo "  release      Build release version"
	@echo "  whisper      Build whisper.cpp with Metal support"
	@echo "  app          Create AudioType.app bundle"
	@echo "  model        Download whisper base.en model"
	@echo "  run          Build and run the app"
	@echo "  clean        Remove all build artifacts"
	@echo "  clean-swift  Remove only Swift build artifacts"
	@echo "  lint         Lint Swift code with swiftlint"
	@echo "  format       Format Swift code with swift-format"
	@echo "  setup        Install development dependencies"
	@echo "  help         Show this help message"
