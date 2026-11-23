#!/usr/bin/env bash
# Compila el APK en Linux / macOS. Requiere Flutter y Android SDK instalados.
set -e
if [ ! -d android ]; then
  flutter create --org ar.consorciofield --project-name consorcio_field --platforms=android _scaffold
  cp -r _scaffold/android ./android
  rm -rf _scaffold
fi
dart tools/preparar_android.dart
flutter pub get
dart run flutter_launcher_icons
flutter build apk --release
echo
echo "APK listo en: build/app/outputs/flutter-apk/app-release.apk"
