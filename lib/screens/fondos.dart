import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db.dart';
import '../fondos.dart';
import '../widgets.dart';

/// Movimiento de fondos del consorcio: cuadro Entrada/Debe, Salida/Haber y Saldo.
class FondosScreen extends StatefulWidget {
  const FondosScreen({super.key});

  @override
  State<FondosScreen> createState() => _FondosScreenState();
}

class _FondosScreenState extends State<FondosScreen> {
  int? _cid;
  String _cnombre = '';
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  bool _reservaApartada = true;
  MovimientoFondos? _m;
  bool _cargando = false;

  String get _periodo => '${_mes.year}-${_mes.month.toString().padLeft(2, '0')}';

  Future<void> _cargar() async {
    if (_cid == null) return;
    setState(() => _cargando = true);
    final m = await Fondos.calcular(_cid!, _periodo, reservaApartada: _reservaApartada);
    if (mounted) {
      setState(() {
        _m = m;
        _cargando = false;
      });
    }
  }

  void _cambiarMes(int d) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + d));
    _cargar();
  }

  Future<void> _pdf() async {
    if (_m == null) return;
    try {
      final cons = await Db.one('consorcios', _cid!);
      final f = await pdfMovimientoFondos(cons, _cnombre, _m!);
      await Share.shareXFiles([XFile(f.path, mimeType: 'application/pdf')],
          text: 'Movimiento de fondos - $_cnombre - ${periodoTexto(_periodo)}');
    } catch (e) {
      if (mounted) aviso(context, 'No se pudo generar el PDF: $e');
    }
  }

  Widget _celda(String t, {bool der = false, bool bold = false, Color? color, double size = 15}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        child: Text(t,
            textAlign: der ? TextAlign.right : TextAlign.left,
            style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Scaffold(
      appBar: AppBar(title: const Text('Movimiento de fondos')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        ConsorcioDropdown(
          valor: _cid,
          onChanged: (c) {
            _cid = c?['id'] as int?;
            _cnombre = c?['nombre']?.toString() ?? '';
            _cargar();
          },
        ),
        const SizedBox(height: 8),
        Row(children: [
          IconButton(iconSize: 34, onPressed: () => _cambiarMes(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
              child: Text(periodoTexto(_periodo),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
          IconButton(iconSize: 34, onPressed: () => _cambiarMes(1), icon: const Icon(Icons.chevron_right)),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Fondo de reserva: apartar el 10 % (Salida)', style: TextStyle(fontSize: 16)),
          subtitle: const Text('Apagado: se suma como Entrada.'),
          value: _reservaApartada,
          onChanged: (v) {
            setState(() => _reservaApartada = v);
            _cargar();
          },
        ),
        if (_cid == null)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Elegí un consorcio para ver el movimiento de fondos.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 17)))
        else if (_cargando || m == null)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else ...[
          Card(
            color: m.resultado >= 0 ? const Color(0xFFE8F5E9) : const Color(0xFFFDECEA),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: m.resultado >= 0 ? kVerde : kRojo, width: 2.5)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Expanded(
                    child: Text('RESULTADO DEL MES', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                Text(fmtPlata(m.resultado),
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900, color: m.resultado >= 0 ? kVerde : kRojo)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kAzul)),
            clipBehavior: Clip.antiAlias,
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(3.2),
                1: FlexColumnWidth(2.1),
                2: FlexColumnWidth(2.1),
                3: FlexColumnWidth(2.2),
              },
              border: const TableBorder(horizontalInside: BorderSide(color: Colors.black12)),
              children: [
                TableRow(decoration: const BoxDecoration(color: kAzul), children: [
                  _celda('Concepto', bold: true, color: Colors.white, size: 13),
                  _celda('Entrada\nDebe', der: true, bold: true, color: Colors.white, size: 13),
                  _celda('Salida\nHaber', der: true, bold: true, color: Colors.white, size: 13),
                  _celda('Saldo', der: true, bold: true, color: Colors.white, size: 13),
                ]),
                for (final f in m.filas)
                  TableRow(children: [
                    _celda(f.concepto, bold: f.tipo != 'gasto' && f.tipo != 'ingreso', size: 14),
                    _celda(f.entrada > 0 ? fmtPlata(f.entrada) : '-', der: true, color: kVerde, size: 13),
                    _celda(f.salida > 0 ? fmtPlata(f.salida) : '-', der: true, color: kRojo, size: 13),
                    _celda(fmtPlata(f.saldo), der: true, bold: true, size: 13),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
              'Saldo inicial = resultado del mes anterior. Expensas comunes = cobradas en el mes. Deudas y convenios = expensas atrasadas pagadas por los propietarios.',
              style: TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          BotonGrande(icono: Icons.picture_as_pdf, texto: 'COMPARTIR PDF', color: kVerde, onPressed: _pdf),
          const SizedBox(height: 30),
        ],
      ]),
    );
  }
}
