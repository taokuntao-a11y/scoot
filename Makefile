.PHONY: build test app run clean cli install-cli

build: test
	swift build -c release

test:
	swift test

app:
	bash scripts/build-app.sh

run: app
	-pkill -f "Scoot.app/Contents/MacOS/Scoot" 2>/dev/null || true
	open dist/Scoot.app

# Builds the `scoot` command-line interface (release).
cli:
	swift build -c release
	@echo "Binary: $$(swift build -c release --show-bin-path)/ScootCLI"

# Builds and installs the `scoot` CLI onto PATH as $(HOME)/.local/bin/scoot.
install-cli: cli
	mkdir -p $(HOME)/.local/bin
	cp .build/release/ScootCLI $(HOME)/.local/bin/scoot
	chmod +x $(HOME)/.local/bin/scoot
	@echo "Installed: $(HOME)/.local/bin/scoot"

clean:
	rm -rf .build dist
