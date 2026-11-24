import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Una fila reconocida en la foto del listado.
class FilaListado {
  String piso, numero, propietario, telefono, coef;
  bool sel;
  FilaListado(this.piso, this.numero, this.propietario, this.telefono, this.coef, this.sel);
}

final _reLetras = RegExp(r"[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s.,'\-]");
final _reEncabezado = RegExp(r'propietari|unidad|piso|tel[eé]fono|coef|total|nombre|apellido|depto|inquilino|celular',
    caseSensitive: false);

String _titulo(String s) => s
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w.length == 1 ? w.toUpperCase() : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

/// Arma las filas del listado a partir del texto reconocido: agrupa los renglones
/// que están a la misma altura (columnas de una tabla) y analiza cada fila.
List<FilaListado> parsearListado(RecognizedText r) {
  final lineas = <TextLine>[];
  for (final b in r.blocks) {
    lineas.addAll(b.lines);
  }
  lineas.sort((a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
  final filas = <List<TextLine>>[];
  double? cy;
  double alto = 0;
  for (final l in lineas) {
    final bb = l.boundingBox;
    if (cy != null && (bb.center.dy - cy).abs() < (alto > bb.height ? alto : bb.height) * 0.6) {
      final f = filas.last;
      f.add(l);
      cy = f.fold<double>(0, (a, x) => a + x.boundingBox.center.dy) / f.length;
      alto = f.fold<double>(0, (a, x) => a + x.boundingBox.height) / f.length;
    } else {
      filas.add([l]);
      cy = bb.center.dy;
      alto = bb.height;
    }
  }
  final res = <FilaListado>[];
  for (final f in filas) {
    f.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    final fila = parsearFila(f.map((x) => x.text).join(' '));
    if (fila != null) res.add(fila);
  }
  return res;
}

/// Analiza un renglón: unidad (piso y número), propietario, teléfono y coeficiente.
FilaListado? parsearFila(String original) {
  var t = original.replaceAll('|', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return null;

  // Teléfono: tira de dígitos (8 a 11) tomada desde la derecha
  var tel = '';
  for (final m in RegExp(r'\+?\d[\d\s\-()]{6,}\d').allMatches(t)) {
    final toks = m.group(0)!.split(' ');
    final acc = <String>[];
    var d = 0;
    var i = toks.length - 1;
    while (i >= 0) {
      final nd = toks[i].replaceAll(RegExp(r'\D'), '').length;
      if (d >= 10) break;
      if (d >= 8 && nd < 3) break;
      acc.insert(0, toks[i]);
      d += nd;
      i--;
    }
    if (d >= 8) {
      tel = acc.join(' ');
      t = '${t.substring(0, m.start)}${toks.sublist(0, i + 1).join(' ')} ${t.substring(m.end)}'.trim();
      break;
    }
  }

  // Coeficiente: número con % o con decimales
  var coef = '';
  final mc = RegExp(r'(\d{1,3}(?:[,.]\d{1,4})?)\s*%').firstMatch(t) ?? RegExp(r'(\d{1,2}[,.]\d{1,4})').firstMatch(t);
  if (mc != null) {
    coef = mc.group(1)!.replaceAll(',', '.');
    t = '${t.substring(0, mc.start)} ${t.substring(mc.end)}'.trim();
  }

  // Unidad
  var piso = '', numero = '';
  final m1 = RegExp(r'^(?:u\.?\s?f\.?|unidad)\s*[:.]?\s*(\d{1,3})\b', caseSensitive: false).firstMatch(t);
  final m2 = RegExp(
          r'^(?:piso\s*)?(pb|ph|planta baja|\d{1,2})\s*[º°]?\s*[-/]?\s*(?:dto\.?|depto\.?|dpto\.?|unidad)?\s*([a-z]|\d{1,3})(?![a-z])',
          caseSensitive: false)
      .firstMatch(t);
  final m3 = RegExp(r'^(\d{1,3})\s+(?=\D)').firstMatch(t);
  if (m1 != null) {
    piso = '-';
    numero = m1.group(1)!;
    t = t.substring(m1.end);
  } else if (m2 != null) {
    piso = m2.group(1)!.toUpperCase();
    numero = m2.group(2)!.toUpperCase();
    t = t.substring(m2.end);
  } else if (m3 != null) {
    piso = '-';
    numero = m3.group(1)!;
    t = t.substring(m3.end);
  }

  var nombre = _titulo(t.replaceAll(_reLetras, ' ').replaceAll(RegExp(r'\s+'), ' ').trim());
  if (nombre.length < 3) nombre = '';
  if (numero.isEmpty && (nombre.isEmpty || _reEncabezado.hasMatch(nombre))) return null;
  return FilaListado(piso, numero, nombre, tel, coef, numero.isNotEmpty);
}

