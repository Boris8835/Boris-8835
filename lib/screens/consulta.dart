import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';

// =====================================================================
// MÓDULO 6: Consulta rápida en terreno (solo lectura, offline)
// =====================================================================
class ConsultaScreen extends StatelessWidget {
  const ConsultaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Consulta rápida'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: kNaranja,
            labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            tabs: [Tab(text: 'SALDOS'), Tab(text: 'VENCIMIENTOS')],
          ),
        ),
        body: const TabBarView(children: [_Saldos(), _Vencimientos()]),
      ),
    );
  }
}

class _Saldos extends StatefulWidget {
  const _Saldos();

  @override
  State<_Saldos> createState() => _SaldosState();
}

class _SaldosState extends State<_Saldos> {
  int? _consorcio;
  List<Map<String, dynamic>> _u = [];
  bool _soloDeudores = false;

  Future<void> _cargar() async {
    if (_consorcio == null) return;
    final l = await Db.all('unidades',
        where: 'consorcio_id = ?', args: [_consorcio], orderBy: 'piso, numero');
    if (mounted) setState(() => _u = l);
  }

  @override
  Widget build(BuildContext context) {
    final lista = _soloDeudores ? _u.where((e) => ((e['saldo'] as num?) ?? 0) > 0).toList() : _u;
    final total = _u.fold<double>(0, (a, e) => a + ((e['saldo'] as num?)?.toDouble() ?? 0));
    return ListView(padding: const EdgeInsets.all(12), children: [
      ConsorcioDropdown(
        valor: _consorcio,
        onChanged: (c) {
          _consorcio = c?['id'] as int?;
          _cargar();
        },
      ),
      if (_consorcio != null) ...[
        Card(
          color: kAzul,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Text('Total adeudado', style: TextStyle(color: Colors.white, fontSize: 16)),
              Text(fmtPlata(total),
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
        SwitchListTile(
          title: const Text('Mostrar solo unidades con deuda', style: TextStyle(fontSize: 17)),
          value: _soloDeudores,
          onChanged: (v) => setState(() => _soloDeudores = v),
        ),
        if (lista.isEmpty)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Sin unidades para mostrar.\nLos saldos se calculan solos con las expensas y pagos de cada unidad.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 17))),
        for (final u in lista)
          Card(
            child: ListTile(
              minVerticalPadding: 10,
              title: Text('Piso ${u['piso']} · Unidad ${u['numero']}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              subtitle: Text((u['propietario'] ?? '').toString()),
              trailing: Text(fmtPlata(u['saldo'] as num?),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: ((u['saldo'] as num?) ?? 0) > 0 ? kRojo : kVerde)),
            ),
          ),
      ],
    ]);
  }
}

class _Vencimientos extends StatefulWidget {
  const _Vencimientos();

  @override
  State<_Vencimientos> createState() => _VencimientosState();
}

class _VencimientosState extends State<_Vencimientos> {
  List<Map<String, dynamic>> _d = [];
  Map<int, String> _nombres = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final docs = await Db.all('documentos',
        where: 'vencimiento IS NOT NULL', orderBy: 'vencimiento ASC');
    final cons = await Db.all('consorcios');
    if (!mounted) return;
    setState(() {
      _d = docs;
      _nombres = {for (final c in cons) c['id'] as int: c['nombre'].toString()};
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_d.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'No hay vencimientos.\nAl guardar un archivo (seguro, matrícula, certificación contra incendio) en un consorcio, cargale la fecha de vencimiento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18))));
    }
    final hoy = DateTime.now();
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final d in _d)
        Builder(builder: (c) {
          final v = DateTime.tryParse(d['vencimiento'].toString());
          final dias = v == null ? 9999 : v.difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
          final color = dias < 0 ? kRojo : (dias <= 30 ? kAmbar : kVerde);
          final txt = dias < 0
              ? 'VENCIDO hace ${-dias} días'
              : (dias == 0 ? 'Vence HOY' : 'Vence en $dias días');
          return Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14), side: BorderSide(color: color, width: 2.5)),
            child: ListTile(
              minVerticalPadding: 12,
              leading: Icon(dias < 0 ? Icons.error : Icons.event, color: color, size: 36),
              title: Text('${d['tipo']} · ${d['nombre']}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              subtitle: Text('${_nombres[d['consorcio_id']] ?? '(consorcio eliminado)'}\n${fmtFecha(d['vencimiento'].toString())}'),
              isThreeLine: true,
              trailing: Text(txt,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          );
        }),
    ]);
  }
}
