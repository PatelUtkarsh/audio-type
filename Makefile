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
	@cat > AudioType.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AudioType</string>
    <key>CFBundleIdentifier</key>
    <string>com.audiotype.app</string>
    <key>CFBundleName</key>
    <string>AudioType</string>
    <key>CFBundleDisplayName</key>
    <string>AudioType</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>AudioType needs microphone access to transcribe your speech.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
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
