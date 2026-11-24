import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_estilo.dart';
import 'widgets.dart' show fmtFecha, fmtPlata, periodoTexto;

double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;
String _plata(dynamic v) => limpio(fmtPlata(_n(v)));

pw.Widget _estadoChip(String estado, {double size = 9}) {
  final pagado = estado == 'Pagado';
  return pdfChip(pagado ? 'PAGADO' : 'DEBE', pagado ? cVerde : cRojo, size: size);
}

// =====================================================================
// 1) Expensa de UNA unidad (recibo / aviso de deuda)
// =====================================================================
Future<File> pdfExpensaUnidad(
  Map<String, dynamic> e,
  Map<String, dynamic>? cons,
  Map<String, dynamic>? unidad,
  List<Map<String, dynamic>> gastos,
) async {
  final logo = await cargarLogo();
  final pagado = e['estado'] == 'Pagado';
  final coef = _n(e['coeficiente']);
  final periodo = periodoTexto(e['periodo']?.toString());
  final colorEstado = pagado ? cVerde : cRojo;

  final doc = pw.Document(title: 'Expensa $periodo', author: 'Consorcio Field');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: pdfPie,
    build: (c) => [
      pdfEncabezado('Expensa $periodo',
          '${e['consorcio_nombre'] ?? ''}${(cons?['direccion'] ?? '').toString().isEmpty ? '' : '  -  ${cons!['direccion']}'}',
          logo,
          etiqueta: 'EXPENSAS'),
      pw.SizedBox(height: 12),
      // Banner de estado
      pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: pagado ? cVerdeClaro : cRojoClaro,
          border: pw.Border.all(color: colorEstado, width: 1.5),
          borderRadius: br(12),
        ),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(pagado ? 'EXPENSA PAGADA' : 'EXPENSA PENDIENTE DE PAGO',
                style: pw.TextStyle(color: colorEstado, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text(
                pagado
                    ? 'Pago registrado el ${fmtFecha(e['fecha_pago']?.toString())} - ${limpio(e['medio_pago'] ?? '')}'
                    : 'Importe a abonar: ${_plata(e['total'])}',
                style: const pw.TextStyle(color: cTexto, fontSize: 10.5)),
          ]),
          pdfChip(pagado ? 'PAGADO' : 'DEBE', colorEstado, size: 13),
        ]),
      ),
      pw.SizedBox(height: 12),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pdfInfoCard(
            'Unidad',
            [
              ['Ubicación', '${e['unidad_txt'] ?? ''}'],
              ['Propietario', (e['propietario'] ?? '').toString().isEmpty ? '-' : '${e['propietario']}'],
              ['Coeficiente', '${coef.toStringAsFixed(2)} %'],
              if ((unidad?['telefono'] ?? '').toString().isNotEmpty) ['Teléfono', '${unidad!['telefono']}'],
            ],
            cAzul),
        pdfInfoCard(
            'Administración',
            [
              ['Consorcio', '${e['consorcio_nombre'] ?? ''}'],
              ['CUIT', (cons?['cuit'] ?? '').toString().isEmpty ? '-' : '${cons!['cuit']}'],
              ['Administrador', (cons?['admin_nombre'] ?? '').toString().isEmpty ? '-' : '${cons!['admin_nombre']}'],
              ['Contacto', '${cons?['admin_tel'] ?? ''} ${cons?['admin_email'] ?? ''}'.trim().isEmpty
                  ? '-'
                  : '${cons?['admin_tel'] ?? ''} ${cons?['admin_email'] ?? ''}'.trim()],
            ],
            cNaranja),
      ]),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        pdfKpi('Gastos ordinarios', _plata(e['ordinarias']), cAzul),
        pdfKpi('Gastos extraordinarios', _plata(e['extraordinarias']), cNaranja),
        pdfKpi('TOTAL DEL PERÍODO', _plata(e['total']), colorEstado),
      ]),
      pdfSeccion('Detalle de gastos del período'),
      if (gastos.isEmpty)
        pw.Text('No hay detalle de gastos disponible para este período.',
            style: const pw.TextStyle(fontSize: 10, color: cTenue))
      else
        pdfTabla(
          ['Concepto', 'Tipo', 'Gasto total', 'Su parte'],
          [
            for (final g in gastos)
              [
                pdfCelda('${g['concepto'] ?? ''}'),
                pdfCelda(g['tipo'] == 'Expensa extraordinaria' ? 'Extraordinaria' : 'Ordinaria',
                    color: g['tipo'] == 'Expensa extraordinaria' ? cNaranja : cAzul, bold: true),
                pdfCelda(_plata(g['monto']), align: pw.TextAlign.right),
                pdfCelda(_plata(_n(g['monto']) * coef / 100), align: pw.TextAlign.right, bold: true),
              ]
          ],
          [4, 2, 2, 2],
          alin: [pw.TextAlign.left, pw.TextAlign.left, pw.TextAlign.right, pw.TextAlign.right],
        ),
      pw.SizedBox(height: 14),
      pw.Text(
          'La parte de cada unidad se calcula según su coeficiente de expensas (${coef.toStringAsFixed(2)} %). '
          'Ante cualquier consulta comuníquese con la administración.',
          style: const pw.TextStyle(fontSize: 8.5, color: cTenue)),
    ],
  ));
  return guardarPdf(doc, 'expensa_${e['periodo']}_${e['unidad_txt']}.pdf');
}

