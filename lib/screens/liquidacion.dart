import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../db.dart';
import '../expensas.dart';
import '../pdf_informes.dart';
import '../widgets.dart';

// =====================================================================
// Liquidación de expensas: suma los gastos del mes de un consorcio, los
// reparte por coeficiente, EMITE las expensas (quedan en "DEBE") y permite
// asentar cada pago ("PAGADO") y compartir el PDF por WhatsApp.
// =====================================================================
class LiquidacionScreen extends StatefulWidget {
  const LiquidacionScreen({super.key});

  @override
  State<LiquidacionScreen> createState() => _LiquidacionScreenState();
}

class _LiquidacionScreenState extends State<LiquidacionScreen> {
  int? _cid;
  String _cnombre = '';
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> _gastos = [];
  List<Map<String, dynamic>> _unidades = [];
  List<Map<String, dynamic>> _expensas = []; // emitidas
  Map<String, dynamic>? _legacy; // emitida con la versión anterior (sin detalle)
  bool _cargando = false;

  String get _periodo => DateFormat('yyyy-MM').format(_mes);
  String get _periodoTxt => periodoTexto(_periodo);
  bool get _emitida => _expensas.isNotEmpty;

  Future<void> _cargar() async {
    if (_cid == null) return;
    setState(() => _cargando = true);
    final gastos = await Expensas.gastosDelPeriodo(_cid!, _periodo);
    final u = await Db.all('unidades', where: 'consorcio_id = ?', args: [_cid], orderBy: 'piso, numero');
    final exp = await Expensas.delPeriodo(_cid!, _periodo);
    final liq = await Db.all('liquidaciones', where: 'consorcio_id = ? AND periodo = ?', args: [_cid, _periodo]);
    if (!mounted) return;
    setState(() {
      _gastos = gastos;
      _unidades = u;
      _expensas = exp;
      _legacy = (exp.isEmpty && liq.isNotEmpty) ? liq.first : null;
      _cargando = false;
    });
  }

  bool _esExtra(Map<String, dynamic> g) => g['tipo'] == 'Expensa extraordinaria';
  double _m(Map<String, dynamic> g) => (g['monto'] as num?)?.toDouble() ?? 0;
  double get _totalOrd => _emitida
      ? _expensas.fold(0.0, (a, e) => a + ((e['ordinarias'] as num?)?.toDouble() ?? 0))
      : _gastos.where((g) => !_esExtra(g)).fold(0.0, (a, g) => a + _m(g));
  double get _totalExt => _emitida
      ? _expensas.fold(0.0, (a, e) => a + ((e['extraordinarias'] as num?)?.toDouble() ?? 0))
      : _gastos.where(_esExtra).fold(0.0, (a, g) => a + _m(g));
  double get _sumaCoef => _unidades.fold(0.0, (a, u) => a + _coef(u));
  double _coef(Map<String, dynamic> u) => (u['coeficiente'] as num?)?.toDouble() ?? 0;
  double _ord(Map<String, dynamic> u) => double.parse((_totalOrd * _coef(u) / 100).toStringAsFixed(2));
  double _ext(Map<String, dynamic> u) => double.parse((_totalExt * _coef(u) / 100).toStringAsFixed(2));

  double get _cobrado => _expensas.fold(0.0, (a, e) => a + ((e['pagado'] as num?)?.toDouble() ?? 0));
  double get _pendiente => _expensas.fold(0.0, (a, e) => a + restaDe(e));

