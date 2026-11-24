import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../db.dart';
import '../importar_propietarios.dart';
import '../widgets.dart';

class _Fila {
  bool sel;
  final TextEditingController piso, num, prop, tel, coef;
  _Fila(FilaListado f)
      : sel = f.sel,
        piso = TextEditingController(text: f.piso),
        num = TextEditingController(text: f.numero),
        prop = TextEditingController(text: f.propietario),
        tel = TextEditingController(text: f.telefono),
        coef = TextEditingController(text: f.coef);
}

String _norm(String s) => s.trim().toLowerCase().replaceFirst(RegExp(r'^0+(?=\d)'), '');

/// Foto del listado de propietarios -> unidades cargadas automáticamente.
class ImportarPropietariosScreen extends StatefulWidget {
  final int? consorcioId;
  const ImportarPropietariosScreen({super.key, this.consorcioId});

  @override
  State<ImportarPropietariosScreen> createState() => _ImportarPropietariosScreenState();
}

class _ImportarPropietariosScreenState extends State<ImportarPropietariosScreen> {
  int? _cid;
  final _filas = <_Fila>[];
  bool _leyendo = false;
  String? _foto;

  @override
  void initState() {
    super.initState();
    _cid = widget.consorcioId;
  }

  Future<void> _leer(ImageSource fuente) async {
    try {
      final x = await ImagePicker().pickImage(source: fuente, imageQuality: 90, maxWidth: 2600);
      if (x == null) return;
      setState(() => _leyendo = true);
      final ruta = await guardarArchivo(x.path, 'listados');
      final rec = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final res = await rec.processImage(InputImage.fromFilePath(ruta));
        final encontradas = parsearListado(res);
        setState(() {
          _foto = ruta;
          _filas.addAll(encontradas.map(_Fila.new));
        });
        if (mounted) {
          aviso(context,
              encontradas.isEmpty
                  ? 'No se pudo leer ninguna fila. Probá con más luz y la hoja derecha, o agregá filas a mano.'
                  : 'Se leyeron ${encontradas.length} filas. Revisalas antes de importar.');
        }
      } finally {
        await rec.close();
      }
    } catch (e) {
      if (mounted) aviso(context, 'No se pudo leer la foto: $e');
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  Future<void> _importar() async {
    if (_cid == null) {
      aviso(context, 'Elegí el consorcio');
      return;
    }
    final elegidas = _filas.where((f) => f.sel && f.num.text.trim().isNotEmpty).toList();
    if (elegidas.isEmpty) {
      aviso(context, 'No hay filas con unidad para importar');
      return;
    }
    final existentes = await Db.all('unidades', where: 'consorcio_id = ?', args: [_cid]);
    var nuevas = 0, actualizadas = 0;
    for (final f in elegidas) {
      final piso = f.piso.text.trim().isEmpty ? '-' : f.piso.text.trim();
      final num = f.num.text.trim();
      final clave = '${_norm(piso)}|${_norm(num)}';
      final prev = existentes.where((u) => '${_norm('${u['piso']}')}|${_norm('${u['numero']}')}' == clave).toList();
      final coef = parseNumero(f.coef.text);
      if (prev.isNotEmpty) {
        final u = prev.first;
        await Db.save('unidades', {
          'id': u['id'],
          if (f.prop.text.trim().isNotEmpty) 'propietario': f.prop.text.trim(),
          if (f.tel.text.trim().isNotEmpty) 'telefono': f.tel.text.trim(),
          if (coef != null) 'coeficiente': coef,
        });
        actualizadas++;
      } else {
        final id = await Db.save('unidades', {
          'consorcio_id': _cid,
          'piso': piso,
          'numero': num,
          'propietario': f.prop.text.trim(),
          'telefono': f.tel.text.trim(),
          'coeficiente': coef ?? 0.0,
          'saldo': 0.0,
        });
        existentes.add({'id': id, 'piso': piso, 'numero': num});
        nuevas++;
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Listo'),
        content: Text('Unidades nuevas: $nuevas\nUnidades actualizadas: $actualizadas',
            style: const TextStyle(fontSize: 18)),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Widget _campo(TextEditingController c, String l, {TextInputType? tipo}) => TextField(
        controller: c,
        keyboardType: tipo,
        style: const TextStyle(fontSize: 16),
        decoration: deco(l),
      );

  @override
  Widget build(BuildContext context) {
    final n = _filas.where((f) => f.sel && f.num.text.trim().isNotEmpty).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Cargar desde foto')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        ConsorcioDropdown(valor: _cid, onChanged: (c) => setState(() => _cid = c?['id'] as int?)),
        const SizedBox(height: 8),
        const Text(
            'Sacale una foto al listado de propietarios (hoja derecha, con buena luz). Se leen unidad, nombre, teléfono y coeficiente. Podés sacar varias fotos: las filas se suman.',
            style: TextStyle(fontSize: 15)),
        const SizedBox(height: 10),
        if (_leyendo)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else ...[
          BotonGrande(
              icono: Icons.photo_camera, texto: 'SACAR FOTO DEL LISTADO', color: kNaranja, onPressed: () => _leer(ImageSource.camera)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              onPressed: () => _leer(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Elegir foto de la galería')),
        ],
        if (_foto != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(8), child: Image.file(File(_foto!), height: 120, fit: BoxFit.cover)),
          ),
        const SizedBox(height: 12),
        if (_filas.isNotEmpty)
          const Text('Revisá y corregí antes de importar:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        for (var i = 0; i < _filas.length; i++)
          Card(
            key: ObjectKey(_filas[i]),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                Row(children: [
                  Checkbox(value: _filas[i].sel, onChanged: (v) => setState(() => _filas[i].sel = v ?? false)),
                  Expanded(child: Text('Fila ${i + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                  IconButton(
                      icon: const Icon(Icons.delete_outline, color: kRojo),
                      onPressed: () => setState(() => _filas.removeAt(i))),
                ]),
                Row(children: [
                  Expanded(child: _campo(_filas[i].piso, 'Piso')),
                  const SizedBox(width: 8),
                  Expanded(child: _campo(_filas[i].num, 'Unidad')),
                  const SizedBox(width: 8),
                  Expanded(child: _campo(_filas[i].coef, 'Coef. %', tipo: const TextInputType.numberWithOptions(decimal: true))),
                ]),
                const SizedBox(height: 8),
                _campo(_filas[i].prop, 'Propietario'),
                const SizedBox(height: 8),
                _campo(_filas[i].tel, 'Teléfono', tipo: TextInputType.phone),
              ]),
            ),
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            onPressed: () => setState(() => _filas.add(_Fila(FilaListado('', '', '', '', '', true)))),
            icon: const Icon(Icons.add),
            label: const Text('Agregar fila a mano')),
        const SizedBox(height: 10),
        BotonGrande(
            icono: Icons.download_done,
            texto: 'IMPORTAR $n UNIDADES',
            color: kVerde,
            onPressed: n == 0 ? null : _importar),
        const SizedBox(height: 30),
      ]),
    );
  }
}
