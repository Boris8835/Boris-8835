import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'db.dart';
import 'pdf_estilo.dart';
import 'widgets.dart' show fmtFecha, fmtPlata, periodoTexto;

double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;
double _r2(double v) => double.parse(v.toStringAsFixed(2));
const double kPorcFondoReserva = 10;

class FilaFondo {
  final String concepto;
  final double entrada; // Entrada / Debe
  final double salida; // Salida / Haber
  final double saldo;
  final String tipo; // inicial, expensas, reserva, deudas, ingreso, gasto
  FilaFondo(this.concepto, this.entrada, this.salida, this.saldo, this.tipo);
}

class MovimientoFondos {
  final String periodo;
  final List<FilaFondo> filas;
  final double saldoInicial, expensas, reserva, deudas, otros, gastos, resultado;
  MovimientoFondos(this.periodo, this.filas, this.saldoInicial, this.expensas, this.reserva, this.deudas,
      this.otros, this.gastos, this.resultado);
}

String _per(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
String _perDe(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString());
  return d == null ? '' : _per(d.toLocal());
}

class Fondos {
  /// Calcula el movimiento de fondos del mes. El saldo inicial es el resultado
  /// del mes anterior (se arrastra desde el primer mes con movimientos).
  /// [reservaApartada]: true = el 10 % se aparta (Salida); false = se suma como Entrada.
  static Future<MovimientoFondos> calcular(int consorcioId, String periodo, {bool reservaApartada = true}) async {
    final gastos = await Db.all('gastos', where: 'consorcio_id = ?', args: [consorcioId], orderBy: 'fecha ASC');
    final ingresos = await Db.all('ingresos', where: 'consorcio_id = ?', args: [consorcioId], orderBy: 'fecha ASC');
    final pagos = await Db.all('pagos', where: 'consorcio_id = ?', args: [consorcioId], orderBy: 'fecha ASC');
    final exp = await Db.all('expensas', where: 'consorcio_id = ?', args: [consorcioId]);
    final porId = {for (final e in exp) e['id']: e};

    // primer mes con movimientos
    final meses = <String>{
      for (final g in gastos) _perDe(g['fecha']),
      for (final i in ingresos) _perDe(i['fecha']),
      for (final p in pagos) _perDe(p['fecha']),
    }..remove('');
    var inicio = meses.isEmpty ? periodo : (meses.toList()..sort()).first;
    if (inicio.compareTo(periodo) > 0) inicio = periodo;

    // ¿el pago es de la expensa de ese mismo mes o de una deuda anterior?
    bool esDeuda(Map<String, dynamic> p, String mes) {
      final e = p['expensa_id'] == null ? null : porId[p['expensa_id']];
      if (e == null) return true; // pago sin detalle: saldo anterior
      if ((e['tipo'] ?? 'Expensa') == 'Saldo anterior') return true;
      return (e['periodo'] ?? '').toString().compareTo(mes) < 0;
    }

    double arrastre = 0;
    var mes = inicio;
    late MovimientoFondos ultimo;
    while (true) {
      final filas = <FilaFondo>[];
      final pm = pagos.where((p) => _perDe(p['fecha']) == mes).toList();
      final cobradas = _r2(pm.where((p) => !esDeuda(p, mes)).fold(0.0, (a, p) => a + _n(p['monto'])));
      final deudas = _r2(pm.where((p) => esDeuda(p, mes)).fold(0.0, (a, p) => a + _n(p['monto'])));
      final reserva = _r2(cobradas * kPorcFondoReserva / 100);
      final otrosList = ingresos.where((i) => _perDe(i['fecha']) == mes).toList();
      final otros = _r2(otrosList.fold(0.0, (a, i) => a + _n(i['monto'])));
      final gl = gastos.where((g) => _perDe(g['fecha']) == mes).toList();
      final totGastos = _r2(gl.fold(0.0, (a, g) => a + _n(g['monto'])));

      var saldo = arrastre;
      filas.add(FilaFondo('Saldo inicial', saldo >= 0 ? saldo : 0, saldo < 0 ? -saldo : 0, saldo, 'inicial'));
      saldo += cobradas;
      filas.add(FilaFondo('Expensas comunes', cobradas, 0, _r2(saldo), 'expensas'));
      if (reservaApartada) {
        saldo -= reserva;
        filas.add(FilaFondo('Fondo de reserva (${kPorcFondoReserva.toStringAsFixed(0)} %)', 0, reserva, _r2(saldo), 'reserva'));
      } else {
        saldo += reserva;
        filas.add(FilaFondo('Fondo de reserva (${kPorcFondoReserva.toStringAsFixed(0)} %)', reserva, 0, _r2(saldo), 'reserva'));
      }
      saldo += deudas;
      filas.add(FilaFondo('Deudas y convenios', deudas, 0, _r2(saldo), 'deudas'));
      for (final i in otrosList) {
        saldo += _n(i['monto']);
        filas.add(FilaFondo('${i['concepto'] ?? 'Ingreso'}', _n(i['monto']), 0, _r2(saldo), 'ingreso'));
      }
      for (final g in gl) {
        saldo -= _n(g['monto']);
        filas.add(FilaFondo('Gasto: ${g['concepto'] ?? ''}', 0, _n(g['monto']), _r2(saldo), 'gasto'));
      }
      saldo = _r2(saldo);
      ultimo = MovimientoFondos(mes, filas, arrastre, cobradas, reserva, deudas, otros, totGastos, saldo);
      if (mes == periodo) break;
      arrastre = saldo;
      final d = DateTime.parse('$mes-01');
      mes = _per(DateTime(d.year, d.month + 1));
    }
    return ultimo;
  }
}

