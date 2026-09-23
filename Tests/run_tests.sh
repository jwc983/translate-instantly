#!/bin/bash
set -e

cd "$(dirname "$0")/.."

test_binary="${TMPDIR:-/tmp}/translate-instantly-prompt-tests"
swiftc \
    Sources/TranslateInstantly/TranslationResult.swift \
    Tests/TranslationPromptBuilderTests.swift \
    -o "$test_binary"
"$test_binary"
