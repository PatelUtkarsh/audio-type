# AudioType Makefile
# Voice-to-text macOS application using Groq API

.PHONY: all build clean run app dev lint format help

# Default target
all: build app

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
	@cp Resources/Info.plist AudioType.app/Contents/Info.plist
	@cp Resources/AppIcon.icns AudioType.app/Contents/Resources/
	@# Sign the bundle
	@codesign --force --deep --sign - AudioType.app 2>/dev/null || true
	@echo "App bundle created: AudioType.app"

# Run the app
run: app
	@echo "Starting AudioType..."
	@open AudioType.app

# Dev: kill, reset permissions, rebuild, install, and launch
dev: 
	@echo "Stopping AudioType..."
	@pkill -f AudioType 2>/dev/null || true
	@sleep 1
	@echo "Resetting Accessibility permission..."
	@tccutil reset Accessibility com.audiotype.app 2>/dev/null || true
	@$(MAKE) app
	@echo "Installing to /Applications..."
	@rm -rf /Applications/AudioType.app
	@cp -R AudioType.app /Applications/
	@echo "Launching..."
	@open /Applications/AudioType.app

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf .build
	@rm -rf AudioType.app
	@echo "Clean complete"

# Lint Swift code using swiftlint (if installed)
lint:
	@echo "Linting Swift code..."
	@if command -v swiftlint &> /dev/null; then \
		swiftlint lint --path AudioType; \
	else \
		echo "swiftlint not installed. Install with: brew install swiftlint"; \
	fi

# Format Swift code using swift-format (if installed)
format:
	@echo "Formatting Swift code..."
	@if command -v swift-format &> /dev/null; then \
		swift-format -i -r AudioType; \
	else \
		echo "swift-format not installed. Install with: brew install swift-format"; \
	fi

# Install development dependencies
setup:
	@echo "Installing development dependencies..."
	@brew install swiftlint swift-format || true
	@echo "Setup complete"

# Show help
help:
	@echo "AudioType Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all          Build everything (default)"
	@echo "  build        Build Swift app"
	@echo "  release      Build release version"
	@echo "  app          Create AudioType.app bundle"
	@echo "  run          Build and run the app"
	@echo "  dev          Kill, reset permissions, rebuild, install, launch"
	@echo "  clean        Remove all build artifacts"
	@echo "  lint         Lint Swift code with swiftlint"
	@echo "  format       Format Swift code with swift-format"
	@echo "  setup        Install development dependencies"
	@echo "  help         Show this help message"
