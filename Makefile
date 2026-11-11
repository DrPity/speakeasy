.PHONY: build test check app icon clean

# Build all targets: the library, the executable and the test bundle.
build:
	./scripts/swiftw build -c release

# Execute the test suite (scripts/test.sh covers the Command-Line-Tools-only quirks).
test:
	./scripts/test.sh

# Build and test together — what CI executes, and the thing to run before pushing.
check: build test

# Package the .app bundle and apply a code signature.
app:
	bash build.sh

# Regenerate Resources/AppIcon.icns from Resources/AppIcon.svg.
icon:
	./scripts/make-icon.sh

clean:
	swift package clean
	rm -rf Speakeasy.app
