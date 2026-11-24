import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'db.dart';
import 'pdf_informes.dart';
import 'widgets.dart';

double _r2(double v) => double.parse(v.toStringAsFixed(2));
double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;

// =====================================================================
// Lógica de expensas emitidas: Debe / Parcial / Pagado
// El saldo de cada unidad SIEMPRE se calcula sumando lo que resta pagar
// (total - pagado) de todas sus expensas y saldos anteriores.
// =====================================================================
double restaDe(Map<String, dynamic> e) {
  final r = _n(e['total']) - _n(e['pagado']);
  return r > 0.005 ? _r2(r) : 0.0;
}

String estadoSegun(double total, double pagado) {
  if (pagado >= total - 0.005) return 'Pagado';
  if (pagado > 0.005) return 'Parcial';
  return 'Debe';
}

bool esSaldoAnterior(Map<String, dynamic> e) => (e['tipo'] ?? 'Expensa') == 'Saldo anterior';

class Expensas {
  /// Solo las expensas del mes (no los saldos anteriores cargados a mano).
  static Future<List<Map<String, dynamic>>> delPeriodo(int consorcioId, String periodo) => Db.all('expensas',
      where: "consorcio_id = ? AND periodo = ? AND COALESCE(tipo,'Expensa') = 'Expensa'",
      args: [consorcioId, periodo],
      orderBy: 'id ASC');

  static Future<List<Map<String, dynamic>>> deUnidad(int unidadId) =>
      Db.all('expensas', where: 'unidad_id = ?', args: [unidadId], orderBy: 'periodo DESC, id DESC');

  static Future<List<Map<String, dynamic>>> gastosDelPeriodo(int consorcioId, String periodo) async {
    final todos = await Db.all('gastos', where: 'consorcio_id = ?', args: [consorcioId], orderBy: 'fecha ASC');
    return todos.where((g) {
      final d = DateTime.tryParse((g['fecha'] ?? '').toString());
      if (d == null) return false;
      final mes = d.month.toString().padLeft(2, '0');
      return '${d.year}-$mes' == periodo;
    }).toList();
  }

  /// Recalcula el saldo pendiente de la unidad a partir de sus expensas.
  static Future<double> recalcularSaldo(dynamic unidadId) async {
    if (unidadId == null) return 0;
    final filas = await Db.all('expensas', where: 'unidad_id = ?', args: [unidadId]);
    final saldo = _r2(filas.fold<double>(0, (a, e) => a + restaDe(e)));
    final u = await Db.one('unidades', unidadId as int);
    if (u != null) {
      u['saldo'] = saldo;
      await Db.save('unidades', u);
    }
    return saldo;
  }

  /// Resta de períodos anteriores (y saldos anteriores) respecto de una expensa.
  static List<Map<String, dynamic>> anterioresDe(Map<String, dynamic> e, List<Map<String, dynamic>> todas) {
    final per = (e['periodo'] ?? '').toString();
    return todas.where((o) {
      if (o['id'] == e['id'] || restaDe(o) <= 0) return false;
      return esSaldoAnterior(o) || (o['periodo'] ?? '').toString().compareTo(per) < 0;
    }).toList();
  }

