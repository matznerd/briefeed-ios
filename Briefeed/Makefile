# Briefeed iOS Project Makefile — Agent-Friendly Build Commands
#
# Usage:
#   make build         - Build for simulator
#   make test          - Run all tests
#   make test-unit     - Run unit tests only
#   make test-ui       - Run UI tests only
#   make run           - Build and launch on simulator
#   make clean         - Clean build artifacts
#   make install-tools - Install agent development tools

.PHONY: build test test-ui test-unit run clean install-tools lint help screenshot ui-tree tap radio-compile radio-golden radio-unit radio-ui radio-smoke sim-doctor sim-status

# ┌─────────────────────────────────────────────┐
# │  PROJECT CONFIGURATION                       │
# └─────────────────────────────────────────────┘
PROJECT = Briefeed.xcodeproj
SCHEME = Briefeed
SIMULATOR = iPhone 17
IOS_VERSION = 26.0.1
BUNDLE_ID = Matznerd.Briefeed
UNIT_TEST_TARGET = BriefeedTests
UI_TEST_TARGET = BriefeedUITests
MAIN_TARGET = Briefeed

# Derived data for faster incremental builds
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData/$(SCHEME)-build

# Default target
.DEFAULT_GOAL := help

help:
	@echo "$(SCHEME) iOS Build Commands"
	@echo ""
	@echo "Build & Run:"
	@echo "  make build         - Build for iOS simulator"
	@echo "  make run           - Build and launch on simulator"
	@echo "  make clean         - Clean build artifacts"
	@echo ""
	@echo "Testing:"
	@echo "  make test          - Run all tests (unit + UI)"
	@echo "  make test-unit     - Run unit tests only"
	@echo "  make test-ui       - Run UI tests only"
	@echo ""
	@echo "Agent Tools:"
	@echo "  make ui-tree       - Get accessibility tree (requires running app)"
	@echo "  make screenshot    - Take simulator screenshot"
	@echo "  make tap ELEMENT=x - Tap element by accessibility ID"
	@echo "  make install-tools - Install xcbeautify, axe, xcp, peekaboo"
	@echo ""

# Build for simulator
build:
	@echo "Building $(SCHEME) for $(SIMULATOR)..."
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=$(IOS_VERSION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-configuration Debug \
		| xcbeautify

# Run all tests
test:
	@echo "Running all tests..."
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=$(IOS_VERSION)' \
		-derivedDataPath $(DERIVED_DATA) \
		| xcbeautify

# Run unit tests only
test-unit:
	@echo "Running unit tests..."
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=$(IOS_VERSION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:"$(UNIT_TEST_TARGET)" \
		| xcbeautify

# Run UI tests only
test-ui:
	@echo "Running UI tests..."
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=$(IOS_VERSION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:"$(UI_TEST_TARGET)" \
		| xcbeautify

# Build and run on simulator
run:
	@echo "Booting simulator..."
	@xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	@echo "Building and installing..."
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR),OS=$(IOS_VERSION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-configuration Debug \
		| xcbeautify
	@echo "Launching app..."
	xcrun simctl launch booted $(BUNDLE_ID)

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME)
	rm -rf $(DERIVED_DATA)
	@echo "Clean complete."

# Take simulator screenshot
screenshot:
	@mkdir -p screenshots
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	xcrun simctl io booted screenshot "screenshots/screenshot_$$TIMESTAMP.png"; \
	echo "Screenshot saved to screenshots/screenshot_$$TIMESTAMP.png"

# Get accessibility tree using axe
ui-tree:
	@echo "Getting accessibility tree..."
	@axe --bundle-id $(BUNDLE_ID) tree 2>/dev/null || echo "Make sure the app is running and axe is installed"

# Tap a UI element by accessibility identifier
tap:
	@if [ -z "$(ELEMENT)" ]; then \
		echo "Usage: make tap ELEMENT=<accessibility-id>"; \
	else \
		axe --bundle-id $(BUNDLE_ID) tap --id "$(ELEMENT)"; \
	fi

# Install development tools for agent-friendly testing
install-tools:
	@echo "Installing development tools..."
	@which xcbeautify > /dev/null || brew install xcbeautify
	@which axe > /dev/null || brew install axe
	@which xcp > /dev/null || brew install xcp
	@which peekaboo > /dev/null || (brew tap steipete/peekaboo && brew install peekaboo)
	@echo ""
	@echo "Tools installed:"
	@echo "  - xcbeautify: $$(xcbeautify --version 2>/dev/null || echo 'not found')"
	@echo "  - axe: $$(axe --version 2>/dev/null || echo 'not found')"
	@echo "  - xcp: $$(xcp --version 2>/dev/null || echo 'not found')"
	@echo "  - peekaboo: $$(peekaboo --version 2>/dev/null || echo 'not found')"

# Lint Swift files (optional, requires swiftlint)
lint:
	@if which swiftlint > /dev/null; then \
		swiftlint lint $(MAIN_TARGET)/; \
	else \
		echo "SwiftLint not installed. Run: brew install swiftlint"; \
	fi

APP_TEST_ENGINE := $(HOME)/ericode/skills/app-testing/scripts
RADIO_SIM_CONFIG := $(CURDIR)/skills/app-testing/config.sh

radio-compile:
	xcodebuild build-for-testing -project Briefeed.xcodeproj -scheme Briefeed -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/briefeed-radio-compile CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO

radio-golden:
	AGENT_SIM_CONFIG=$(RADIO_SIM_CONFIG) bash $(APP_TEST_ENGINE)/sim-doctor.sh --gc
	AGENT_SIM_CONFIG=$(RADIO_SIM_CONFIG) bash $(APP_TEST_ENGINE)/sim-golden.sh refresh

radio-unit:
	bash skills/app-testing/scripts/run-radio.sh radio-unit unit

radio-ui:
	bash skills/app-testing/scripts/run-radio.sh radio-ui ui

radio-smoke:
	bash skills/app-testing/scripts/run-radio.sh radio-smoke smoke

sim-doctor:
	AGENT_SIM_CONFIG=$(RADIO_SIM_CONFIG) bash $(APP_TEST_ENGINE)/sim-doctor.sh --gc

sim-status:
	bash $(APP_TEST_ENGINE)/sim-status.sh
