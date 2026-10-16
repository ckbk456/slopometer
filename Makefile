SHELL := /bin/bash
.DEFAULT_GOAL := help
.NOTPARALLEL:

PROJECT := Slopometer.xcodeproj
XCODE_ARGS := -project $(PROJECT) -scheme Slopometer -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode -clonedSourcePackagesDirPath .build/SourcePackages
LOCKED_PACKAGES := -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
SWIFT_FORMAT := swift run --package-path Tools --scratch-path .build/tools-build --disable-automatic-resolution -c release swift-format
FORMATTED := Package.swift Tools/Package.swift App Sources Tests

.PHONY: help doctor setup generate generate-check resolve lint format docs-check test build build-signed validate open run

help:
	@printf '%s\n' 'setup       Check tools, regenerate the Xcode project, fetch locked dependencies' 'validate    Run lint, structure/docs checks, core tests, and native app build' 'test        Run the core package tests once' 'build       Build the unsigned Debug app (CI and validation)' 'run         Build a signed Debug app and launch it (manual)' 'open        Open the Xcode project' 'generate-check Fail if the Xcode project differs from project.yml' 'format      Format project-owned Swift files' 'generate    Regenerate the checked-in Xcode project with XcodeGen 2.46.0'

doctor:
	@bash scripts/doctor.sh

setup:
	@$(MAKE) doctor
	@$(MAKE) generate
	@$(MAKE) resolve

generate:
	@bash scripts/generate.sh

generate-check:
	@bash scripts/check_generated.sh

resolve:
	swift package --force-resolved-versions resolve
	swift package --package-path Tools --scratch-path .build/tools-build --force-resolved-versions resolve
	xcodebuild -resolvePackageDependencies $(XCODE_ARGS) $(LOCKED_PACKAGES)

lint:
	$(SWIFT_FORMAT) lint --strict --recursive $(FORMATTED)

format:
	$(SWIFT_FORMAT) format --in-place --recursive $(FORMATTED)

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

build-signed:
	xcodebuild $(XCODE_ARGS) $(LOCKED_PACKAGES) -jobs 4 -allowProvisioningUpdates build

run: build-signed
	open .build/xcode/Build/Products/Debug/Slopometer.app
