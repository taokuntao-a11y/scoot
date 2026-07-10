.PHONY: build test app run clean

build: test
	swift build -c release

test:
	swift test

app:
	bash scripts/build-app.sh

run: app
	-pkill -f "Scoot.app/Contents/MacOS/Scoot" 2>/dev/null || true
	open dist/Scoot.app

clean:
	rm -rf .build dist
