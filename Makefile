APP_NAME   := SpanWall
SOURCES    := Sources/$(APP_NAME)/*.swift
BUILD_DIR  := .build
BIN        := $(BUILD_DIR)/$(APP_NAME)
APP        := $(BUILD_DIR)/$(APP_NAME).app
FRAMEWORKS := -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
              -framework AVFoundation -framework CoreVideo -framework CoreMedia -framework CoreImage \
              -framework ServiceManagement -framework SwiftUI

# NOTE: SwiftPM (`swift build`) is broken in this machine's Command Line Tools
# (swift-package crashes on a missing framework), so we compile directly with
# swiftc. Package.swift is kept for when full Xcode is installed.
#
# IMPORTANT: run SpanWall as the .app bundle (`make run`) — video playback via
# AVSampleBufferDisplayLayer is validated launched through LaunchServices.

.PHONY: build app run release clean

build:
	@mkdir -p $(BUILD_DIR)
	swiftc -o $(BIN) $(SOURCES) $(FRAMEWORKS)

# Assemble a proper .app bundle around the built binary.
app: build
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp $(BIN) "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Info.plist "$(APP)/Contents/Info.plist"
	cp AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	@echo "Built $(APP)"

# Build the bundle and launch it via LaunchServices.
run: app
	open "$(APP)"

release:
	@mkdir -p $(BUILD_DIR)
	swiftc -O -o $(BIN) $(SOURCES) $(FRAMEWORKS)

clean:
	rm -rf $(BUILD_DIR)
