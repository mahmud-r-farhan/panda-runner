# Panda Runner — developer shortcuts.
# `make` alone runs the full check suite.

FLUTTER ?= flutter
BASE_HREF ?= /

.PHONY: help deps check analyze test format web web-pages macos ios clean run

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

deps: ## Fetch Flutter packages
	$(FLUTTER) pub get

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

run: ## Run on Chrome
	$(FLUTTER) run -d chrome

check: deps analyze test web ## deps + analyze + test + web build

clean: ## Remove build output
	$(FLUTTER) clean
