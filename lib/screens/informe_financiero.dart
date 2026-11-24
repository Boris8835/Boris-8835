import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db.dart';
import '../pdf_informes.dart';
import '../widgets.dart';

/// Elige consorcio y rango de fechas y comparte el PDF de gastos e ingresos.
class InformeFinancieroScreen extends StatefulWidget {
  final int? consorcioId;
  const InformeFinancieroScreen({super.key, this.consorcioId});

  @override
  State<InformeFinancieroScreen> createState() => _InformeFinancieroScreenState();
}

class _InformeFinancieroScreenState extends State<InformeFinancieroScreen> {
  int? _cid;
  String _cnombre = '';
  late DateTime _desde = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _hasta = DateTime.now();
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    _cid = widget.consorcioId;
  }

  bool _dentro(dynamic iso) {
    final d = DateTime.tryParse((iso ?? '').toString());
    if (d == null) return false;
    final dia = DateTime(d.year, d.month, d.day);
    return !dia.isBefore(DateTime(_desde.year, _desde.month, _desde.day)) &&
        !dia.isAfter(DateTime(_hasta.year, _hasta.month, _hasta.day));
  }

  Future<void> _generar() async {
    if (_cid == null) {
      aviso(context, 'Elegí el consorcio');
      return;
    }
    setState(() => _trabajando = true);
    try {
      final cons = await Db.one('consorcios', _cid!);
      final gastos = (await Db.all('gastos', where: 'consorcio_id = ?', args: [_cid], orderBy: 'fecha ASC'))
          .where((g) => _dentro(g['fecha']))
          .toList();
      final otros = (await Db.all('ingresos', where: 'consorcio_id = ?', args: [_cid], orderBy: 'fecha ASC'))
          .where((g) => _dentro(g['fecha']))
          .toList();
      final cobros = (await Db.all('pagos', where: 'consorcio_id = ?', args: [_cid], orderBy: 'fecha ASC'))
          .where((g) => _dentro(g['fecha']))
          .toList();
      // Agrega la unidad a cada cobro para identificarlo
      final unidades = await Db.all('unidades', where: 'consorcio_id = ?', args: [_cid]);
      final nombres = {for (final u in unidades) u['id']: 'Piso ${u['piso']} - ${u['numero']}'};
      for (final c in cobros) {
        c['concepto'] = '${nombres[c['unidad_id']] ?? 'Unidad'} · ${c['concepto'] ?? ''}';
      }
      final rango = '${fmtFecha(_desde.toIso8601String())} al ${fmtFecha(_hasta.toIso8601String())}';
      final f = await pdfGastosIngresos(
        cons: cons,
        consorcioNombre: _cnombre.isEmpty ? (cons?['nombre'] ?? '').toString() : _cnombre,
        rango: rango,
        gastos: gastos,
        cobros: cobros,
        otrosIngresos: otros,
      );
      await Share.shareXFiles([XFile(f.path, mimeType: 'application/pdf')],
          text: 'Gastos e ingresos - $_cnombre - $rango');
    } catch (e) {
      if (mounted) aviso(context, 'No se pudo generar el PDF: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informe de gastos e ingresos')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        ConsorcioDropdown(
          valor: _cid,
          onChanged: (c) => setState(() {
            _cid = c?['id'] as int?;
            _cnombre = c?['nombre']?.toString() ?? '';
          }),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
          icon: const Icon(Icons.event),
          label: Text('Desde: ${fmtFecha(_desde.toIso8601String())}', style: const TextStyle(fontSize: 17)),
          onPressed: () async {
            final f = await elegirFecha(context, _desde);
            if (f != null) setState(() => _desde = f);
          },
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
          icon: const Icon(Icons.event),
          label: Text('Hasta: ${fmtFecha(_hasta.toIso8601String())}', style: const TextStyle(fontSize: 17)),
          onPressed: () async {
            final f = await elegirFecha(context, _hasta);
            if (f != null) setState(() => _hasta = f);
          },
        ),
        const SizedBox(height: 10),
        const Text(
            'El informe incluye los gastos cargados, los cobros de expensas asentados (pagos totales y parciales) y los otros ingresos, con el balance.',
            style: TextStyle(fontSize: 15)),
        const SizedBox(height: 16),
        _trabajando
            ? const Center(child: CircularProgressIndicator())
            : BotonGrande(
                icono: Icons.picture_as_pdf, texto: 'GENERAR Y COMPARTIR PDF', color: kVerde, onPressed: _generar),
      ]),
    );
  }
}
