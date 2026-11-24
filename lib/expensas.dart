import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'db.dart';
import 'pdf_informes.dart';
import 'widgets.dart';

double _r2(double v) => double.parse(v.toStringAsFixed(2));
double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;

// =====================================================================
// Lógica de expensas emitidas: Debe / Pagado
// =====================================================================
class Expensas {
  static Future<List<Map<String, dynamic>>> delPeriodo(int consorcioId, String periodo) =>
      Db.all('expensas',
          where: 'consorcio_id = ? AND periodo = ?', args: [consorcioId, periodo], orderBy: 'id ASC');

  static Future<List<Map<String, dynamic>>> deUnidad(int unidadId) =>
      Db.all('expensas', where: 'unidad_id = ?', args: [unidadId], orderBy: 'periodo DESC');

  static Future<List<Map<String, dynamic>>> gastosDelPeriodo(int consorcioId, String periodo) async {
    final todos = await Db.all('gastos', where: 'consorcio_id = ?', args: [consorcioId], orderBy: 'fecha ASC');
    return todos.where((g) {
      final d = DateTime.tryParse((g['fecha'] ?? '').toString());
      if (d == null) return false;
      final mes = d.month.toString().padLeft(2, '0');
      return '${d.year}-$mes' == periodo;
    }).toList();
  }

  /// Crea una expensa "Debe" por cada unidad y suma el importe a su saldo.
  static Future<void> emitir({
    required int consorcioId,
    required String consorcioNombre,
    required String periodo,
    required List<Map<String, dynamic>> unidades,
    required double totalOrd,
    required double totalExt,
  }) async {
    final ahora = DateTime.now().toIso8601String();
    double total = 0;
    for (final u in unidades) {
      final coef = _n(u['coeficiente']);
      final ord = _r2(totalOrd * coef / 100);
      final ext = _r2(totalExt * coef / 100);
      final t = _r2(ord + ext);
      total += t;
      await Db.save('expensas', {
        'consorcio_id': consorcioId,
        'consorcio_nombre': consorcioNombre,
        'unidad_id': u['id'],
        'unidad_txt': 'Piso ${u['piso']} - ${u['numero']}',
        'propietario': u['propietario'] ?? '',
        'periodo': periodo,
        'coeficiente': coef,
        'ordinarias': ord,
        'extraordinarias': ext,
        'total': t,
        'estado': 'Debe',
        'fecha_emision': ahora,
      });
      final nuevo = Map<String, dynamic>.from(u);
      nuevo['saldo'] = _r2(_n(u['saldo']) + t);
      await Db.save('unidades', nuevo);
    }
    await Db.save('liquidaciones', {
      'consorcio_id': consorcioId,
      'periodo': periodo,
      'total': _r2(total),
      'detalle': '{"v":3}',
      'aplicada': ahora,
    });
  }

  static Future<List<Map<String, dynamic>>> pagosDeUnidad(int unidadId) =>
      Db.all('pagos', where: 'unidad_id = ?', args: [unidadId], orderBy: 'id DESC');

  /// Deuda del saldo que NO corresponde a una expensa emitida (cargada con la versión anterior o a mano).
  static double saldoSinDetalle(Map<String, dynamic> unidad, List<Map<String, dynamic>> exp) {
    final enFilas = exp.where((e) => e['estado'] != 'Pagado').fold(0.0, (a, e) => a + _n(e['total']));
    final r = _n(unidad['saldo']) - enFilas;
    return r > 0.005 ? _r2(r) : 0.0;
  }

  static Future<void> pagarSaldo(Map<String, dynamic> unidad, double monto, String medio, DateTime fecha) async {
    await Db.save('pagos', {
      'unidad_id': unidad['id'],
      'consorcio_id': unidad['consorcio_id'],
      'fecha': fecha.toIso8601String(),
      'monto': _r2(monto),
      'medio': medio,
      'concepto': 'Saldo anterior',
    });
    await _ajustarSaldo(unidad['id'], -_r2(monto));
  }

  static Future<void> anularPago(Map<String, dynamic> pago) async {
    await Db.delete('pagos', pago['id'] as int);
    await _ajustarSaldo(pago['unidad_id'], _n(pago['monto']));
  }

  static Future<void> _ajustarSaldo(dynamic unidadId, double delta) async {
    if (unidadId == null) return;
    final u = await Db.one('unidades', unidadId as int);
    if (u == null) return;
    u['saldo'] = _r2(_n(u['saldo']) + delta);
    await Db.save('unidades', u);
  }

