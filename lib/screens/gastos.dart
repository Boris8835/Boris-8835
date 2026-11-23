import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../db.dart';
import '../widgets.dart';

// =====================================================================
// MÓDULO 4: Carga rápida de gastos (con OCR offline de la factura)
// =====================================================================
const kTiposGasto = ['Expensa ordinaria', 'Expensa extraordinaria'];
const kFormasPago = ['Contado', 'Cuotas', 'Pago parcial'];

class GastosScreen extends StatelessWidget {
  const GastosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListaModulo(
      titulo: 'Gastos',
      vacio: 'No hay gastos cargados.\nTocá NUEVO y sacale una foto a la factura.',
      cargar: () => Db.all('gastos'),
      buscable: (e) => '${e['consorcio_nombre']} ${e['concepto']} ${e['proveedor']}',
      onNuevo: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const GastoForm()));
      },
      item: (c, e, recargar) => Card(
        child: ListTile(
          minVerticalPadding: 12,
          leading: Icon(Icons.receipt_long,
              size: 38, color: e['tipo'] == 'Expensa extraordinaria' ? kAmbar : kVerde),
          title: Text(fmtPlata(e['monto'] as num?),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          subtitle: Text(
              '${e['concepto'] ?? ''}\n${e['consorcio_nombre'] ?? ''} · ${fmtFecha(e['fecha']?.toString())}\n${e['tipo'] ?? ''} · ${e['forma_pago'] ?? ''}'),
          isThreeLine: true,
          onTap: () async {
            await Navigator.push(c, MaterialPageRoute(builder: (_) => GastoForm(existente: e)));
            await recargar();
          },
        ),
      ),
    );
  }
}

class GastoForm extends StatefulWidget {
  final Map<String, dynamic>? existente;
  const GastoForm({super.key, this.existente});

  @override
  State<GastoForm> createState() => _GastoFormState();
}

