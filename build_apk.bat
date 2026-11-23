@echo off
REM Compila el APK en Windows. Requiere Flutter y Android SDK instalados (flutter doctor sin errores).
if not exist android (
  call flutter create --org ar.consorciofield --project-name consorcio_field --platforms=android _scaffold || goto :error
  xcopy /E /I /Y _scaffold\android android >nul
  rmdir /S /Q _scaffold
)
call dart tools\preparar_android.dart || goto :error
call flutter pub get || goto :error
call dart run flutter_launcher_icons || goto :error
call flutter build apk --release || goto :error
echo.
echo APK listo en: build\app\outputs\flutter-apk\app-release.apk
goto :eof
:error
echo Ocurrio un error. Revisa el mensaje de arriba.
exit /b 1
