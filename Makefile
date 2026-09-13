.PHONY: gen build test run clean

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
	rm -rf OpossumDesktop.xcodeproj OpossumKit/.build
