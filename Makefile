.PHONY: build release test install uninstall clean help
.PHONY: release-all release-macos release-linux release-windows

PREFIX ?= ~/.local
DIST ?= dist

build:
	zig build

release:
	zig build -Doptimize=ReleaseFast

test:
	zig build test

install: release
	mkdir -p $(PREFIX)/bin
	cp ./zig-out/bin/gwa $(PREFIX)/bin/
	@if [ "$$(uname)" = "Darwin" ]; then codesign -s - -f $(PREFIX)/bin/gwa 2>/dev/null || true; fi

uninstall:
	rm -f $(PREFIX)/bin/gwa

clean:
	rm -rf zig-out .zig-cache $(DIST)

run:
	zig build run -- $(ARGS)

# Cross-compilation targets
release-macos: release-macos-arm64 release-macos-x64

release-macos-arm64:
	zig build -Doptimize=ReleaseFast -Dtarget=aarch64-macos
	mkdir -p $(DIST)/macos-arm64
	cp ./zig-out/bin/gwa $(DIST)/macos-arm64/

release-macos-x64:
	zig build -Doptimize=ReleaseFast -Dtarget=x86_64-macos
	mkdir -p $(DIST)/macos-x64
	cp ./zig-out/bin/gwa $(DIST)/macos-x64/

release-linux: release-linux-arm64 release-linux-x64

release-linux-arm64:
	zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux
	mkdir -p $(DIST)/linux-arm64
	cp ./zig-out/bin/gwa $(DIST)/linux-arm64/

release-linux-x64:
	zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux
	mkdir -p $(DIST)/linux-x64
	cp ./zig-out/bin/gwa $(DIST)/linux-x64/

release-windows: release-windows-x64

release-windows-x64:
	zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows
	mkdir -p $(DIST)/windows-x64
	cp ./zig-out/bin/gwa.exe $(DIST)/windows-x64/

release-all: release-macos release-linux release-windows
	@echo "All platforms built in $(DIST)/"
	@ls -la $(DIST)/*/

help:
	@echo "gwa - Git Worktree for AI"
	@echo ""
	@echo "Usage:"
	@echo "  make build            Build debug version (native)"
	@echo "  make release          Build optimized release (native)"
	@echo "  make test             Run tests"
	@echo "  make install          Install to PREFIX (default: ~/.local)"
	@echo "  make uninstall        Remove from PREFIX"
	@echo "  make clean            Remove build artifacts"
	@echo "  make run ARGS=        Run with arguments"
	@echo ""
	@echo "Cross-compilation:"
	@echo "  make release-macos    Build for macOS (arm64 + x64)"
	@echo "  make release-linux    Build for Linux (arm64 + x64)"
	@echo "  make release-windows  Build for Windows (x64)"
	@echo "  make release-all      Build for all platforms"
	@echo ""
	@echo "Examples:"
	@echo "  make install PREFIX=/usr/local"
	@echo "  make run ARGS='list'"
	@echo "  make release-all      # outputs to dist/"
