# Panda Runner — developer shortcuts.
# `make` alone runs the full check suite.

FLUTTER ?= flutter
BASE_HREF ?= /

.PHONY: help deps check analyze test format web web-pages macos ios android windows native-platforms clean run

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

deps: ## Fetch Flutter packages
	$(FLUTTER) pub get

native-platforms: ## Generate and configure Android/Windows runners with Flutter GPU enabled
	$(FLUTTER) create . --platforms=ios,macos,web,android,windows --project-name panda_runner --org dev.pandarunner
	python3 scripts/configure_native_platforms.py

analyze: ## Static analysis
	$(FLUTTER) analyze --no-fatal-infos

test: ## Unit tests
	$(FLUTTER) test

format: ## Format Dart sources
	dart format lib test

web: ## Production web build (serve build/web)
	$(FLUTTER) build web --release --base-href $(BASE_HREF)

macos: ## Production macOS build
	$(FLUTTER) build macos --release

ios: ## iOS build (requires signing for devices)
	$(FLUTTER) build ios --release --enable-flutter-gpu

android: native-platforms deps ## Production per-ABI Android APKs (requires Android SDK/JDK)
	$(FLUTTER) build apk --release --split-per-abi

windows: native-platforms deps ## Production Windows build (Windows + Visual Studio C++ required)
	$(FLUTTER) build windows --release

run: ## Run on Chrome
	$(FLUTTER) run -d chrome

check: deps analyze test web ## deps + analyze + test + web build

clean: ## Remove build output
	$(FLUTTER) clean
