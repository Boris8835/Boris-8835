# Consorcio Field — Guía

App Flutter para Android 10+ (minSdk 29), 100 % offline, en español argentino.

## 1. Cómo obtener el APK (sin instalar nada en tu PC): GitHub Actions

1. Creá una cuenta gratis en https://github.com y un repositorio nuevo (por ejemplo `consorcio-field`).
2. Descomprimí este ZIP y subí **todo el contenido** al repositorio (botón *Add file → Upload files*; arrastrá también la carpeta oculta `.github`; si no te deja, subila con GitHub Desktop).
3. Entrá a la pestaña **Actions → "Compilar APK" → Run workflow**.
4. A los 6–10 minutos termina. Entrá a esa ejecución y abajo, en **Artifacts**, descargá `ConsorcioField-APK` (es un ZIP con `app-release.apk` adentro).
5. Si la compilación falla, copiá el mensaje de error rojo y pasámelo: se corrige en minutos.

## 2. Cómo instalar el APK en tu celular

1. Pasá `app-release.apk` al celular (WhatsApp a vos mismo, cable USB, Drive o correo).
2. Tocá el archivo. Android va a avisar que bloquea instalar apps de fuentes desconocidas: tocá **Ajustes** y activá **"Permitir desde esta fuente"** para la app que usaste (Archivos, Chrome, WhatsApp…). Es un ajuste normal en Android 10+: *Ajustes → Apps → Acceso especial → Instalar apps desconocidas*.
3. Volvé atrás y tocá **Instalar**. Si aparece "Play Protect", elegí **Instalar de todos modos** (es normal con apps que no están en la tienda).
4. Abrí **Consorcio Field**. Aceptá los permisos de cámara, ubicación y micrófono cuando los pida.
5. Primer uso: **Consorcios y unidades → NUEVO**, cargá un consorcio y generá sus unidades. Después ya podés usar el resto.

## 3. Compilar en tu propia PC (alternativa)

1. Instalá Flutter (https://docs.flutter.dev/get-started/install) y Android Studio (trae el SDK). Corré `flutter doctor` y resolvé lo que marque en rojo.
2. Abrí una terminal en la carpeta del proyecto.
   - Windows: `build_apk.bat`
   - Linux / Mac: `bash build_apk.sh`
3. El APK queda en `build/app/outputs/flutter-apk/app-release.apk`.

(El script genera la carpeta `android/`, le pone permisos y minSdk 29, crea los íconos desde `assets/icon/icon.png` y compila.)

## 4. Abrir y modificar el código

1. Instalá **VS Code** + extensión *Flutter* (o Android Studio).
2. Descomprimí el ZIP, abrí la carpeta `consorcio_field`.
3. Código en `lib/`:
   - `main.dart` — pantalla de inicio y tema
   - `db.dart` — base de datos SQLite
   - `widgets.dart` — botones, dictado, fotos, GPS
   - `screens/` — un archivo por módulo
   - `pdf_acta.dart` — acta PDF
4. Después de cambiar algo, volvé a compilar (punto 1 o 3).

## 5. Dónde ver los registros de cada módulo

Todo se guarda en el celular (`consorcio_field.db`), cada módulo en tablas separadas:

| Módulo | Dónde verlos | Se puede editar / borrar |
|---|---|---|
| Consorcios y unidades | Inicio → Consorcios → tocar uno (Datos / Unidades / Archivos) | Sí; borrar un consorcio borra solo sus unidades y archivos |
| Inspecciones | Inicio → Inspecciones | Sí, una por una |
| Órdenes de trabajo | Inicio → Órdenes (filtro por estado) | Sí, una por una |
| Gastos | Inicio → Gastos | Sí, uno por uno |
| Reclamos | Inicio → Reclamos (cada uno con su historial) | Sí, uno por uno |
| Consulta rápida | Saldos y vencimientos (solo lectura) | — |

**Borrar una inspección NO borra gastos, reclamos ni órdenes.** Cada registro guarda el nombre del consorcio, así que sobrevive aunque borres el consorcio.

## 6. Notas importantes

- **Sin internet:** todo funciona offline. Esta primera versión **no sincroniza con ningún servidor** (priorizamos estabilidad offline). Hacé copias del celular periódicamente.
- **OCR de facturas:** funciona sin internet y completa monto, fecha y CUIT; siempre revisá los datos.
- **Dictado por voz:** usa el reconocimiento de Google del celular. Sin internet funciona solo si tenés descargado el paquete de voz en español (*Ajustes → Idioma → Voz*).
- **Saldos de expensas:** se cargan a mano en cada unidad (campo "Saldo pendiente").
- **Firma del APK:** el APK sale firmado con clave de depuración. Sirve para instalar en tu teléfono; para publicar en Play Store habría que firmarlo con tu propia clave.

## 8. Novedades de la versión 1.3
- **Pagos parciales:** en cada expensa, el botón PAGAR permite poner un monto menor. Queda en PAGO PARCIAL y lo que resta se arrastra y se suma al saldo pendiente.
- **Saldo pendiente:** se calcula solo (suma de lo que resta de cada expensa). Cada propietario debe lo que le corresponde según su porcentaje (coeficiente). Para una deuda vieja, usá CARGAR SALDO ANTERIOR en la unidad.
- **Resumen de cuenta:** en la unidad se ve total emitido, pagos recibidos, pagos parciales anteriores y saldo pendiente. Los PDF muestran lo mismo.
- **Firma del administrador/a:** en el consorcio, botón ESCANEAR FIRMA CON LA CÁMARA. Se agrega al final de todos los PDF.
- **Ingresos** y **Informe de gastos e ingresos (PDF)** con balance, desde la pantalla principal, Gastos o Ingresos.
- Los PDF ya no llevan el nombre del desarrollador; figura al pie de la pantalla principal.
