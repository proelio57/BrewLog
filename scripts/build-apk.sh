#!/bin/bash
# Builds an Android APK for sideloading or distribution.
# Runs unit tests first before compiling.
# Usage: ./scripts/build-apk.sh [--release]
set -euo pipefail

cd "$(dirname "$0")/.."

# Auto-detect JAVA_HOME if not set
if [ -z "${JAVA_HOME:-}" ]; then
  if [ -d "$HOME/.local/share/jdk-17" ]; then
    export JAVA_HOME="$HOME/.local/share/jdk-17"
  elif [ -d "/usr/lib/jvm/java-17-openjdk" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
  elif [ -d "/usr/lib/jvm/default" ]; then
    export JAVA_HOME="/usr/lib/jvm/default"
  fi
fi

# Auto-detect Android SDK if not set
if [ -z "${ANDROID_HOME:-}" ] && [ ! -f "android/local.properties" ]; then
  if [ -d "$HOME/Android/Sdk" ]; then
    export ANDROID_HOME="$HOME/Android/Sdk"
    echo "sdk.dir=$ANDROID_HOME" > android/local.properties
  elif [ -d "$HOME/Library/Android/sdk" ]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
    echo "sdk.dir=$ANDROID_HOME" > android/local.properties
  fi
fi

BUILD_TYPE="Debug"
GRADLE_TASK="assembleDebug"
for arg in "$@"; do
  if [ "$arg" == "--release" ]; then
    BUILD_TYPE="Release"
    GRADLE_TASK="assembleRelease"
  fi
done

echo "==> Running unit tests before compilation..."
./android/gradlew -p android testDebugUnitTest

echo "==> Compiling APK ($BUILD_TYPE)..."
./android/gradlew -p android "$GRADLE_TASK"

mkdir -p build
if [ "$BUILD_TYPE" == "Release" ]; then
  if [ -f "android/app/build/outputs/apk/release/app-release.apk" ]; then
    cp "android/app/build/outputs/apk/release/app-release.apk" "build/BrewLog.apk"
    echo "==> Successfully built: $(pwd)/build/BrewLog.apk"
  elif [ -f "android/app/build/outputs/apk/release/app-release-unsigned.apk" ]; then
    cp "android/app/build/outputs/apk/release/app-release-unsigned.apk" "build/BrewLog-release-unsigned.apk"
    echo "==> Successfully built: $(pwd)/build/BrewLog-release-unsigned.apk (unsigned)"
  fi
else
  cp "android/app/build/outputs/apk/debug/app-debug.apk" "build/BrewLog-debug.apk"
  echo "==> Successfully built: $(pwd)/build/BrewLog-debug.apk"
fi
