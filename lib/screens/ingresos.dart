import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';
import 'informe_financiero.dart';

// =====================================================================
// INGRESOS del consorcio (alquileres, intereses, multas, aportes, etc.)
// Los cobros de expensas se toman solos de los pagos asentados.
// =====================================================================
const kTiposIngreso = ['Alquiler / cochera', 'Intereses', 'Aporte / fondo', 'Otro'];

class IngresosScreen extends StatelessWidget {
  const IngresosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListaModulo(
      titulo: 'Ingresos',
      vacio: 'No hay ingresos cargados.\nLos cobros de expensas se suman solos en el informe.\nTocá NUEVO para otros ingresos.',
      cargar: () => Db.all('ingresos'),
      buscable: (e) => '${e['consorcio_nombre']} ${e['concepto']} ${e['tipo']}',
      acciones: [
        IconButton(
          tooltip: 'Informe PDF de gastos e ingresos',
          icon: const Icon(Icons.picture_as_pdf),
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const InformeFinancieroScreen())),
        ),
      ],
      onNuevo: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const IngresoForm()));
      },
      item: (c, e, recargar) => Card(
        child: ListTile(
          minVerticalPadding: 12,
          leading: const Icon(Icons.savings, size: 38, color: kVerde),
          title: Text(fmtPlata(e['monto'] as num?),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: kVerde)),
          subtitle: Text(
              '${e['concepto'] ?? ''}\n${e['consorcio_nombre'] ?? ''} · ${fmtFecha(e['fecha']?.toString())}\n${e['tipo'] ?? ''}'),
          isThreeLine: true,
          onTap: () async {
            await Navigator.push(c, MaterialPageRoute(builder: (_) => IngresoForm(existente: e)));
            await recargar();
          },
        ),
      ),
    );
  }
}

class IngresoForm extends StatefulWidget {
  final Map<String, dynamic>? existente;
  const IngresoForm({super.key, this.existente});

  @override
  State<IngresoForm> createState() => _IngresoFormState();
}

class _IngresoFormState extends State<IngresoForm> {
  final _k = GlobalKey<FormState>();
  int? _consorcioId;
  String _consorcioNombre = '';
  final _concepto = TextEditingController();
  final _monto = TextEditingController();
  final _notas = TextEditingController();
  DateTime _fecha = DateTime.now();
  String _tipo = kTiposIngreso.first;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _consorcioId = e['consorcio_id'] as int?;
      _consorcioNombre = (e['consorcio_nombre'] ?? '').toString();
      _concepto.text = (e['concepto'] ?? '').toString();
      _monto.text = e['monto']?.toString() ?? '';
      _notas.text = (e['notas'] ?? '').toString();
      _fecha = DateTime.tryParse((e['fecha'] ?? '').toString()) ?? DateTime.now();
      _tipo = (e['tipo'] ?? kTiposIngreso.first).toString();
    }
  }

  Future<void> _guardar() async {
    if (!_k.currentState!.validate()) return;
    if (_consorcioId == null) {
      aviso(context, 'Elegí el consorcio');
      return;
    }
    await Db.save('ingresos', {
      'id': widget.existente?['id'],
      'consorcio_id': _consorcioId,
      'consorcio_nombre': _consorcioNombre,
      'fecha': _fecha.toIso8601String(),
      'concepto': _concepto.text.trim(),
      'tipo': _tipo,
      'monto': parseNumero(_monto.text) ?? 0.0,
      'notas': _notas.text.trim(),
    });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _eliminar() async {
    if (!await confirmar(context, 'Se elimina SOLO este ingreso.')) return;
    await Db.delete('ingresos', widget.existente!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existente == null ? 'Nuevo ingreso' : 'Ingreso'),
        actions: [
          if (widget.existente != null) IconButton(icon: const Icon(Icons.delete), onPressed: _eliminar),
        ],
      ),
      body: Form(
        key: _k,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          ConsorcioDropdown(
            valor: _consorcioId,
            onChanged: (c) => setState(() {
              _consorcioId = c?['id'] as int?;
              _consorcioNombre = c?['nombre']?.toString() ?? _consorcioNombre;
            }),
          ),
          campo(_concepto, 'Concepto (ej: Alquiler cochera 3)', obligatorio: true, icono: Icons.description),
          TextFormField(
            controller: _monto,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: deco('Monto (\$) *', icono: Icons.attach_money),
            validator: (v) => parseNumero(v ?? '') == null ? 'Ingresá un monto' : null,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
            icon: const Icon(Icons.event),
            label: Text('Fecha: ${fmtFecha(_fecha.toIso8601String())}', style: const TextStyle(fontSize: 17)),
            onPressed: () async {
              final f = await elegirFecha(context, _fecha);
              if (f != null) setState(() => _fecha = f);
            },
          ),
          const SizedBox(height: 14),
          const Text('Tipo de ingreso', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectorEstado(opciones: kTiposIngreso, valor: _tipo, onChanged: (v) => setState(() => _tipo = v)),
          const SizedBox(height: 12),
          campo(_notas, 'Notas', lineas: 2),
          BotonGrande(icono: Icons.save, texto: 'GUARDAR INGRESO', onPressed: _guardar),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}