  /// Crea una expensa "Debe" por cada unidad según su porcentaje (coeficiente).
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
        'tipo': 'Expensa',
        'pagado': 0.0,
      });
      await recalcularSaldo(u['id']);
    }
    await Db.save('liquidaciones', {
      'consorcio_id': consorcioId,
      'periodo': periodo,
      'total': _r2(total),
      'detalle': '{"v":3}',
      'aplicada': ahora,
    });
  }

  /// Carga una deuda anterior (sin liquidación por mes) para poder cobrarla en partes.
  static Future<void> agregarSaldoAnterior(Map<String, dynamic> unidad, double monto, String concepto) async {
    final cons = await Db.one('consorcios', unidad['consorcio_id'] as int);
    final ahora = DateTime.now();
    await Db.save('expensas', {
      'consorcio_id': unidad['consorcio_id'],
      'consorcio_nombre': cons?['nombre'] ?? '',
      'unidad_id': unidad['id'],
      'unidad_txt': 'Piso ${unidad['piso']} - ${unidad['numero']}',
      'propietario': unidad['propietario'] ?? '',
      'periodo': '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}',
      'coeficiente': unidad['coeficiente'],
      'ordinarias': 0.0,
      'extraordinarias': 0.0,
      'total': _r2(monto),
      'estado': 'Debe',
      'fecha_emision': ahora.toIso8601String(),
      'tipo': 'Saldo anterior',
      'concepto': concepto.isEmpty ? 'Saldo anterior' : concepto,
      'pagado': 0.0,
    });
    await recalcularSaldo(unidad['id']);
  }

  static Future<List<Map<String, dynamic>>> pagosDeUnidad(int unidadId) =>
      Db.all('pagos', where: 'unidad_id = ?', args: [unidadId], orderBy: 'id DESC');

  /// Asienta un pago total o parcial sobre una expensa.
  static Future<void> registrarPago(Map<String, dynamic> e, double monto, String medio, DateTime fecha) async {
    final resta = restaDe(e);
    final m = _r2(monto > resta ? resta : monto);
    if (m <= 0) return;
    final pagado = _r2(_n(e['pagado']) + m);
    final total = _n(e['total']);
    await Db.save('pagos', {
      'unidad_id': e['unidad_id'],
      'consorcio_id': e['consorcio_id'],
      'fecha': fecha.toIso8601String(),
      'monto': m,
      'medio': medio,
      'concepto': esSaldoAnterior(e)
          ? (e['concepto'] ?? 'Saldo anterior').toString()
          : 'Expensa ${periodoTexto(e['periodo']?.toString())}',
      'expensa_id': e['id'],
    });
    await Db.save('expensas', {
      'id': e['id'],
      'pagado': pagado,
      'estado': estadoSegun(total, pagado),
      'medio_pago': medio,
      'fecha_pago': fecha.toIso8601String(),
    });
    await recalcularSaldo(e['unidad_id']);
  }

  static Future<void> _recalcularExpensa(int expensaId) async {
    final e = await Db.one('expensas', expensaId);
    if (e == null) return;
    final pagos = await Db.all('pagos', where: 'expensa_id = ?', args: [expensaId]);
    final pagado = _r2(pagos.fold<double>(0, (a, p) => a + _n(p['monto'])));
    await Db.save('expensas', {
      'id': expensaId,
      'pagado': pagado,
      'estado': estadoSegun(_n(e['total']), pagado),
      if (pagado <= 0.005) 'medio_pago': null,
      if (pagado <= 0.005) 'fecha_pago': null,
    });
  }

  static Future<void> anularPago(Map<String, dynamic> pago) async {
    await Db.delete('pagos', pago['id'] as int);
    final eid = pago['expensa_id'];
    if (eid != null) await _recalcularExpensa(eid as int);
    await recalcularSaldo(pago['unidad_id']);
  }

  /// Quita TODOS los pagos de una expensa y la deja otra vez en DEBE.
  static Future<void> deshacerPagos(Map<String, dynamic> e) async {
    await Db.deleteWhere('pagos', 'expensa_id = ?', [e['id']]);
    await Db.save('expensas', {
      'id': e['id'],
      'pagado': 0.0,
      'estado': 'Debe',
      'medio_pago': null,
      'fecha_pago': null,
    });
    await recalcularSaldo(e['unidad_id']);
  }

  /// Anula la emisión: quita las expensas del mes y sus pagos.
  static Future<void> revertirEmision(int consorcioId, String periodo) async {
    final filas = await delPeriodo(consorcioId, periodo);
    for (final e in filas) {
      await Db.deleteWhere('pagos', 'expensa_id = ?', [e['id']]);
      await Db.delete('expensas', e['id'] as int);
      await recalcularSaldo(e['unidad_id']);
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
    final otras = e['unidad_id'] == null ? <Map<String, dynamic>>[] : await Expensas.deUnidad(e['unidad_id'] as int);
    return pdfExpensaUnidad(e, cons, unidad, gastos, otras);
  },
      'Expensa ${periodoTexto(e['periodo']?.toString())} - ${e['consorcio_nombre']} - ${e['unidad_txt']}: '
      '${fmtPlata(_n(e['total']))} - resta ${fmtPlata(restaDe(e))} (${e['estado'] == 'Pagado' ? 'PAGADO' : 'DEBE'})');
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
    final parcial = estado == 'Parcial';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
          color: pagado ? kVerde : (parcial ? kAmbar : kRojo), borderRadius: BorderRadius.circular(20)),
      child: Text(pagado ? 'PAGADO' : (parcial ? 'PAGO PARCIAL' : 'DEBE'),
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

/// Diálogo de pago: el monto se puede bajar para registrar un PAGO PARCIAL.
Future<bool> dialogoPago(BuildContext context, Map<String, dynamic> e) async {
  final resta = restaDe(e);
  final c = TextEditingController(text: resta.toStringAsFixed(2));
  String medio = 'Efectivo';
  DateTime fecha = DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setD) {
        final m = parseNumero(c.text) ?? 0;
        final parcial = m > 0 && m < resta - 0.005;
        return AlertDialog(
          title: const Text('Asentar pago'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${e['unidad_txt']}${(e['propietario'] ?? '').toString().isEmpty ? '' : ' · ${e['propietario']}'}\n'
                  '${esSaldoAnterior(e) ? (e['concepto'] ?? 'Saldo anterior') : 'Expensa ${periodoTexto(e['periodo']?.toString())}'}\n'
                  'Importe: ${fmtPlata(_n(e['total']))}\n'
                  'Ya pagado: ${fmtPlata(_n(e['pagado']))}\n'
                  'Resta pagar: ${fmtPlata(resta)}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                decoration: deco('Monto que paga (\$)'),
                onChanged: (_) => setD(() {}),
              ),
              const SizedBox(height: 6),
              Text(
                  parcial
                      ? 'PAGO PARCIAL: quedan ${fmtPlata(resta - m)} pendientes y se suman al saldo.'
                      : 'Pago total: la expensa queda PAGADA.',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: parcial ? kAmbar : kVerde)),
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
                final v = parseNumero(c.text);
                if (v == null || v <= 0 || v > resta + 0.005) {
                  aviso(d, 'Monto inválido. Máximo: ${fmtPlata(resta)}');
                  return;
                }
                Navigator.pop(d, true);
              },
              child: Text(parcial ? 'PAGO PARCIAL' : 'REGISTRAR PAGO'),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true) return false;
  await Expensas.registrarPago(e, parseNumero(c.text)!, medio, fecha);
  return true;
}