  static Future<void> pagar(Map<String, dynamic> e, String medio, DateTime fecha) async {
    final nuevo = Map<String, dynamic>.from(e);
    nuevo['estado'] = 'Pagado';
    nuevo['medio_pago'] = medio;
    nuevo['fecha_pago'] = fecha.toIso8601String();
    await Db.save('expensas', nuevo);
    await _ajustarSaldo(e['unidad_id'], -_n(e['total']));
  }

  static Future<void> deshacerPago(Map<String, dynamic> e) async {
    final nuevo = Map<String, dynamic>.from(e);
    nuevo['estado'] = 'Debe';
    nuevo['medio_pago'] = null;
    nuevo['fecha_pago'] = null;
    await Db.save('expensas', nuevo);
    await _ajustarSaldo(e['unidad_id'], _n(e['total']));
  }

  /// Anula la emisión: quita las expensas del mes y descuenta lo que seguía debiéndose.
  static Future<void> revertirEmision(int consorcioId, String periodo) async {
    final filas = await delPeriodo(consorcioId, periodo);
    for (final e in filas) {
      if (e['estado'] != 'Pagado') await _ajustarSaldo(e['unidad_id'], -_n(e['total']));
      await Db.delete('expensas', e['id'] as int);
    }
    await Db.deleteWhere('liquidaciones', 'consorcio_id = ? AND periodo = ?', [consorcioId, periodo]);
  }
}

// =====================================================================
// Compartir PDF (el menú de Android permite elegir WhatsApp)
// =====================================================================
Future<void> _enviarPdf(BuildContext context, Future<dynamic> Function() generar, String texto) async {
  try {
    final f = await generar();
    await Share.shareXFiles([XFile(f.path as String, mimeType: 'application/pdf')], text: texto);
  } catch (err) {
    if (context.mounted) aviso(context, 'No se pudo generar el PDF: $err');
  }
}

Future<void> compartirExpensaUnidad(BuildContext context, Map<String, dynamic> e) {
  return _enviarPdf(context, () async {
    final cons = await Db.one('consorcios', e['consorcio_id'] as int);
    final unidad = e['unidad_id'] == null ? null : await Db.one('unidades', e['unidad_id'] as int);
    final gastos = await Expensas.gastosDelPeriodo(e['consorcio_id'] as int, e['periodo'].toString());
    return pdfExpensaUnidad(e, cons, unidad, gastos);
  },
      'Expensa ${periodoTexto(e['periodo']?.toString())} - ${e['consorcio_nombre']} - ${e['unidad_txt']}: '
      '${fmtPlata(_n(e['total']))} (${e['estado'] == 'Pagado' ? 'PAGADO' : 'DEBE'})');
}

Future<void> compartirEstadoCuenta(BuildContext context, int unidadId) {
  return _enviarPdf(context, () async {
    final unidad = (await Db.one('unidades', unidadId))!;
    final cons = await Db.one('consorcios', unidad['consorcio_id'] as int);
    final exp = await Expensas.deUnidad(unidadId);
    final pagos = await Expensas.pagosDeUnidad(unidadId);
    return pdfEstadoCuenta(unidad, cons, exp, pagos);
  }, 'Estado de cuenta de expensas');
}

// =====================================================================
// Widgets
// =====================================================================
class EstadoPago extends StatelessWidget {
  final String estado;
  const EstadoPago(this.estado, {super.key});

  @override
  Widget build(BuildContext context) {
    final pagado = estado == 'Pagado';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: pagado ? kVerde : kRojo, borderRadius: BorderRadius.circular(20)),
      child: Text(pagado ? 'PAGADO' : 'DEBE',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
    );
  }
}

/// "DEBE $x" en rojo o "AL DÍA" en verde, según el saldo de la unidad.
class EstadoDeuda extends StatelessWidget {
  final num? saldo;
  const EstadoDeuda(this.saldo, {super.key});

  @override
  Widget build(BuildContext context) {
    final debe = (saldo ?? 0) > 0.005;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: debe ? kRojo : kVerde, borderRadius: BorderRadius.circular(20)),
        child: Text(debe ? 'DEBE' : 'AL DÍA',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
      ),
      if (debe)
        Text(fmtPlata(saldo), style: const TextStyle(color: kRojo, fontWeight: FontWeight.w800, fontSize: 14)),
    ]);
  }
}

