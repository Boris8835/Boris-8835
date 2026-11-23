// Ajusta el proyecto Android recién generado con `flutter create`:
//  - minSdk 29 (Android 10)
//  - permisos de cámara, micrófono, GPS
//  - nombre visible "Consorcio Field"
// Se ejecuta con:  dart tools/preparar_android.dart
import 'dart:io';

void main() {
  final manifestFile = File('android/app/src/main/AndroidManifest.xml');
  if (!manifestFile.existsSync()) {
    stderr.writeln('No existe android/. Primero ejecutá flutter create (ver GUIA.md).');
    exit(1);
  }
  var m = manifestFile.readAsStringSync();

  if (!m.contains('android.permission.CAMERA')) {
    const permisos = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    <uses-feature android:name="android.hardware.location.gps" android:required="false"/>
    <application''';
    m = m.replaceFirst('<application', permisos);
  }

  if (!m.contains('android.speech.RecognitionService')) {
    const intentVoz =
        '<intent><action android:name="android.speech.RecognitionService"/></intent>';
    if (m.contains('<queries>')) {
      m = m.replaceFirst('<queries>', '<queries>\n        $intentVoz');
    } else {
      m = m.replaceFirst('</manifest>', '    <queries>\n        $intentVoz\n    </queries>\n</manifest>');
    }
  }

  m = m.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Consorcio Field"');
  manifestFile.writeAsStringSync(m);

  for (final ruta in ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final f = File(ruta);
    if (!f.existsSync()) continue;
    var g = f.readAsStringSync();
    g = g.replaceAll(RegExp(r'minSdk\s*=\s*flutter\.minSdkVersion'), 'minSdk = 29');
    g = g.replaceAll(RegExp(r'minSdkVersion\s+flutter\.minSdkVersion'), 'minSdkVersion 29');
    f.writeAsStringSync(g);
    stdout.writeln('Actualizado $ruta (minSdk 29)');
  }
  stdout.writeln('Android listo: permisos + minSdk 29 + nombre de la app.');
}
