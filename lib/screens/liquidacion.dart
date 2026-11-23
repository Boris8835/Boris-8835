import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../db.dart';
import '../widgets.dart';

// =====================================================================
// Liquidación de expensas: suma los gastos del mes de un consorcio y los
// reparte entre las unidades según su coeficiente.
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
  Map<String, dynamic>? _aplicada;
  bool _cargando = false;

  String get _periodo => DateFormat('yyyy-MM').format(_mes);
  String get _periodoTxt {
    final t = DateFormat('MMMM yyyy', 'es_AR').format(_mes);
    return t[0].toUpperCase() + t.substring(1);
  }

  Future<void> _cargar() async {
    if (_cid == null) return;
    setState(() => _cargando = true);
    final todos = await Db.all('gastos', where: 'consorcio_id = ?', args: [_cid], orderBy: 'fecha ASC');
    final delMes = todos.where((g) {
      final d = DateTime.tryParse((g['fecha'] ?? '').toString());
      return d != null && d.year == _mes.year && d.month == _mes.month;
    }).toList();
    final u = await Db.all('unidades',
        where: 'consorcio_id = ?', args: [_cid], orderBy: 'piso, numero');
    final liq = await Db.all('liquidaciones',
        where: 'consorcio_id = ? AND periodo = ?', args: [_cid, _periodo]);
    if (!mounted) return;
    setState(() {
      _gastos = delMes;
      _unidades = u;
      _aplicada = liq.isEmpty ? null : liq.first;
      _cargando = false;
    });
  }

  bool _esExtra(Map<String, dynamic> g) => g['tipo'] == 'Expensa extraordinaria';
  double _m(Map<String, dynamic> g) => (g['monto'] as num?)?.toDouble() ?? 0;
  double get _totalOrd => _gastos.where((g) => !_esExtra(g)).fold(0.0, (a, g) => a + _m(g));
  double get _totalExt => _gastos.where(_esExtra).fold(0.0, (a, g) => a + _m(g));
  double get _sumaCoef => _unidades.fold(0.0, (a, u) => a + ((u['coeficiente'] as num?)?.toDouble() ?? 0));
  double _coef(Map<String, dynamic> u) => (u['coeficiente'] as num?)?.toDouble() ?? 0;
  double _ord(Map<String, dynamic> u) => double.parse((_totalOrd * _coef(u) / 100).toStringAsFixed(2));
  double _ext(Map<String, dynamic> u) => double.parse((_totalExt * _coef(u) / 100).toStringAsFixed(2));

  void _cambiarMes(int d) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + d));
    _cargar();
  }

  String _resumenTexto() {
    final b = StringBuffer();
    b.writeln('LIQUIDACIÓN DE EXPENSAS - $_cnombre');
    b.writeln('Período: $_periodoTxt');
    b.writeln('Gastos ordinarios: ${fmtPlata(_totalOrd)}');
    b.writeln('Gastos extraordinarios: ${fmtPlata(_totalExt)}');
    b.writeln('TOTAL: ${fmtPlata(_totalOrd + _totalExt)}');
    b.writeln('');
    for (final u in _unidades) {
      final tot = _ord(u) + _ext(u);
      b.writeln('Piso ${u['piso']} - ${u['numero']} (${_coef(u)}%): ${fmtPlata(tot)}'
          '${(u['propietario'] ?? '').toString().isEmpty ? '' : ' - ${u['propietario']}'}');
    }
    return b.toString();
  }

  Future<void> _aplicar() async {
    if (_unidades.isEmpty || _gastos.isEmpty) return;
    final ok = await confirmar(
        context,
        'Se va a SUMAR la expensa de $_periodoTxt al saldo pendiente de cada unidad '
        '(${fmtPlata(_totalOrd + _totalExt)} en total).\n\nPodés revertirlo después.',
        boton: 'Aplicar');
    if (!ok) return;
    final detalle = <String, double>{};
    for (final u in _unidades) {
      final monto = _ord(u) + _ext(u);
      detalle[u['id'].toString()] = monto;
      final nuevo = Map<String, dynamic>.from(u);
      nuevo['saldo'] = ((u['saldo'] as num?)?.toDouble() ?? 0) + monto;
      await Db.save('unidades', nuevo);
    }
    await Db.save('liquidaciones', {
      'consorcio_id': _cid,
      'periodo': _periodo,
      'total': _totalOrd + _totalExt,
      'detalle': jsonEncode(detalle),
      'aplicada': DateTime.now().toIso8601String(),
    });
    await _cargar();
    if (mounted) aviso(context, 'Expensas sumadas a los saldos.');
  }

  Future<void> _revertir() async {
    final liq = _aplicada;
    if (liq == null) return;
    if (!await confirmar(context, 'Se RESTA del saldo de cada unidad lo que se había sumado en $_periodoTxt.',
        boton: 'Revertir')) {
      return;
    }
    final detalle = (jsonDecode(liq['detalle'] as String) as Map).map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    for (final u in _unidades) {
      final monto = detalle[u['id'].toString()];
      if (monto == null) continue;
      final nuevo = Map<String, dynamic>.from(u);
      nuevo['saldo'] = ((u['saldo'] as num?)?.toDouble() ?? 0) - monto;
      await Db.save('unidades', nuevo);
    }
    await Db.delete('liquidaciones', liq['id'] as int);
    await _cargar();
    if (mounted) aviso(context, 'Aplicación revertida.');
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
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
          IconButton(iconSize: 40, icon: const Icon(Icons.chevron_right), onPressed: () => _cambiarMes(1)),
        ]),
        if (_cid == null)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Elegí un consorcio y el mes. Se suman los gastos cargados en ese mes y se reparten por coeficiente.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 17))),
        if (_cargando) const LinearProgressIndicator(),
        if (_cid != null && !_cargando) ...[
          Card(
            color: kAzul,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text('Total a repartir', style: TextStyle(color: Colors.white, fontSize: 16)),
                Text(fmtPlata(_totalOrd + _totalExt),
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('Ordinarias: ${fmtPlata(_totalOrd)}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                Text('Extraordinarias: ${fmtPlata(_totalExt)}', style: const TextStyle(color: Colors.white, fontSize: 16)),
              ]),
            ),
          ),
          if (_unidades.isEmpty)
            const Card(
                color: Color(0xFFFFF3CD),
                child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Este consorcio no tiene unidades. Cargalas en "Consorcios y unidades".',
                        style: TextStyle(fontSize: 16))))
          else if (!coefOk)
            Card(
                color: const Color(0xFFFFF3CD),
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                        'Atención: los coeficientes suman ${_sumaCoef.toStringAsFixed(2)}% (deberían sumar 100%). El reparto no va a cerrar con el total.',
                        style: const TextStyle(fontSize: 16)))),
          if (_gastos.isEmpty)
            const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No hay gastos cargados en este mes para este consorcio.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 17)))
          else ...[
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
                icono: Icons.share,
                texto: 'COMPARTIR LIQUIDACIÓN',
                color: kVerde,
                onPressed: () => Share.share(_resumenTexto())),
            const SizedBox(height: 10),
            if (_aplicada == null)
              BotonGrande(
                  icono: Icons.add_card,
                  texto: 'SUMAR A SALDOS DE UNIDADES',
                  color: kNaranja.withAlpha(255),
                  onPressed: _unidades.isEmpty ? null : _aplicar)
            else ...[
              Card(
                color: const Color(0xFFE8F5E9),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Ya sumada a los saldos el ${fmtFecha(_aplicada!['aplicada']?.toString(), hora: true)}.',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              BotonGrande(icono: Icons.undo, texto: 'REVERTIR APLICACIÓN', color: kRojo, onPressed: _revertir),
            ],
          ],
          const SizedBox(height: 30),
        ],
      ]),
    );
  }
}
