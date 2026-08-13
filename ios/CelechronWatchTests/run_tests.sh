#!/usr/bin/env bash
set -euo pipefail

TEST_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIRECTORY="$(cd "${TEST_DIRECTORY}/../.." && pwd)"
QR_TEST_BINARY="$(mktemp "${TMPDIR:-/tmp}/celechron-qr-tests.XXXXXX")"
ECARD_TEST_BINARY="$(mktemp "${TMPDIR:-/tmp}/celechron-ecard-tests.XXXXXX")"
trap 'rm -f "${QR_TEST_BINARY}" "${ECARD_TEST_BINARY}"' EXIT

xcrun swiftc \
  "${PROJECT_DIRECTORY}/ios/CelechronWatch/SimpleQRCode.swift" \
  "${TEST_DIRECTORY}/SimpleQRCodeTests.swift" \
  -o "${QR_TEST_BINARY}"

"${QR_TEST_BINARY}" "${TEST_DIRECTORY}/reference_matrices.json"

xcrun swiftc \
  "${PROJECT_DIRECTORY}/ios/Shared/ECardService.swift" \
  "${TEST_DIRECTORY}/ECardServiceTests.swift" \
  -o "${ECARD_TEST_BINARY}"

"${ECARD_TEST_BINARY}"