Future<File> pdfMovimientoFondos(Map<String, dynamic>? cons, String consorcioNombre, MovimientoFondos m) async {
  final logo = await cargarLogo();
  final firma = await cargarFirma(cons);
  String pl(num v) => limpio(fmtPlata(v));
  final ok = m.resultado >= 0;
  final doc = pw.Document(title: 'Movimiento de fondos', author: 'Consorcio Field');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: pdfPie,
    build: (c) => [
      pdfEncabezado('Movimiento de fondos', '$consorcioNombre  -  ${periodoTexto(m.periodo)}', logo, etiqueta: 'FONDOS'),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        pdfKpi('Saldo inicial', pl(m.saldoInicial), cAzul),
        pdfKpi('Total gastos', pl(m.gastos), cRojo),
        pdfKpi('RESULTADO', pl(m.resultado), ok ? cVerde : cRojo),
      ]),
      pdfSeccion('Cuadro de movimientos', color: cNavy),
      pdfTabla(
        ['Concepto', 'Entrada / Debe', 'Salida / Haber', 'Saldo'],
        [
          for (final f in m.filas)
            [
              pdfCelda(f.concepto, bold: f.tipo != 'gasto' && f.tipo != 'ingreso'),
              pdfCelda(f.entrada > 0 ? pl(f.entrada) : '-', align: pw.TextAlign.right, color: cVerde),
              pdfCelda(f.salida > 0 ? pl(f.salida) : '-', align: pw.TextAlign.right, color: cRojo),
              pdfCelda(pl(f.saldo), align: pw.TextAlign.right, bold: true),
            ],
          [
            pdfCelda('RESULTADO DEL MES', bold: true),
            pdfCelda(pl(m.filas.fold(0.0, (a, f) => a + f.entrada)), align: pw.TextAlign.right, bold: true, color: cVerde),
            pdfCelda(pl(m.filas.fold(0.0, (a, f) => a + f.salida)), align: pw.TextAlign.right, bold: true, color: cRojo),
            pdfCelda(pl(m.resultado), align: pw.TextAlign.right, bold: true, color: ok ? cVerde : cRojo),
          ],
        ],
        [5, 2.6, 2.6, 2.6],
        alin: [pw.TextAlign.left, pw.TextAlign.right, pw.TextAlign.right, pw.TextAlign.right],
      ),
      pw.SizedBox(height: 8),
      pw.Text(
          'El saldo inicial es el resultado del mes anterior. Expensas comunes: cobradas en el mes. '
          'Deudas y convenios: expensas atrasadas pagadas por los propietarios.',
          style: const pw.TextStyle(fontSize: 8.5, color: cTenue)),
      pw.SizedBox(height: 6),
      pw.Text('Documento generado el ${fmtFecha(DateTime.now().toIso8601String(), hora: true)}.',
          style: const pw.TextStyle(fontSize: 8.5, color: cTenue)),
      pdfBloqueFirma(cons, firma),
    ],
  ));
  return guardarPdf(doc, 'movimiento_fondos_${consorcioNombre}_${m.periodo}.pdf');
}
