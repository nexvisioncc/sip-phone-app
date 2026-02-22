#!/bin/bash
set -e

echo "🚀 SIP Phone App - Setup Script"
echo "================================"
echo ""

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found!"
    echo "Please install Flutter: https://docs.flutter.dev/get-started/install"
    exit 1
fi

echo "✅ Flutter version: $(flutter --version | head -1)"

# Check Android SDK
if [ -z "$ANDROID_SDK_ROOT" ] && [ -z "$ANDROID_HOME" ]; then
    echo "⚠️  Warning: ANDROID_SDK_ROOT or ANDROID_HOME not set"
fi

cd flutter_app

echo ""
echo "📦 Getting dependencies..."
flutter pub get

echo ""
echo "🔧 Checking for Firebase config..."
if [ ! -f "android/app/google-services.json" ]; then
    echo "⚠️  google-services.json not found!"
    echo "Please add your Firebase config to android/app/google-services.json"
    echo "Get it from: https://console.firebase.google.com/"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Add google-services.json if not already done"
echo "2. Run: flutter analyze"
echo "3. Run: flutter run"
echo ""
