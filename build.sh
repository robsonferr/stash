#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Stash"
BUNDLE_ID="com.robsonferreira.stash"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICONSET_DIR="icon.iconset"
ICNS_FILE="AppIcon.icns"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

echo "==> Limpando build anterior"
rm -rf "${APP_DIR}" "${ICONSET_DIR}" "${ICNS_FILE}"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "==> Gerando iconset"
swift generate_icon.swift

if command -v iconutil >/dev/null 2>&1; then
  echo "==> Convertendo iconset para .icns"
  iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_FILE}"
  cp "${ICNS_FILE}" "${RESOURCES_DIR}/"
else
  echo "[aviso] iconutil nao encontrado. O app sera gerado sem .icns."
fi

echo "==> Compilando executavel"
swiftc DumpMemory.swift -framework Cocoa -framework EventKit -framework Security -o "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "==> Gerando Info.plist"
cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>pt-BR</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.14</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSRemindersFullAccessUsageDescription</key>
  <string>Stash precisa acessar Lembretes para criar itens no app Reminders.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Stash cria lembretes no app Reminders quando voce salva itens com o icone de lembrete.</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  if [[ "${CODE_SIGN_IDENTITY}" == "-" ]]; then
    echo "==> Assinando app (ad-hoc)"
    codesign --force --deep --sign - "${APP_DIR}"
  else
    echo "==> Assinando app com identidade: ${CODE_SIGN_IDENTITY}"
    codesign --force --deep --options runtime --sign "${CODE_SIGN_IDENTITY}" "${APP_DIR}"
  fi

  echo "==> Verificando assinatura"
  codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
else
  echo "[aviso] codesign nao encontrado. Build segue sem assinatura."
fi

echo "==> Build concluido: ./${APP_DIR}"
echo "Execute com: open ${APP_DIR}"
