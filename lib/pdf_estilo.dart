import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ---------------------------------------------------------------------
// Estilo común de todos los PDF de Consorcio Field:
// encabezado azul marino con franja naranja, tarjetas de colores,
// tablas con filas alternadas y pie con numeración.
// ---------------------------------------------------------------------
const PdfColor cNavy = PdfColor.fromInt(0xFF0B2545);
const PdfColor cAzul = PdfColor.fromInt(0xFF1565C0);
const PdfColor cNaranja = PdfColor.fromInt(0xFFF59E0B);
const PdfColor cVerde = PdfColor.fromInt(0xFF1B7F3B);
const PdfColor cRojo = PdfColor.fromInt(0xFFC62828);
const PdfColor cGris = PdfColor.fromInt(0xFFF4F6FA);
const PdfColor cTexto = PdfColor.fromInt(0xFF1F2937);
const PdfColor cTenue = PdfColor.fromInt(0xFF6B7280);
const PdfColor cVerdeClaro = PdfColor.fromInt(0xFFE8F5E9);
const PdfColor cRojoClaro = PdfColor.fromInt(0xFFFDECEA);
const PdfColor cNaranjaClaro = PdfColor.fromInt(0xFFFFF4DB);

/// Quita caracteres que la fuente estándar del PDF no soporta (emojis, etc.).
String limpio(dynamic t) {
  final s = (t ?? '').toString();
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x00A0) {
      b.write(' ');
    } else if (r < 0x250 || r == 0x20AC) {
      b.writeCharCode(r);
    } else {
      b.write(' ');
    }
  }
  return b.toString();
}

pw.BorderRadius br(double r) => pw.BorderRadius.all(pw.Radius.circular(r));

Future<pw.MemoryImage?> cargarLogo() async {
  try {
    final bytes = await rootBundle.load('assets/icon/icon.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

pw.Widget pdfEncabezado(String titulo, String subtitulo, pw.MemoryImage? logo, {String? etiqueta}) {
  return pw.Container(
    decoration: pw.BoxDecoration(color: cNavy, borderRadius: br(14)),
    child: pw.Column(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(16),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          if (logo != null)
            pw.Container(
              width: 52,
              height: 52,
              margin: const pw.EdgeInsets.only(right: 14),
              child: pw.ClipRRect(
                  horizontalRadius: 12,
                  verticalRadius: 12,
                  child: pw.Image(logo, fit: pw.BoxFit.cover)),
            ),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(limpio(titulo),
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(limpio(subtitulo),
                  style: const pw.TextStyle(color: PdfColor.fromInt(0xFFBFD3F2), fontSize: 11)),
            ]),
          ),
          if (etiqueta != null)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(color: cNaranja, borderRadius: br(20)),
              child: pw.Text(limpio(etiqueta),
                  style: pw.TextStyle(color: cNavy, fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ),
        ]),
      ),
      pw.Container(height: 5, color: cNaranja),
    ]),
  );
}

pw.Widget pdfChip(String t, PdfColor fondo, {PdfColor texto = PdfColors.white, double size = 9}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: pw.BoxDecoration(color: fondo, borderRadius: br(20)),
    child: pw.Text(limpio(t), style: pw.TextStyle(color: texto, fontSize: size, fontWeight: pw.FontWeight.bold)),
  );
}

pw.Widget pdfKpi(String titulo, String valor, PdfColor color) {
  return pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: color, borderRadius: br(12)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(limpio(titulo).toUpperCase(),
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 8.5)),
        pw.SizedBox(height: 5),
        pw.Text(limpio(valor),
            style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
      ]),
    ),
  );
}

pw.Widget pdfSeccion(String t, {PdfColor color = cAzul}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 7),
    child: pw.Row(children: [
      pw.Container(width: 5, height: 15, color: color),
      pw.SizedBox(width: 7),
      pw.Text(limpio(t), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: cNavy)),
    ]),
  );
}

pw.Widget pdfInfoCard(String titulo, List<List<String>> pares, PdfColor color) {
  return pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
      color: cGris,
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Container(width: 4, color: color),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(limpio(titulo).toUpperCase(),
                  style: pw.TextStyle(color: color, fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              for (final par in pares)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.RichText(
                    text: pw.TextSpan(children: [
                      pw.TextSpan(
                          text: '${limpio(par[0])}: ',
                          style: const pw.TextStyle(color: cTenue, fontSize: 9)),
                      pw.TextSpan(
                          text: limpio(par[1]),
                          style: pw.TextStyle(color: cTexto, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    ),
  );
}

pw.Widget pdfCelda(String t,
    {bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor color = cTexto,
    double size = 9.5}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: pw.Text(limpio(t),
        textAlign: align,
        style: pw.TextStyle(
            fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
  );
}

pw.Widget pdfTabla(List<String> cab, List<List<pw.Widget>> filas, List<double> flex,
    {PdfColor color = cNavy, List<pw.TextAlign>? alin}) {
  final widths = <int, pw.TableColumnWidth>{
    for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i])
  };
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: color),
      children: [
        for (var i = 0; i < cab.length; i++)
          pdfCelda(cab[i],
              bold: true,
              color: PdfColors.white,
              align: (alin != null && i < alin.length) ? alin[i] : pw.TextAlign.left),
      ],
    ),
  ];
  for (var i = 0; i < filas.length; i++) {
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: i.isOdd ? cGris : PdfColors.white),
      children: filas[i],
    ));
  }
  return pw.Table(columnWidths: widths, children: rows);
}

pw.Widget pdfPie(pw.Context c) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.5))),
    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Consorcio Field - desarrollado por Boris Javier Casanueva Muñoz',
          style: const pw.TextStyle(fontSize: 8, color: cTenue)),
      pw.Text('Pág. ${c.pageNumber} de ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: cTenue)),
    ]),
  );
}

Future<File> guardarPdf(pw.Document doc, String nombre) async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'informes'));
  await dir.create(recursive: true);
  final seguro = nombre.replaceAll(RegExp(r'[^A-Za-z0-9_\-.]'), '_');
  final f = File(p.join(dir.path, seguro));
  await f.writeAsBytes(await doc.save());
  return f;
}