/// Diálogo para cargar una deuda anterior a una unidad.
Future<bool> dialogoSaldoAnterior(BuildContext context, Map<String, dynamic> unidad) async {
  final monto = TextEditingController();
  final concepto = TextEditingController(text: 'Saldo anterior');
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Cargar saldo anterior'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Deuda de expensas anterior a esta app. Después se cobra en partes con PAGAR.',
              style: TextStyle(fontSize: 15)),
          const SizedBox(height: 12),
          TextField(
            controller: monto,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: deco('Importe adeudado (\$)'),
          ),
          const SizedBox(height: 10),
          TextField(controller: concepto, decoration: deco('Detalle (ej: expensas de marzo a mayo)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final v = parseNumero(monto.text);
            if (v == null || v <= 0) {
              aviso(d, 'Ingresá un importe mayor a 0');
              return;
            }
            Navigator.pop(d, true);
          },
          child: const Text('CARGAR'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await Expensas.agregarSaldoAnterior(unidad, parseNumero(monto.text)!, concepto.text.trim());
  return true;
}

/// Tarjeta de una expensa: estado DEBE / PAGO PARCIAL / PAGADO, botón PAGAR y PDF para WhatsApp.
class TarjetaExpensa extends StatelessWidget {
  final Map<String, dynamic> e;
  final bool mostrarUnidad;
  final Future<void> Function() onCambio;
  const TarjetaExpensa({super.key, required this.e, required this.mostrarUnidad, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    final estado = (e['estado'] ?? 'Debe').toString();
    final pagado = estado == 'Pagado';
    final parcial = estado == 'Parcial';
    final color = pagado ? kVerde : (parcial ? kAmbar : kRojo);
    final anterior = esSaldoAnterior(e);
    final base = anterior ? (e['concepto'] ?? 'Saldo anterior').toString() : periodoTexto(e['periodo']?.toString());
    final titulo = mostrarUnidad
        ? '${e['unidad_txt']}${(e['propietario'] ?? '').toString().isEmpty ? '' : ' · ${e['propietario']}'}'
        : base;
    final yaPagado = _n(e['pagado']);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color, width: 2.5)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            EstadoPago(estado),
          ]),
          const SizedBox(height: 4),
          Text(fmtPlata(_n(e['total'])), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          if (!anterior)
            Text('Ord. ${fmtPlata(_n(e['ordinarias']))} · Extra ${fmtPlata(_n(e['extraordinarias']))}',
                style: const TextStyle(fontSize: 14)),
          if (anterior && !mostrarUnidad) const Text('Deuda anterior', style: TextStyle(fontSize: 14)),
          if (yaPagado > 0.005)
            Text('Pagado: ${fmtPlata(yaPagado)}',
                style: const TextStyle(fontSize: 16, color: kVerde, fontWeight: FontWeight.w800)),
          if (!pagado)
            Text('Resta pagar: ${fmtPlata(restaDe(e))}',
                style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.w900)),
          if (pagado)
            Text('Pagado el ${fmtFecha(e['fecha_pago']?.toString())}${e['medio_pago'] == null ? '' : ' · ${e['medio_pago']}'}',
                style: const TextStyle(fontSize: 15, color: kVerde, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(children: [
            if (!pagado)
              Expanded(
                child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kVerde, minimumSize: const Size(0, 52)),
                    onPressed: () async {
                      if (await dialogoPago(context, e)) await onCambio();
                    },
                    icon: const Icon(Icons.payments),
                    label: const Text('PAGAR', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              ),
            if (!pagado) const SizedBox(width: 8),
            if (!anterior)
              Expanded(
                child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kAzul, minimumSize: const Size(0, 52)),
                    onPressed: () => compartirExpensaUnidad(context, e),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('PDF', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              ),
          ]),
          if (yaPagado > 0.005)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
                  onPressed: () async {
                    if (!await confirmar(context, 'Se anulan los pagos de esta expensa y vuelve a DEBE por el total.',
                        boton: 'Deshacer pagos')) {
                      return;
                    }
                    await Expensas.deshacerPagos(e);
                    await onCambio();
                  },
                  icon: const Icon(Icons.undo),
                  label: const Text('Deshacer pagos')),
            ),
        ]),
      ),
    );
  }
}
