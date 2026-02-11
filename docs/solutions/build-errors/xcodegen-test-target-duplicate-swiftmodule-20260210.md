---
title: "xcodegen test target produces duplicate swiftmodule — PRODUCT_MODULE_NAME fix"
category: build-errors
date: 2026-02-10
component: ios
tags: [xcodegen, unit-tests, swiftmodule, build-conflict, swift-testing]
severity: blocking
symptoms:
  - "Multiple commands produce '...Robo.swiftmodule/arm64-apple-ios-simulator.swiftmodule'"
  - "Target 'Robo' has copy command / Target 'RoboTests' has copy command"
  - xcodebuild test fails on simulator but device build succeeds
---

# xcodegen Test Target Produces Duplicate swiftmodule

## Problem

Adding a `bundle.unit-test` target in xcodegen's `project.yml` causes `xcodebuild test` to fail with a "Multiple commands produce" error for `.swiftmodule` files. The device build (`generic/platform=iOS`) succeeds because it only builds the app target.

## Symptoms

```
error: Multiple commands produce '.../Robo.swiftmodule/arm64-apple-ios-simulator.swiftmodule'
    note: Target 'Robo' (project 'Robo') has copy command...
    note: Target 'RoboTests' (project 'Robo') has copy command...
```

- Only occurs when running `xcodebuild test` (simulator)
- Device-only builds succeed
- Clean builds don't help

## Root Cause

The test target inherits `PRODUCT_NAME: Robo` from project-level settings in `project.yml`. Both the app target and the test target then produce a swiftmodule named `Robo.swiftmodule`, causing a build system collision.

xcodegen propagates project-level `settings.base` to all targets. When the app target is named `Robo` and `PRODUCT_NAME` is set at the project level, the test target also gets `PRODUCT_NAME: Robo` unless explicitly overridden.

## Solution

Add `PRODUCT_MODULE_NAME: RoboTests` to the test target settings:

```yaml
# ios/project.yml
  RoboTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: RoboTests
        excludes:
          - "**/.DS_Store"
    dependencies:
      - target: Robo
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.silv.Robo.tests
        PRODUCT_MODULE_NAME: RoboTests          # <-- THIS FIXES IT
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Robo.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Robo"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

Also requires `GENERATE_INFOPLIST_FILE: YES` — without it you get a separate "Cannot code sign because the target does not have an Info.plist file" error.

After changing `project.yml`, regenerate:

```bash
cd ios && xcodegen generate
```

## Why This Works

`PRODUCT_MODULE_NAME` overrides the module name derived from `PRODUCT_NAME`. By setting it to `RoboTests`, the test target produces `RoboTests.swiftmodule` instead of `Robo.swiftmodule`, eliminating the collision.

## Prevention

When adding test targets in xcodegen, always set `PRODUCT_MODULE_NAME` to a unique value distinct from the app target. A simple convention: `{AppName}Tests`.

## Related

- [Issue #40](https://github.com/mattsilv/robo/issues/40) — Add iOS test targets and CI gates
- Apple Technical Note: [Resolving "Multiple commands produce" errors](https://developer.apple.com/documentation/xcode/build-system)