class _GastoFormState extends State<GastoForm> {
  final _k = GlobalKey<FormState>();
  int? _consorcioId;
  String _consorcioNombre = '';
  final _concepto = TextEditingController();
  final _prov = TextEditingController();
  final _cuit = TextEditingController();
  final _monto = TextEditingController();
  final _cuotas = TextEditingController(text: '3');
  final _pagado = TextEditingController();
  DateTime _fecha = DateTime.now();
  String _tipo = kTiposGasto.first;
  String _forma = kFormasPago.first;
  String? _foto;
  String _ocr = '';
  bool _leyendo = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _consorcioId = e['consorcio_id'] as int?;
      _consorcioNombre = (e['consorcio_nombre'] ?? '').toString();
      _concepto.text = (e['concepto'] ?? '').toString();
      _prov.text = (e['proveedor'] ?? '').toString();
      _cuit.text = (e['cuit'] ?? '').toString();
      _monto.text = e['monto']?.toString() ?? '';
      _cuotas.text = (e['cuotas'] ?? 3).toString();
      _pagado.text = e['pagado']?.toString() ?? '';
      _fecha = DateTime.tryParse((e['fecha'] ?? '').toString()) ?? DateTime.now();
      _tipo = (e['tipo'] ?? kTiposGasto.first).toString();
      _forma = (e['forma_pago'] ?? kFormasPago.first).toString();
      _foto = e['foto']?.toString();
      _ocr = (e['texto_ocr'] ?? '').toString();
    }
  }

  Future<void> _fotoFactura() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2000);
      if (x == null) return;
      setState(() => _leyendo = true);
      final ruta = await guardarArchivo(x.path, 'facturas');
      _foto = ruta;
      final reconocedor = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final res = await reconocedor.processImage(InputImage.fromFilePath(ruta));
        _ocr = res.text;
        _autocompletar(res.text);
      } finally {
        await reconocedor.close();
      }
      if (mounted) aviso(context, 'Factura leída. Revisá los datos antes de guardar.');
    } catch (e) {
      if (mounted) aviso(context, 'No se pudo leer la factura. Cargá los datos a mano.');
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  void _autocompletar(String texto) {
    // Importe: toma el mayor monto con formato 1.234,56 (suele ser el TOTAL).
    final reMonto = RegExp(r'\d{1,3}(?:\.\d{3})*,\d{2}');
    double? mejor;
    for (final m in reMonto.allMatches(texto)) {
      final v = parseNumero(m.group(0)!);
      if (v != null && (mejor == null || v > mejor)) mejor = v;
    }
    if (mejor != null) _monto.text = mejor.toStringAsFixed(2);

    final reCuit = RegExp(r'\b(\d{2})-?(\d{8})-?(\d)\b');
    final mc = reCuit.firstMatch(texto);
    if (mc != null) _cuit.text = '${mc.group(1)}-${mc.group(2)}-${mc.group(3)}';

    final reFecha = RegExp(r'\b(\d{2})[/\-.](\d{2})[/\-.](\d{4})\b');
    final mf = reFecha.firstMatch(texto);
    if (mf != null) {
      final d = int.tryParse(mf.group(1)!);
      final mo = int.tryParse(mf.group(2)!);
      final a = int.tryParse(mf.group(3)!);
      if (d != null && mo != null && a != null && mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        _fecha = DateTime(a, mo, d);
      }
    }
    if (_prov.text.isEmpty) {
      final primera = texto.split('\n').map((l) => l.trim()).firstWhere((l) => l.length > 3, orElse: () => '');
      _prov.text = primera;
    }
  }

  Future<void> _guardar() async {
    if (!_k.currentState!.validate()) return;
    if (_consorcioNombre.isEmpty) {
      aviso(context, 'Elegí el consorcio.');
      return;
    }
    final monto = parseNumero(_monto.text);
    if (monto == null) {
      aviso(context, 'Ingresá un monto válido.');
      return;
    }
    await Db.save('gastos', {
      'id': widget.existente?['id'],
      'consorcio_id': _consorcioId,
      'consorcio_nombre': _consorcioNombre,
      'fecha': _fecha.toIso8601String(),
      'concepto': _concepto.text.trim(),
      'proveedor': _prov.text.trim(),
      'cuit': _cuit.text.trim(),
      'monto': monto,
      'tipo': _tipo,
      'forma_pago': _forma,
      'cuotas': _forma == 'Cuotas' ? (int.tryParse(_cuotas.text) ?? 1) : null,
      'pagado': _forma == 'Pago parcial' ? parseNumero(_pagado.text) : null,
      'foto': _foto,
      'texto_ocr': _ocr,
    });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _eliminar() async {
    if (!await confirmar(context, 'Se elimina SOLO este gasto.')) return;
    await Db.delete('gastos', widget.existente!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final monto = parseNumero(_monto.text) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existente == null ? 'Nuevo gasto' : 'Gasto'),
        actions: [
          if (widget.existente != null) IconButton(icon: const Icon(Icons.delete), onPressed: _eliminar),
        ],
      ),
      body: Form(
        key: _k,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          BotonGrande(
              icono: Icons.document_scanner,
              texto: _leyendo ? 'LEYENDO FACTURA...' : 'FOTO DE FACTURA (OCR)',
              color: kNaranja.withAlpha(255),
              onPressed: _leyendo ? null : _fotoFactura),
          if (_foto != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(_foto!), height: 140, fit: BoxFit.cover)),
            ),
          const SizedBox(height: 14),
          ConsorcioDropdown(
            valor: _consorcioId,
            onChanged: (c) => setState(() {
              _consorcioId = c?['id'] as int?;
              _consorcioNombre = c?['nombre']?.toString() ?? _consorcioNombre;
            }),
          ),
          campo(_concepto, 'Concepto (ej: Reparación bomba)', obligatorio: true, icono: Icons.description),
          campo(_prov, 'Proveedor', icono: Icons.store),
          campo(_cuit, 'CUIT proveedor', tipo: TextInputType.number),
          TextFormField(
            controller: _monto,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: deco('Monto total (\$) *', icono: Icons.attach_money),
            validator: (v) => parseNumero(v ?? '') == null ? 'Ingresá un monto' : null,
            onChanged: (_) => setState(() {}),
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
          const Text('Clasificación', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectorEstado(opciones: kTiposGasto, valor: _tipo, onChanged: (v) => setState(() => _tipo = v)),
          const SizedBox(height: 14),
          const Text('Forma de pago', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectorEstado(opciones: kFormasPago, valor: _forma, onChanged: (v) => setState(() => _forma = v)),
          const SizedBox(height: 12),
          if (_forma == 'Cuotas') ...[
            campo(_cuotas, 'Cantidad de cuotas', tipo: TextInputType.number),
            if ((int.tryParse(_cuotas.text) ?? 0) > 0)
              Text('Cuota estimada: ${fmtPlata(monto / (int.tryParse(_cuotas.text) ?? 1))}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
          if (_forma == 'Pago parcial')
            campo(_pagado, 'Monto pagado hasta ahora (\$)', tipo: const TextInputType.numberWithOptions(decimal: true)),
          if (_ocr.isNotEmpty)
            ExpansionTile(
              title: const Text('Texto leído de la factura'),
              children: [Padding(padding: const EdgeInsets.all(8), child: Text(_ocr))],
            ),
          const SizedBox(height: 10),
          BotonGrande(icono: Icons.save, texto: 'GUARDAR GASTO', onPressed: _guardar),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}
