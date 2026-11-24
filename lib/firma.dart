import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'db.dart';

/// Escanea la firma con la cámara: saca el fondo de la hoja, deja solo la tinta
/// (transparente), recorta los bordes y guarda un PNG listo para los PDF.
/// Devuelve la ruta guardada o null si se cancela / no se detecta firma.
Future<String?> escanearFirma({ImageSource fuente = ImageSource.camera}) async {
  final x = await ImagePicker().pickImage(source: fuente, maxWidth: 1800, imageQuality: 92);
  if (x == null) return null;
  final bytes = await File(x.path).readAsBytes();
  final png = await compute(_procesar, bytes);
  if (png == null) return null;
  final tmp = File('${x.path}_firma.png');
  await tmp.writeAsBytes(png);
  return guardarArchivo(tmp.path, 'firmas');
}

Uint8List? _procesar(Uint8List datos) {
  var im = img.decodeImage(datos);
  if (im == null) return null;
  im = img.bakeOrientation(im);
  if (im.width > 1000) im = img.copyResize(im, width: 1000);
  final w = im.width, h = im.height;

  // luminancia de cada pixel
  final lum = List<int>.filled(w * h, 0);
  final hist = List<int>.filled(256, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255).toInt();
      lum[y * w + x] = l;
      hist[l]++;
    }
  }
  // el fondo (hoja) es lo más claro: percentil 80 de la luminancia
  var acum = 0, fondo = 255;
  final objetivo = (w * h * 0.8).round();
  for (var i = 0; i < 256; i++) {
    acum += hist[i];
    if (acum >= objetivo) {
      fondo = i;
      break;
    }
  }
  if (fondo < 90) return null; // muy oscuro: no se distingue la firma

  final out = img.Image(width: w, height: h, numChannels: 4);
  var minX = w, minY = h, maxX = -1, maxY = -1;
  final umbral = fondo * 0.78; // más oscuro que esto = tinta
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = lum[y * w + x];
      int a = 0;
      if (l < umbral) {
        a = (((umbral - l) / (umbral * 0.55)) * 255).round().clamp(0, 255).toInt();
        if (a < 70) a = 0;
      }
      if (a > 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      out.setPixelRgba(x, y, 11, 37, 69, a);
    }
  }
  if (maxX < 0) return null; // no se encontró tinta
  const margen = 12;
  final x0 = (minX - margen).clamp(0, w - 1).toInt();
  final y0 = (minY - margen).clamp(0, h - 1).toInt();
  final x1 = (maxX + margen).clamp(0, w - 1).toInt();
  final y1 = (maxY + margen).clamp(0, h - 1).toInt();
  final rec = img.copyCrop(out, x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1);
  return Uint8List.fromList(img.encodePng(rec));
}