Future<bool> dialogoPago(BuildContext context, Map<String, dynamic> e) async {
  String medio = 'Efectivo';
  DateTime fecha = DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text('Asentar pago'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${e['unidad_txt']}${(e['propietario'] ?? '').toString().isEmpty ? '' : ' · ${e['propietario']}'}\n'
                'Expensa ${periodoTexto(e['periodo']?.toString())}\n'
                'Importe: ${fmtPlata(_n(e['total']))}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            const Text('Forma de pago', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 6),
            SelectorEstado(
                opciones: const ['Efectivo', 'Transferencia', 'Cheque', 'Otro'],
                valor: medio,
                onChanged: (v) => setD(() => medio = v)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              icon: const Icon(Icons.event),
              label: Text('Fecha de pago: ${fmtFecha(fecha.toIso8601String())}'),
              onPressed: () async {
                final f = await elegirFecha(c, fecha);
                if (f != null) setD(() => fecha = f);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kVerde),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('MARCAR PAGADO')),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  await Expensas.pagar(e, medio, fecha);
  return true;
}

/// Tarjeta de una expensa: estado DEBE/PAGADO, botón Pagado y PDF para WhatsApp.
class TarjetaExpensa extends StatelessWidget {
  final Map<String, dynamic> e;
  final bool mostrarUnidad;
  final Future<void> Function() onCambio;
  const TarjetaExpensa({super.key, required this.e, required this.mostrarUnidad, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    final pagado = e['estado'] == 'Pagado';
    final titulo = mostrarUnidad
        ? '${e['unidad_txt']}${(e['propietario'] ?? '').toString().isEmpty ? '' : ' · ${e['propietario']}'}'
        : periodoTexto(e['periodo']?.toString());
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), side: BorderSide(color: pagado ? kVerde : kRojo, width: 2.5)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            EstadoPago('${e['estado']}'),
          ]),
          const SizedBox(height: 4),
          Text(fmtPlata(_n(e['total'])), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          Text('Ord. ${fmtPlata(_n(e['ordinarias']))} · Extra ${fmtPlata(_n(e['extraordinarias']))}',
              style: const TextStyle(fontSize: 14)),
          if (pagado)
            Text('Pagado el ${fmtFecha(e['fecha_pago']?.toString())} · ${e['medio_pago'] ?? ''}',
                style: const TextStyle(fontSize: 15, color: kVerde, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: pagado
                  ? OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                      onPressed: () async {
                        if (!await confirmar(context, 'Se vuelve a marcar como DEBE y se suma al saldo.',
                            boton: 'Deshacer pago')) {
                          return;
                        }
                        await Expensas.deshacerPago(e);
                        await onCambio();
                      },
                      icon: const Icon(Icons.undo),
                      label: const Text('Deshacer pago'))
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: kVerde, minimumSize: const Size(0, 52)),
                      onPressed: () async {
                        if (await dialogoPago(context, e)) await onCambio();
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('PAGADO', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kAzul, minimumSize: const Size(0, 52)),
                  onPressed: () => compartirExpensaUnidad(context, e),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            ),
          ]),
        ]),
      ),
    );
  }
}

Future<bool> dialogoPagoSaldo(BuildContext context, Map<String, dynamic> unidad, double maximo) async {
  final c = TextEditingController(text: maximo.toStringAsFixed(2));
  String medio = 'Efectivo';
  DateTime fecha = DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setD) => AlertDialog(
        title: const Text('Registrar pago'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Saldo anterior sin detalle: ${fmtPlata(maximo)}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: deco('Monto que paga (\$)'),
            ),
            const SizedBox(height: 12),
            const Text('Forma de pago', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 6),
            SelectorEstado(
                opciones: const ['Efectivo', 'Transferencia', 'Cheque', 'Otro'],
                valor: medio,
                onChanged: (v) => setD(() => medio = v)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              icon: const Icon(Icons.event),
              label: Text('Fecha de pago: ${fmtFecha(fecha.toIso8601String())}'),
              onPressed: () async {
                final f = await elegirFecha(d, fecha);
                if (f != null) setD(() => fecha = f);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kVerde),
            onPressed: () {
              final m = parseNumero(c.text);
              if (m == null || m <= 0 || m > maximo + 0.005) {
                aviso(d, 'Monto inválido. Máximo: ${fmtPlata(maximo)}');
                return;
              }
              Navigator.pop(d, true);
            },
            child: const Text('REGISTRAR PAGO'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  await Expensas.pagarSaldo(unidad, parseNumero(c.text)!, medio, fecha);
  return true;
}
