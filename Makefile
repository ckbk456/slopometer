SHELL := /bin/bash
.DEFAULT_GOAL := help
.NOTPARALLEL:

PROJECT := Slopometer.xcodeproj
XCODE_ARGS := -project $(PROJECT) -scheme Slopometer -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode -clonedSourcePackagesDirPath .build/SourcePackages
LOCKED_PACKAGES := -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile

.PHONY: help doctor setup generate resolve lint format docs-check test build validate open run

help:
	@printf '%s\n' 'setup       Check tools, regenerate the Xcode project, fetch locked dependencies' 'validate    Run lint, structure/docs checks, core tests, and native app build' 'test        Run the core package tests once' 'build       Build the unsigned Debug app' 'open        Open the Xcode project' 'run         Build and launch the sample-data app (manual)' 'format      Format project-owned Swift files' 'generate    Regenerate the checked-in Xcode project with XcodeGen 2.46.0'

doctor:
	@bash scripts/doctor.sh

setup:
	@$(MAKE) doctor
	@$(MAKE) generate
	@$(MAKE) resolve

generate:
	@bash scripts/generate.sh

resolve:
	swift package --force-resolved-versions resolve
	xcodebuild -resolvePackageDependencies $(XCODE_ARGS) $(LOCKED_PACKAGES)

lint:
	xcrun swift-format lint --strict --recursive Package.swift App Sources Tests

format:
	xcrun swift-format format --in-place --recursive Package.swift App Sources Tests

docs-check:
	python3 scripts/check_structure.py

test:
	swift test --disable-automatic-resolution --jobs 4

build:
	xcodebuild $(XCODE_ARGS) $(LOCKED_PACKAGES) -jobs 4 CODE_SIGNING_ALLOWED=NO build

validate:
	@$(MAKE) lint
	@$(MAKE) docs-check
	@$(MAKE) test
	@$(MAKE) build

open:
	open $(PROJECT)

run: build
	open .build/xcode/Build/Products/Debug/Slopometer.app