  void _cambiarMes(int d) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + d));
    _cargar();
  }

  List<Map<String, dynamic>> _filasParaPdf() {
    if (_emitida) return _expensas;
    return [
      for (final u in _unidades)
        {
          'unidad_txt': 'Piso ${u['piso']} - ${u['numero']}',
          'propietario': u['propietario'] ?? '',
          'coeficiente': _coef(u),
          'ordinarias': _ord(u),
          'extraordinarias': _ext(u),
          'total': _ord(u) + _ext(u),
        }
    ];
  }

  Future<void> _compartirPdf() async {
    try {
      final cons = await Db.one('consorcios', _cid!);
      final f = await pdfLiquidacion(cons, _cnombre, _periodo, _gastos, _filasParaPdf(), _emitida);
      await Share.shareXFiles([XFile(f.path, mimeType: 'application/pdf')],
          text: 'Liquidación de expensas - $_cnombre - $_periodoTxt');
    } catch (e) {
      if (mounted) aviso(context, 'No se pudo generar el PDF: $e');
    }
  }

  Future<void> _emitirExpensas() async {
    if (_unidades.isEmpty || _gastos.isEmpty) return;
    final ok = await confirmar(
        context,
        'Se emiten las expensas de $_periodoTxt: cada unidad queda en DEBE y el importe se suma a su saldo '
        '(${fmtPlata(_totalOrd + _totalExt)} en total).\n\nPodés revertirlo después.',
        boton: 'Emitir');
    if (!ok) return;
    await Expensas.emitir(
      consorcioId: _cid!,
      consorcioNombre: _cnombre,
      periodo: _periodo,
      unidades: _unidades,
      totalOrd: _totalOrd,
      totalExt: _totalExt,
    );
    await _cargar();
    if (mounted) aviso(context, 'Expensas emitidas. Ahora podés asentar los pagos.');
  }

  Future<void> _revertirEmision() async {
    if (!await confirmar(context,
        'Se eliminan las expensas emitidas de $_periodoTxt (también los pagos asentados de ese mes) y se descuenta lo adeudado de cada saldo.',
        boton: 'Revertir')) {
      return;
    }
    await Expensas.revertirEmision(_cid!, _periodo);
    await _cargar();
    if (mounted) aviso(context, 'Emisión revertida.');
  }

  Future<void> _revertirLegacy() async {
    final liq = _legacy;
    if (liq == null) return;
    if (!await confirmar(context, 'Se RESTA del saldo de cada unidad lo que se había sumado en $_periodoTxt.',
        boton: 'Revertir')) {
      return;
    }
    try {
      final detalle = (jsonDecode(liq['detalle'] as String) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
      for (final u in _unidades) {
        final monto = detalle[u['id'].toString()];
        if (monto == null) continue;
        final nuevo = Map<String, dynamic>.from(u);
        nuevo['saldo'] = ((u['saldo'] as num?)?.toDouble() ?? 0) - monto;
        await Db.save('unidades', nuevo);
      }
    } catch (_) {}
    await Db.delete('liquidaciones', liq['id'] as int);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final coefOk = (_sumaCoef - 100).abs() < 0.05;
    return Scaffold(
      appBar: AppBar(title: const Text('Liquidación de expensas')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        ConsorcioDropdown(
          valor: _cid,
          onChanged: (c) {
            _cid = c?['id'] as int?;
            _cnombre = c?['nombre']?.toString() ?? '';
            _cargar();
          },
        ),
        Row(children: [
          IconButton(iconSize: 40, icon: const Icon(Icons.chevron_left), onPressed: () => _cambiarMes(-1)),
          Expanded(
              child: Text(_periodoTxt,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
          IconButton(iconSize: 40, icon: const Icon(Icons.chevron_right), onPressed: () => _cambiarMes(1)),
        ]),
        if (_cid == null)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                  'Elegí un consorcio y el mes. Se suman los gastos cargados en ese mes y se reparten por coeficiente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17))),
        if (_cargando) const LinearProgressIndicator(),
        if (_cid != null && !_cargando) ...[
          Card(
            color: kAzul,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(_emitida ? 'Total emitido' : 'Total a repartir',
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
                Text(fmtPlata(_totalOrd + _totalExt),
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('Ordinarias: ${fmtPlata(_totalOrd)}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                Text('Extraordinarias: ${fmtPlata(_totalExt)}',
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
              ]),
            ),
          ),
          if (_emitida)
            Row(children: [
              Expanded(
                  child: Card(
                      color: const Color(0xFFE8F5E9),
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(children: [
                            const Text('COBRADO', style: TextStyle(fontWeight: FontWeight.w800, color: kVerde)),
                            Text(fmtPlata(_cobrado),
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kVerde)),
                          ])))),
              Expanded(
                  child: Card(
                      color: const Color(0xFFFDECEA),
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(children: [
                            const Text('DEBEN', style: TextStyle(fontWeight: FontWeight.w800, color: kRojo)),
                            Text(fmtPlata(_pendiente),
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kRojo)),
                          ])))),
            ]),
          if (_unidades.isEmpty)
            const Card(
                color: Color(0xFFFFF3CD),
                child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Este consorcio no tiene unidades. Cargalas en "Consorcios y unidades".',
                        style: TextStyle(fontSize: 16))))
          else if (!coefOk && !_emitida)
            Card(
                color: const Color(0xFFFFF3CD),
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                        'Atención: los coeficientes suman ${_sumaCoef.toStringAsFixed(2)}% (deberían sumar 100%). El reparto no va a cerrar con el total.',
                        style: const TextStyle(fontSize: 16)))),
          if (_gastos.isEmpty && !_emitida)
            const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No hay gastos cargados en este mes para este consorcio.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 17))),
          if (_gastos.isNotEmpty)
            ExpansionTile(
              title: Text('Gastos del mes (${_gastos.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              children: [
                for (final g in _gastos)
                  ListTile(
                    title: Text(g['concepto'].toString()),
                    subtitle: Text('${fmtFecha(g['fecha']?.toString())} · ${g['tipo']}'),
                    trailing: Text(fmtPlata(_m(g)), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          if (_legacy != null)
            Card(
              color: const Color(0xFFFFF3CD),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  const Text(
                      'Esta liquidación se sumó a los saldos con la versión anterior de la app (sin detalle de pagos). Revertila y volvé a emitirla para poder marcar Pagado.',
                      style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  BotonGrande(icono: Icons.undo, texto: 'REVERTIR', color: kRojo, onPressed: _revertirLegacy),
                ]),
              ),
            )
          else if (_emitida) ...[
            const SizedBox(height: 6),
            const Text('Expensas por unidad', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            for (final e in _expensas) TarjetaExpensa(key: ValueKey(e['id']), e: e, mostrarUnidad: true, onCambio: _cargar),
            const SizedBox(height: 10),
            BotonGrande(
                icono: Icons.picture_as_pdf,
                texto: 'COMPARTIR LIQUIDACIÓN (PDF)',
                color: kVerde,
                onPressed: _compartirPdf),
            const SizedBox(height: 10),
            BotonGrande(icono: Icons.undo, texto: 'REVERTIR EMISIÓN', color: kRojo, onPressed: _revertirEmision),
          ] else if (_gastos.isNotEmpty && _unidades.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('Reparto por unidad', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            for (final u in _unidades)
              Card(
                child: ListTile(
                  minVerticalPadding: 10,
                  title: Text('Piso ${u['piso']} · Unidad ${u['numero']}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  subtitle: Text(
                      '${(u['propietario'] ?? '').toString().isEmpty ? 'Sin propietario' : u['propietario']} · ${_coef(u)}%\n'
                      'Ord. ${fmtPlata(_ord(u))} · Extra ${fmtPlata(_ext(u))}'),
                  isThreeLine: true,
                  trailing: Text(fmtPlata(_ord(u) + _ext(u)),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ),
            const SizedBox(height: 10),
            BotonGrande(
                icono: Icons.picture_as_pdf,
                texto: 'VER / COMPARTIR BORRADOR (PDF)',
                color: kAzul,
                onPressed: _compartirPdf),
            const SizedBox(height: 10),
            BotonGrande(
                icono: Icons.receipt_long,
                texto: 'EMITIR EXPENSAS (quedan en DEBE)',
                color: kNaranja.withAlpha(255),
                onPressed: _emitirExpensas),
          ],
          const SizedBox(height: 30),
        ],
      ]),
    );
  }
}
