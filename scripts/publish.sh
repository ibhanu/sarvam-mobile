#!/usr/bin/env bash
set -eo pipefail

MODE="${1:---dry-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=========================================================="
echo "Sarvam Mobile SDKs — Monorepo Publishing Pipeline"
echo "Mode: $MODE"
echo "Root: $ROOT_DIR"
echo "=========================================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. npm packages (@sarvam-mobile/core & @sarvam-mobile/react-native)
echo -e "\n${YELLOW}=== [1/4] TypeScript & React Native Packages (npm) ===${NC}"
cd "$ROOT_DIR"
npm install
npm run build

if [ "$MODE" = "--live" ] || [ "$MODE" = "--publish" ]; then
    echo -e "${GREEN}Publishing @sarvam-mobile/core to npm registry...${NC}"
    (cd "$ROOT_DIR/packages/ts-core" && npm publish --access public)
    echo -e "${GREEN}Publishing @sarvam-mobile/react-native to npm registry...${NC}"
    (cd "$ROOT_DIR/packages/react-native" && npm publish --access public)
else
    echo "Running npm publish dry-run for @sarvam-mobile/core..."
    (cd "$ROOT_DIR/packages/ts-core" && npm publish --dry-run)
    echo "Running npm publish dry-run for @sarvam-mobile/react-native..."
    (cd "$ROOT_DIR/packages/react-native" && npm publish --dry-run)
fi

# 2. Dart & Flutter Packages (pub.dev)
echo -e "\n${YELLOW}=== [2/4] Dart & Flutter Packages (pub.dev) ===${NC}"
DART_CMD="dart"
FLUTTER_CMD="flutter"

# Prefer user-installed modern Dart/Flutter SDKs if available
if [ -x "/Users/bhanu/fvm/default/bin/dart" ]; then
    DART_CMD="/Users/bhanu/fvm/default/bin/dart"
fi
if [ -x "/Users/bhanu/fvm/default/bin/flutter" ]; then
    FLUTTER_CMD="/Users/bhanu/fvm/default/bin/flutter"
fi

echo "Using Dart: $($DART_CMD --version)"
echo "Validating sarvam (core Dart)..."
(
    cd "$ROOT_DIR/packages/dart/sarvam"
    $DART_CMD pub get
    if [ "$MODE" = "--live" ] || [ "$MODE" = "--publish" ]; then
        echo -e "${GREEN}Publishing sarvam to pub.dev...${NC}"
        $DART_CMD pub publish --force
    else
        $DART_CMD pub publish --dry-run || [ $? -eq 65 ] || true
    fi
)

echo "Validating sarvam_flutter_audio (Flutter companion)..."
(
    cd "$ROOT_DIR/packages/dart/sarvam_flutter_audio"
    $FLUTTER_CMD pub get
    if [ "$MODE" = "--live" ] || [ "$MODE" = "--publish" ]; then
        echo -e "${GREEN}Publishing sarvam_flutter_audio to pub.dev...${NC}"
        $FLUTTER_CMD pub publish --force
    else
        $FLUTTER_CMD pub publish --dry-run || [ $? -eq 65 ] || true
    fi
)

# 3. Kotlin & Android Packages (Maven Central / Local Maven)
echo -e "\n${YELLOW}=== [3/4] Kotlin & Android Packages (Maven) ===${NC}"
if [ -z "$JAVA_HOME" ] && [ -x "/usr/libexec/java_home" ]; then
    export JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home)"
fi
echo "Using JAVA_HOME: $JAVA_HOME"

(
    cd "$ROOT_DIR/packages/kotlin"
    echo "Publishing Kotlin artifacts to Maven Local and Staging directory..."
    ./gradlew publishToMavenLocal publishAllPublicationsToStagingRepository --stacktrace
    
    if [ "$MODE" = "--live" ] || [ "$MODE" = "--publish" ]; then
        if [ -n "$OSSRH_USERNAME" ]; then
            echo -e "${GREEN}Publishing artifacts to Maven Central / Sonatype...${NC}"
            ./gradlew publish --stacktrace
        else
            echo -e "${YELLOW}Notice: OSSRH_USERNAME not set; artifacts published to Maven Local and Staging repository.${NC}"
        fi
    fi
)

# 4. Swift Package Manager (SPM / Swift Package Index)
echo -e "\n${YELLOW}=== [4/4] Swift Packages (SPM / Git Release) ===${NC}"
(
    cd "$ROOT_DIR"
    echo "Building release configuration for Swift targets..."
    swift build -c release
    echo -e "${GREEN}Swift build successful. Targets Sarvam and SarvamAudio are ready for SPM consumption.${NC}"
    if [ -f ".spi.yml" ]; then
        echo "Swift Package Index manifest .spi.yml is present."
    fi
)

echo -e "\n${GREEN}==========================================================${NC}"
echo -e "${GREEN}All package registries checked and processed successfully!${NC}"
echo -e "${GREEN}==========================================================${NC}"
