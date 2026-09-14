VERSION ?= 0.2.1

.PHONY: gen build test run clean release

# Regenerate OpossumDesktop.xcodeproj from project.yml (requires `brew install xcodegen`).
gen:
	xcodegen generate

# Run the OpossumKit unit test suite (fast, no Xcode project needed).
test:
	cd OpossumKit && swift test

# Build the app in Debug via xcodebuild (regenerates the project first).
build: gen
	xcodebuild -project OpossumDesktop.xcodeproj -scheme OpossumDesktop -configuration Debug -destination 'platform=macOS' build

# Build and launch the app.
run: build
	open "$$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -iname 'OpossumDesktop-*' -print -quit)/Build/Products/Debug/Opossum Desktop.app"

clean:
	rm -rf OpossumDesktop.xcodeproj OpossumKit/.build build dist

# Build an unsigned Release .app, zip it (ditto, so it stays double-clickable and Gatekeeper-sane
# to the extent an unsigned app can be), and write its sha256 for the Homebrew cask manifest.
# CURRENT_PROJECT_VERSION (CFBundleVersion) is stamped with the current time rather than left
# static: macOS's icon/LaunchServices caches key off bundle identity + version, so reinstalling
# over the same path with an unchanged version can leave a stale icon in the Dock/Quick Look
# even though the files on disk are current.
# Usage: make release VERSION=0.2.0
release: gen
	xcodebuild -project OpossumDesktop.xcodeproj -scheme OpossumDesktop -configuration Release \
		-destination 'platform=macOS' -derivedDataPath build/DerivedData \
		MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(shell date +%s) build
	mkdir -p dist
	ditto -c -k --sequesterRsrc --keepParent \
		"build/DerivedData/Build/Products/Release/Opossum Desktop.app" \
		"dist/OpossumDesktop-$(VERSION).zip"
	shasum -a 256 "dist/OpossumDesktop-$(VERSION).zip" | tee "dist/OpossumDesktop-$(VERSION).zip.sha256"
	@echo "Built dist/OpossumDesktop-$(VERSION).zip"
