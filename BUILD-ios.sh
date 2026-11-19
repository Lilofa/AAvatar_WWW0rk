#!/usr/bin/env bash
# АВатар — сборка iOS (.ipa) под TestFlight / App Store. Запускать на macOS с Xcode.
# Подробности и разовая настройка: docs/ios-build.md
set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-https://qkcxfnfyjdesmaotsmya.supabase.co}"
# publishable-ключ не секрет (он и так внутри приложения), но для staging/prod он разный:
: "${SUPABASE_ANON_KEY:?Задайте SUPABASE_ANON_KEY (publishable-ключ нужного проекта)}"
: "${EXPORT_OPTIONS:=ios/ExportOptions.plist}"   # см. docs/ios-build.md, шаг 3

cd "$(dirname "$0")/avatar-front"

flutter pub get
flutter test --concurrency=1                       # тесты — обязательный гейт


flutter build ipa --release -t lib/main_sentry.dart \
  --export-options-plist="$EXPORT_OPTIONS" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

IPA=$(ls build/ios/ipa/*.ipa)
echo "Готово: $IPA"
# Загрузка в TestFlight (или через приложение Transporter):
#   xcrun altool --upload-app --type ios -f "$IPA" --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
