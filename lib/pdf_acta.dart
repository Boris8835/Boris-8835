import 'dart:convert';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_estilo.dart';
import 'widgets.dart' show esVideo, fmtFecha;

PdfColor _color(String e) => e == 'ok' ? cVerde : (e == 'obs' ? cNaranja : cRojo);
String _txt(String e) => e == 'ok' ? 'OK' : (e == 'obs' ? 'OBSERVACIÓN' : 'URGENTE');

Future<File> generarActaPdf(Map<String, dynamic> insp, Map<String, dynamic>? consorcio) async {
  final logo = await cargarLogo();
  final items = (jsonDecode((insp['items'] ?? '[]') as String) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final lat = insp['lat'];
  final lng = insp['lng'];
  final ok = items.where((i) => i['estado'] == 'ok').length;
  final obs = items.where((i) => i['estado'] == 'obs').length;
  final urg = items.where((i) => i['estado'] == 'urgente').length;

  final cuerpo = <pw.Widget>[
    pdfEncabezado('Acta de inspección', '${limpio(insp['consorcio_nombre'])}', logo, etiqueta: 'INSPECCIÓN'),
    pw.SizedBox(height: 12),
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pdfInfoCard(
          'Consorcio',
          [
            ['Nombre', '${insp['consorcio_nombre'] ?? '-'}'],
            ['Dirección', (consorcio?['direccion'] ?? '').toString().isEmpty ? '-' : '${consorcio!['direccion']}'],
            ['CUIT', (consorcio?['cuit'] ?? '').toString().isEmpty ? '-' : '${consorcio!['cuit']}'],
            ['Administrador', (consorcio?['admin_nombre'] ?? '').toString().isEmpty ? '-' : '${consorcio!['admin_nombre']}'],
          ],
          cAzul),
      pdfInfoCard(
          'Inspección',
          [
            ['Fecha y hora', fmtFecha(insp['fecha']?.toString(), hora: true)],
            ['GPS', lat == null ? 'No disponible' : '${(lat as num).toStringAsFixed(6)}, ${(lng as num).toStringAsFixed(6)}'],
            ['Ítems revisados', '${items.length}'],
          ],
          cNaranja),
    ]),
    pw.SizedBox(height: 12),
    pw.Row(children: [
      pdfKpi('Todo OK', '$ok', cVerde),
      pdfKpi('Observaciones', '$obs', cNaranja),
      pdfKpi('Urgentes', '$urg', cRojo),
    ]),
    pdfSeccion('Resultado del check-list'),
  ];

  for (final it in items) {
    final estado = (it['estado'] ?? 'ok').toString();
    final col = _color(estado);
    cuerpo.add(pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: cGris,
        border: pw.Border(left: pw.BorderSide(color: col, width: 5)),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(limpio(it['nombre']),
              style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: cNavy)),
          pdfChip(_txt(estado), col),
        ]),
        if ((it['ubicacion'] ?? '').toString().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text('Ubicación: ${limpio(it['ubicacion'])}', style: const pw.TextStyle(fontSize: 9.5)),
        ],
        if ((it['nota'] ?? '').toString().isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text('Nota: ${limpio(it['nota'])}', style: const pw.TextStyle(fontSize: 9.5)),
        ],
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
          child: pw.ClipRRect(
              horizontalRadius: 8,
              verticalRadius: 8,
              child: pw.Image(pw.MemoryImage(await File(f).readAsBytes()), fit: pw.BoxFit.cover)),
        ));
      }
      cuerpo.add(pw.Wrap(children: imgs));
    }
  }

  if ((insp['notas'] ?? '').toString().isNotEmpty) {
    cuerpo.add(pdfSeccion('Observaciones generales', color: cNaranja));
    cuerpo.add(pw.Text(limpio(insp['notas']), style: const pw.TextStyle(fontSize: 10)));
  }
  cuerpo.add(pw.SizedBox(height: 40));
  cuerpo.add(pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
    pw.Column(children: [
      pw.Container(width: 200, height: 0.8, color: cTexto),
      pw.SizedBox(height: 3),
      pw.Text('Firma del administrador', style: const pw.TextStyle(fontSize: 9, color: cTenue)),
    ]),
  ]));

  final doc = pw.Document(title: 'Acta de inspección', author: 'Consorcio Field');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: pdfPie,
    build: (c) => cuerpo,
  ));
  return guardarPdf(doc, 'acta_inspeccion_${insp['id']}.pdf');
}
