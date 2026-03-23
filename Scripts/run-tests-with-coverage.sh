#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${SCHEME:-ApproovURLSessionPackage-Package}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.6}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.derivedData-tests}"
BUILD_PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-$DERIVED_DATA_PATH/TestResults.xcresult}"
TEST_LOG_PATH="${TEST_LOG_PATH:-$DERIVED_DATA_PATH/test-output.log}"

COMMON_ARGS=(
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -enableCodeCoverage YES
)

cd "$ROOT_DIR"

xcodebuild build-for-testing "${COMMON_ARGS[@]}"

for framework in \
  "$BUILD_PRODUCTS_DIR/Approov.framework" \
  "$BUILD_PRODUCTS_DIR/PackageFrameworks/Approov.framework"
do
  if [ -d "$framework" ]; then
    codesign --force --sign - --timestamp=none "$framework"
  fi
done

rm -rf "$RESULT_BUNDLE_PATH"
: > "$TEST_LOG_PATH"
xcodebuild test-without-building "${COMMON_ARGS[@]}" -resultBundlePath "$RESULT_BUNDLE_PATH" 2>&1 | tee "$TEST_LOG_PATH"
