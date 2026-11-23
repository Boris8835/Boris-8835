import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'widgets.dart';

/// Quita caracteres que la fuente estándar del PDF no soporta (emojis, etc.).
String _limpio(dynamic t) {
  final s = (t ?? '').toString();
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r < 0x250 || r == 0x20AC) {
      b.writeCharCode(r);
    } else {
      b.write(' ');
    }
  }
  return b.toString();
}

String _estadoTxt(String e) => e == 'ok' ? 'OK' : (e == 'obs' ? 'OBSERVACION' : 'URGENTE');

PdfColor _estadoColor(String e) => e == 'ok'
    ? PdfColors.green800
    : (e == 'obs' ? PdfColors.orange800 : PdfColors.red800);

Future<File> generarActaPdf(Map<String, dynamic> insp, Map<String, dynamic>? consorcio) async {
  final items = (jsonDecode((insp['items'] ?? '[]') as String) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final doc = pw.Document();
  final lat = insp['lat'];
  final lng = insp['lng'];

  final widgets = <pw.Widget>[
    pw.Text('ACTA DE INSPECCION EDILICIA',
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 8),
    pw.Text('Consorcio: ${_limpio(insp['consorcio_nombre'])}',
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
    if (consorcio != null) ...[
      pw.Text('Direccion: ${_limpio(consorcio['direccion'])}'),
      pw.Text('CUIT: ${_limpio(consorcio['cuit'])}'),
      pw.Text('Administrador: ${_limpio(consorcio['admin_nombre'])}  Tel: ${_limpio(consorcio['admin_tel'])}'),
    ],
    pw.Text('Fecha y hora: ${fmtFecha(insp['fecha']?.toString(), hora: true)}'),
    pw.Text(lat == null
        ? 'Ubicacion GPS: no disponible'
        : 'Ubicacion GPS: $lat, $lng  (https://maps.google.com/?q=$lat,$lng)'),
    pw.Divider(),
    pw.Text('Resultado del check-list',
        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 6),
  ];

  for (final it in items) {
    final estado = (it['estado'] ?? 'ok').toString();
    widgets.add(pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _estadoColor(estado), width: 1.2)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(_limpio(it['nombre']), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(_estadoTxt(estado),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _estadoColor(estado))),
        ]),
        if ((it['ubicacion'] ?? '').toString().isNotEmpty)
          pw.Text('Ubicacion: ${_limpio(it['ubicacion'])}'),
        if ((it['nota'] ?? '').toString().isNotEmpty) pw.Text('Nota: ${_limpio(it['nota'])}'),
      ]),
    ));
    final fotos = (it['medios'] as List? ?? [])
        .map((e) => e.toString())
        .where((r) => !esVideo(r) && File(r).existsSync())
        .take(3)
        .toList();
    if (fotos.isNotEmpty) {
      final imgs = <pw.Widget>[];
      for (final f in fotos) {
        imgs.add(pw.Container(
          width: 150,
          height: 110,
          margin: const pw.EdgeInsets.only(right: 6, bottom: 8),
          child: pw.Image(pw.MemoryImage(await File(f).readAsBytes()), fit: pw.BoxFit.cover),
        ));
      }
      widgets.add(pw.Wrap(children: imgs));
    }
  }

  if ((insp['notas'] ?? '').toString().isNotEmpty) {
    widgets.add(pw.Divider());
    widgets.add(pw.Text('Observaciones generales',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)));
    widgets.add(pw.Text(_limpio(insp['notas'])));
  }
  widgets.add(pw.SizedBox(height: 40));
  widgets.add(pw.Text('Firma del administrador: ______________________________'));

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (c) => widgets,
  ));

  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'actas'));
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, 'acta_inspeccion_${insp['id']}.pdf'));
  await file.writeAsBytes(await doc.save());
  return file;
}
