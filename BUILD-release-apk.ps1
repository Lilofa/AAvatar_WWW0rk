# ============================================================
#  АВатар 1.0.0 - финальная release-сборка под ПРОД
#  Запуск: PowerShell в D:\dev\projects\avatar-repo
#  Порядок: распаковать zip в корень репо -> этот скрипт -> APK отдать Матвею.
# ============================================================
Set-StrictMode -Version Latest
cd D:\dev\projects\avatar-repo\avatar-front

# --- 0. Прод-ключи (publishable - он и так будет внутри APK, это не секрет) ---
$SUP_URL = "https://qkcxfnfyjdesmaotsmya.supabase.co"
$SUP_KEY = "sb_publishable_0_qZm0Tiucge5W6vSnNBgA_4cHP4eve"

# --- 1. Гейт keystore: ЖЁСТКИЙ СТОП, debug-подпись в релизе недопустима ---
if (-not (Test-Path android\key.properties)) {
  Write-Host "НЕТ android\key.properties - сборка НЕ начата (иначе подпишется debug-ключом)." -ForegroundColor Red
  Write-Host "Разовые шаги (keytool не в PATH - он в JBR внутри Android Studio):" -ForegroundColor Yellow
  Write-Host '  $kt = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"'
  Write-Host '  New-Item -ItemType Directory -Force D:\keys | Out-Null'
  Write-Host '  & $kt -genkeypair -v -keystore D:\keys\avatar-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias avatar -dname "CN=Artem, OU=Avatar, O=Avatar, L=Novosibirsk, C=RU"'
  Write-Host '  copy android\key.properties.example android\key.properties   # заполнить: storeFile=D:/keys/avatar-release.jks'
  Write-Host '  Файл .jks - ВНЕ репо, в двух местах; пароль отдать бизнесмену.'
  exit 1
}
$kp = @{}
Get-Content android\key.properties | Where-Object { $_ -match '^\s*([^=#]+)\s*=\s*(.*)$' } | ForEach-Object {
  $p = $_ -split '=', 2; $kp[$p[0].Trim()] = $p[1].Trim()
}
$sf = ''
if ($kp.ContainsKey('storeFile')) { $sf = $kp['storeFile'] }
if (-not $sf -or -not (Test-Path $sf)) {
  Write-Host "key.properties: storeFile не найден [$sf] - сборка НЕ начата." -ForegroundColor Red
  exit 1
}

# --- 2. Зависимости и тесты (тесты - обязательный гейт) ---
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "PUB GET УПАЛ" -ForegroundColor Red; exit 1 }
flutter test --concurrency=1
if ($LASTEXITCODE -ne 0) { Write-Host "ТЕСТЫ УПАЛИ - сборку не начинаем" -ForegroundColor Red; exit 1 }

# --- 3. Сборка APK ---
flutter build apk --release -t lib/main_sentry.dart `
  --dart-define=SUPABASE_URL=$SUP_URL `
  --dart-define=SUPABASE_ANON_KEY=$SUP_KEY
if ($LASTEXITCODE -ne 0) { Write-Host "СБОРКА УПАЛА" -ForegroundColor Red; exit 1 }

# AAB для сторов (тот же состав) - снять комментарий, когда понадобится:
# flutter build appbundle --release -t lib/main_sentry.dart `
#   --dart-define=SUPABASE_URL=$SUP_URL --dart-define=SUPABASE_ANON_KEY=$SUP_KEY

# Sentry DSN не передаём, пока нет проекта (R5): main_sentry.dart без DSN
# работает как обычный main.dart. Как появится - добавить
#   --dart-define=SENTRY_DSN=https://...@sentry.io/... и ПЕРЕСОБРАТЬ.

# --- 4. Контроль артефакта ---
$apk = "build\app\outputs\flutter-apk\app-release.apk"
Get-Item $apk | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}}, LastWriteTime

$bt = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory | Sort-Object Name -Descending | Select-Object -First 1
& "$($bt.FullName)\apksigner.bat" verify --print-certs $apk
# Ждём CN=Artem (из -dname keytool), НЕ "CN=Android Debug".

# --- 5. Что внутри: прод-URL зашит, staging-URL отсутствует ---
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $apk))
$e = $z.Entries | Where-Object { $_.FullName -like "*libapp.so" } | Select-Object -First 1
$ms = New-Object IO.MemoryStream; $s = $e.Open(); $s.CopyTo($ms); $s.Close()
$txt = [Text.Encoding]::ASCII.GetString($ms.ToArray()); $z.Dispose()
if ($txt -match "qkcxfnfyjdesmaotsmya") { "OK: прод-URL в бинарнике" } else { "ПРОВАЛ: прод-URL не зашит" }
if ($txt -match "djbtzyezhfnxberzliwc") { "ПРОВАЛ: внутри staging-URL" } else { "OK: staging-URL отсутствует" }

# --- 6. Установка на телефон (USB-отладка) ---
# adb install -r build\app\outputs\flutter-apk\app-release.apk
# или просто перекинуть APK файлом и поставить.

# --- 7. Смоук R6-0 (ПОСЛЕ того, как Матвей починит RPC - см. README-MATVEY-prod-check.txt) ---
#  a) вход по SMS: номер -> код (если sms.ru не доставила - код берём из sms_codes в Studio)
#  b) заявка: адрес с подсказками -> время -> грузчики -> РАСЧЁТ СТОИМОСТИ виден построчно
#  c) отклик грузчика с ETA (второе окно/второй телефон)
#  d) пульт диспетчера: одобрение -> бригада
#  e) этапы: выехал -> на месте -> начали -> закончили (лента обновляется БЕЗ пулл-ту-рефреш)
#  f) чат заказа + фото
#  g) закрытие -> отзыв -> рейтинг
# Каждый шаг сверяем SQL-ом: docs/matvey-live-run.md раздел 4.
