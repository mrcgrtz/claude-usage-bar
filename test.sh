#!/bin/sh
# Builds and runs the tests in Tests with the app code. Sources/main.swift starts the app, so the tests leave it out.
set -eu

cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc -swift-version 6 $(ls Sources/*.swift | grep -v '/main.swift$') Tests/*.swift -o build/tests
# English and US formats give the same texts and numbers on each Mac.
build/tests -AppleLanguages '(en)' -AppleLocale en_US
