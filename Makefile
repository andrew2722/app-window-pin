.PHONY: build app assets run release release-check clean logs

# Compile only — fastest feedback loop while editing.
build:
	swift build

# Redraw the app icon and README figures from Scripts/make-assets.swift.
assets:
	./Scripts/make-assets.sh

# Assemble the signed .app bundle that macOS will grant Accessibility to.
app:
	./Scripts/build-app.sh

run: app
	open build/WindowPin.app

# Build, verify, notarize and publish. Pass VERSION=1.0.1.
release:
	./Scripts/release.sh $(VERSION)

# Same checks, publishes nothing.
release-check:
	./Scripts/release.sh $(VERSION) --dry-run

clean:
	rm -rf .build build

# Live debug output from the running app.
logs:
	log stream --level debug --predicate 'subsystem == "com.windowpin.app"'