// =====================================================================
// 2) Estado de cuenta del propietario (todas sus expensas)
// =====================================================================
Future<File> pdfEstadoCuenta(
  Map<String, dynamic> unidad,
  Map<String, dynamic>? cons,
  List<Map<String, dynamic>> expensas, [
  List<Map<String, dynamic>> pagos = const [],
]) async {
  final logo = await cargarLogo();
  final saldo = _n(unidad['saldo']);
  final debe = saldo > 0.005;
  double emitido = 0, cobrado = 0;
  for (final x in expensas) {
    emitido += _n(x['total']);
    if (x['estado'] == 'Pagado') cobrado += _n(x['total']);
  }
  for (final pg in pagos) {
    cobrado += _n(pg['monto']);
  }
  final nombreUnidad = 'Piso ${unidad['piso'] ?? ''} - Unidad ${unidad['numero'] ?? ''}';
  final doc = pw.Document(title: 'Estado de cuenta', author: 'Consorcio Field');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: pdfPie,
    build: (c) => [
      pdfEncabezado('Estado de cuenta', '${cons?['nombre'] ?? ''}  -  $nombreUnidad', logo,
          etiqueta: 'PROPIETARIO'),
      pw.SizedBox(height: 12),
      pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: debe ? cRojoClaro : cVerdeClaro,
          border: pw.Border.all(color: debe ? cRojo : cVerde, width: 1.5),
          borderRadius: br(12),
        ),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(debe ? 'SALDO PENDIENTE DE PAGO' : 'CUENTA AL DÍA',
                style: pw.TextStyle(color: debe ? cRojo : cVerde, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text(debe ? 'Total adeudado: ${_plata(saldo)}' : 'No registra deuda de expensas.',
                style: const pw.TextStyle(color: cTexto, fontSize: 10.5)),
          ]),
          pdfChip(debe ? 'DEBE' : 'AL DÍA', debe ? cRojo : cVerde, size: 13),
        ]),
      ),
      pw.SizedBox(height: 12),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pdfInfoCard(
            'Propietario',
            [
              ['Nombre', (unidad['propietario'] ?? '').toString().isEmpty ? '-' : '${unidad['propietario']}'],
              ['Teléfono', (unidad['telefono'] ?? '').toString().isEmpty ? '-' : '${unidad['telefono']}'],
              ['Unidad', nombreUnidad],
              ['Coeficiente', '${_n(unidad['coeficiente']).toStringAsFixed(2)} %'],
            ],
            cAzul),
        pdfInfoCard(
            'Consorcio',
            [
              ['Nombre', '${cons?['nombre'] ?? '-'}'],
              ['Dirección', (cons?['direccion'] ?? '').toString().isEmpty ? '-' : '${cons!['direccion']}'],
              ['Administrador', (cons?['admin_nombre'] ?? '').toString().isEmpty ? '-' : '${cons!['admin_nombre']}'],
              ['Contacto', (cons?['admin_tel'] ?? '').toString().isEmpty ? '-' : '${cons!['admin_tel']}'],
            ],
            cNaranja),
      ]),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        pdfKpi('Total emitido', _plata(emitido), cAzul),
        pdfKpi('Total pagado', _plata(cobrado), cVerde),
        pdfKpi('Saldo adeudado', _plata(saldo), debe ? cRojo : cVerde),
      ]),
      pdfSeccion('Detalle por período'),
      if (expensas.isEmpty)
        pw.Text('Todavía no hay expensas emitidas para esta unidad.',
            style: const pw.TextStyle(fontSize: 10, color: cTenue))
      else
        pdfTabla(
          ['Período', 'Ordinarias', 'Extraord.', 'Total', 'Estado', 'Fecha de pago'],
          [
            for (final x in expensas)
              [
                pdfCelda(periodoTexto(x['periodo']?.toString()), bold: true),
                pdfCelda(_plata(x['ordinarias']), align: pw.TextAlign.right),
                pdfCelda(_plata(x['extraordinarias']), align: pw.TextAlign.right),
                pdfCelda(_plata(x['total']), align: pw.TextAlign.right, bold: true),
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Align(alignment: pw.Alignment.centerLeft, child: _estadoChip('${x['estado']}'))),
                pdfCelda(x['estado'] == 'Pagado' ? fmtFecha(x['fecha_pago']?.toString()) : '-'),
              ]
          ],
          [3, 2.4, 2.2, 2.4, 1.8, 2.2],
          alin: [
            pw.TextAlign.left,
            pw.TextAlign.right,
            pw.TextAlign.right,
            pw.TextAlign.right,
            pw.TextAlign.left,
            pw.TextAlign.left
          ],
        ),
      if (pagos.isNotEmpty) ...[
        pdfSeccion('Pagos registrados', color: cVerde),
        pdfTabla(
          ['Fecha', 'Concepto', 'Forma de pago', 'Monto'],
          [
            for (final pg in pagos)
              [
                pdfCelda(fmtFecha(pg['fecha']?.toString())),
                pdfCelda('${pg['concepto'] ?? ''}', bold: true),
                pdfCelda('${pg['medio'] ?? ''}'),
                pdfCelda(_plata(pg['monto']), align: pw.TextAlign.right, bold: true),
              ]
          ],
          [2, 3, 3, 2.4],
          color: cVerde,
          alin: [pw.TextAlign.left, pw.TextAlign.left, pw.TextAlign.left, pw.TextAlign.right],
        ),
      ],
      pw.SizedBox(height: 12),
      pw.Text('Documento generado el ${fmtFecha(DateTime.now().toIso8601String(), hora: true)}.',
          style: const pw.TextStyle(fontSize: 8.5, color: cTenue)),
    ],
  ));
  return guardarPdf(doc, 'estado_cuenta_${cons?['nombre'] ?? 'consorcio'}_${unidad['piso']}${unidad['numero']}.pdf');
}

