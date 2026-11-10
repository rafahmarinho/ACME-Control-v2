#!/usr/bin/env bash
# Build script for deploying the Flutter web app from Git on Vercel.
# Vercel has no Flutter SDK, so this installs the stable SDK, writes the
# dart-define file from Vercel environment variables and builds build/web.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.9}"

if ! command -v flutter >/dev/null 2>&1; then
  if [ ! -d "$HOME/flutter" ]; then
    git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$HOME/flutter"
  fi
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter config --no-analytics >/dev/null
flutter --version

mkdir -p env
cat > env/vercel.json <<JSON
{
  "SUPABASE_URL": "${SUPABASE_URL:?Set SUPABASE_URL in Vercel}",
  "SUPABASE_ANON_KEY": "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY in Vercel}",
  "API_BASE_URL": "${API_BASE_URL:?Set API_BASE_URL in Vercel}",
  "WEB_APP_URL": "${WEB_APP_URL:-}",
  "DEMO_PASSWORD": "${DEMO_PASSWORD:-}"
}
JSON

flutter pub get
flutter build web --release --dart-define-from-file=env/vercel.json