// =====================================================================
// 3) Liquidación general del consorcio (todas las unidades)
// =====================================================================
/// [filas]: una por unidad, con unidad_txt, propietario, coeficiente,
/// ordinarias, extraordinarias, total y (si ya fue emitida) estado.
Future<File> pdfLiquidacion(
  Map<String, dynamic>? cons,
  String consorcioNombre,
  String periodo,
  List<Map<String, dynamic>> gastos,
  List<Map<String, dynamic>> filas,
  bool emitida,
) async {
  final logo = await cargarLogo();
  double ord = 0, ext = 0, cobrado = 0, pendiente = 0;
  for (final f in filas) {
    ord += _n(f['ordinarias']);
    ext += _n(f['extraordinarias']);
    if (emitida) {
      if (f['estado'] == 'Pagado') {
        cobrado += _n(f['total']);
      } else {
        pendiente += _n(f['total']);
      }
    }
  }
  final doc = pw.Document(title: 'Liquidación ${periodoTexto(periodo)}', author: 'Consorcio Field');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: pdfPie,
    build: (c) => [
      pdfEncabezado('Liquidación de expensas', '$consorcioNombre  -  ${periodoTexto(periodo)}', logo,
          etiqueta: emitida ? 'EMITIDA' : 'BORRADOR'),
      pw.SizedBox(height: 12),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pdfInfoCard(
            'Consorcio',
            [
              ['Nombre', consorcioNombre],
              ['CUIT', (cons?['cuit'] ?? '').toString().isEmpty ? '-' : '${cons!['cuit']}'],
              ['Dirección', (cons?['direccion'] ?? '').toString().isEmpty ? '-' : '${cons!['direccion']}'],
            ],
            cAzul),
        pdfInfoCard(
            'Administración',
            [
              ['Administrador', (cons?['admin_nombre'] ?? '').toString().isEmpty ? '-' : '${cons!['admin_nombre']}'],
              ['Teléfono', (cons?['admin_tel'] ?? '').toString().isEmpty ? '-' : '${cons!['admin_tel']}'],
              ['Correo', (cons?['admin_email'] ?? '').toString().isEmpty ? '-' : '${cons!['admin_email']}'],
            ],
            cNaranja),
      ]),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        pdfKpi('Gastos ordinarios', _plata(ord), cAzul),
        pdfKpi('Gastos extraordinarios', _plata(ext), cNaranja),
        pdfKpi('TOTAL A REPARTIR', _plata(ord + ext), cNavy),
      ]),
      if (emitida) ...[
        pw.SizedBox(height: 8),
        pw.Row(children: [
          pdfKpi('Cobrado', _plata(cobrado), cVerde),
          pdfKpi('Pendiente de cobro', _plata(pendiente), cRojo),
        ]),
      ],
      pdfSeccion('Gastos del período'),
      if (gastos.isEmpty)
        pw.Text('Sin gastos cargados en el período.', style: const pw.TextStyle(fontSize: 10, color: cTenue))
      else
        pdfTabla(
          ['Fecha', 'Concepto', 'Proveedor', 'Tipo', 'Monto'],
          [
            for (final g in gastos)
              [
                pdfCelda(fmtFecha(g['fecha']?.toString())),
                pdfCelda('${g['concepto'] ?? ''}', bold: true),
                pdfCelda('${g['proveedor'] ?? ''}'),
                pdfCelda(g['tipo'] == 'Expensa extraordinaria' ? 'Extraord.' : 'Ordinaria',
                    color: g['tipo'] == 'Expensa extraordinaria' ? cNaranja : cAzul, bold: true),
                pdfCelda(_plata(g['monto']), align: pw.TextAlign.right, bold: true),
              ]
          ],
          [2, 4, 3, 2, 2.4],
          alin: [pw.TextAlign.left, pw.TextAlign.left, pw.TextAlign.left, pw.TextAlign.left, pw.TextAlign.right],
        ),
      pdfSeccion('Reparto por unidad', color: cNaranja),
      pdfTabla(
        emitida
            ? ['Unidad', 'Propietario', 'Coef.', 'Ordinarias', 'Extraord.', 'Total', 'Estado']
            : ['Unidad', 'Propietario', 'Coef.', 'Ordinarias', 'Extraord.', 'Total'],
        [
          for (final f in filas)
            [
              pdfCelda('${f['unidad_txt'] ?? ''}', bold: true),
              pdfCelda('${f['propietario'] ?? ''}'),
              pdfCelda('${_n(f['coeficiente']).toStringAsFixed(2)}%', align: pw.TextAlign.right),
              pdfCelda(_plata(f['ordinarias']), align: pw.TextAlign.right),
              pdfCelda(_plata(f['extraordinarias']), align: pw.TextAlign.right),
              pdfCelda(_plata(f['total']), align: pw.TextAlign.right, bold: true),
              if (emitida)
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Align(alignment: pw.Alignment.centerLeft, child: _estadoChip('${f['estado']}', size: 8))),
            ]
        ],
        emitida ? [2.4, 3.4, 1.4, 2.4, 2.2, 2.4, 1.8] : [2.4, 3.6, 1.4, 2.6, 2.4, 2.6],
        color: cNavy,
        alin: [
          pw.TextAlign.left,
          pw.TextAlign.left,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.left
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Text('Documento generado el ${fmtFecha(DateTime.now().toIso8601String(), hora: true)}.',
          style: const pw.TextStyle(fontSize: 8.5, color: cTenue)),
    ],
  ));
  return guardarPdf(doc, 'liquidacion_${consorcioNombre}_$periodo.pdf');
}
