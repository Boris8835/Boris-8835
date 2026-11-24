import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:speech_to_text/speech_to_text.dart';
import 'db.dart';

// ---------- Colores y formatos ----------
const kAzul = Color(0xFF0B2545);
const kNaranja = Color(0xFFF59E0B);
const kRojo = Color(0xFFC62828);
const kVerde = Color(0xFF1B7F3B);
const kAmbar = Color(0xFFB45309);

String fmtFecha(String? iso, {bool hora = false}) {
  if (iso == null || iso.isEmpty) return '-';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat(hora ? 'dd/MM/yyyy HH:mm' : 'dd/MM/yyyy').format(d.toLocal());
}

String fmtPlata(num? v) {
  final f = NumberFormat.currency(locale: 'es_AR', symbol: r'$', decimalDigits: 2);
  return f.format(v ?? 0);
}

String periodoTexto(String? p) {
  final d = DateTime.tryParse('${p ?? ''}-01');
  if (d == null) return p ?? '-';
  final t = DateFormat('MMMM yyyy', 'es_AR').format(d);
  return t[0].toUpperCase() + t.substring(1);
}

double? parseNumero(String s) {
  var t = s.trim().replaceAll(r'$', '').replaceAll(' ', '');
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(t);
}

List<String> listaDeJson(dynamic raw) {
  if (raw == null || (raw is String && raw.isEmpty)) return [];
  try {
    return (jsonDecode(raw as String) as List).map((e) => e.toString()).toList();
  } catch (_) {
    return [];
  }
}

bool esVideo(String ruta) {
  final e = p.extension(ruta).toLowerCase();
  return e == '.mp4' || e == '.mov' || e == '.3gp' || e == '.mkv' || e == '.webm';
}

void aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto, style: const TextStyle(fontSize: 16))));
}

Future<bool> confirmar(BuildContext context, String mensaje, {String boton = 'Eliminar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('¿Confirmás?'),
      content: Text(mensaje, style: const TextStyle(fontSize: 17)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kRojo),
          onPressed: () => Navigator.pop(c, true),
          child: Text(boton),
        ),
      ],
    ),
  );
  return r ?? false;
}

// ---------- Botón grande ----------
class BotonGrande extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback? onPressed;
  final Color? color;
  const BotonGrande(
      {super.key, required this.icono, required this.texto, this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color ?? kAzul,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        icon: Icon(icono, size: 28),
        label: Text(texto),
      ),
    );
  }
}

InputDecoration deco(String label, {IconData? icono}) => InputDecoration(
      labelText: label,
      prefixIcon: icono == null ? null : Icon(icono),
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    );

Widget campo(TextEditingController c, String label,
    {TextInputType? tipo, int lineas = 1, bool obligatorio = false, IconData? icono}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      keyboardType: tipo,
      minLines: lineas,
      maxLines: lineas == 1 ? 1 : lineas + 3,
      style: const TextStyle(fontSize: 18),
      decoration: deco(obligatorio ? '$label *' : label, icono: icono),
      validator: obligatorio
          ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null
          : null,
    ),
  );
}

Future<DateTime?> elegirFecha(BuildContext context, DateTime? inicial) {
  final hoy = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: inicial ?? hoy,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
}

// ---------- Lista genérica de módulo ----------
class ListaModulo extends StatefulWidget {
  final String titulo;
  final Future<List<Map<String, dynamic>>> Function() cargar;
  final Widget Function(BuildContext, Map<String, dynamic>, Future<void> Function() recargar) item;
  final Future<void> Function() onNuevo;
  final String vacio;
  final String Function(Map<String, dynamic>)? buscable;
  final Widget? arriba;
  const ListaModulo({
    super.key,
    required this.titulo,
    required this.cargar,
    required this.item,
    required this.onNuevo,
    required this.vacio,
    this.buscable,
    this.arriba,
  });

  @override
  State<ListaModulo> createState() => ListaModuloState();
}

class ListaModuloState extends State<ListaModulo> {
  List<Map<String, dynamic>> _datos = [];
  bool _cargando = true;
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    recargar();
  }

  Future<void> recargar() async {
    final d = await widget.cargar();
    if (!mounted) return;
    setState(() {
      _datos = d;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _filtro.toLowerCase();
    final visibles = (widget.buscable == null || f.isEmpty)
        ? _datos
        : _datos.where((e) => widget.buscable!(e).toLowerCase().contains(f)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kNaranja,
        foregroundColor: Colors.black,
        onPressed: () async {
          await widget.onNuevo();
          await recargar();
        },
        icon: const Icon(Icons.add, size: 30),
        label: const Text('NUEVO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              if (widget.buscable != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    style: const TextStyle(fontSize: 18),
                    decoration: deco('Buscar', icono: Icons.search),
                    onChanged: (v) => setState(() => _filtro = v),
                  ),
                ),
              if (widget.arriba != null) widget.arriba!,
              Expanded(
                child: visibles.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(widget.vacio,
                              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                        itemCount: visibles.length,
                        itemBuilder: (c, i) => widget.item(c, visibles[i], recargar),
                      ),
              ),
            ]),
    );
  }
}

// ---------- Selector de consorcio ----------
class ConsorcioDropdown extends StatefulWidget {
  final int? valor;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  final String etiqueta;
  const ConsorcioDropdown(
      {super.key, required this.valor, required this.onChanged, this.etiqueta = 'Consorcio *'});

  @override
  State<ConsorcioDropdown> createState() => _ConsorcioDropdownState();
}

class _ConsorcioDropdownState extends State<ConsorcioDropdown> {
  List<Map<String, dynamic>> _lista = [];
  bool _listo = false;

  @override
  void initState() {
    super.initState();
    Db.all('consorcios', orderBy: 'nombre COLLATE NOCASE').then((l) {
      if (mounted) {
        setState(() {
          _lista = l;
          _listo = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_listo) return const LinearProgressIndicator();
    if (_lista.isEmpty) {
      return const Card(
        color: Color(0xFFFFF3CD),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Primero cargá un consorcio en el módulo "Consorcios y unidades".',
              style: TextStyle(fontSize: 16)),
        ),
      );
    }
    final existe = _lista.any((e) => e['id'] == widget.valor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int>(
        value: existe ? widget.valor : null,
        isExpanded: true,
        decoration: deco(widget.etiqueta, icono: Icons.apartment),
        style: const TextStyle(fontSize: 18, color: Colors.black),
        items: _lista
            .map((e) => DropdownMenuItem<int>(
                value: e['id'] as int, child: Text(e['nombre'].toString(), overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: (v) {
          widget.onChanged(v == null ? null : _lista.firstWhere((e) => e['id'] == v));
        },
      ),
    );
  }
}

// ---------- Elegir unidad: Consorcio -> Piso -> Unidad ----------
Future<Map<String, dynamic>?> elegirUnidad(BuildContext context, int consorcioId) async {
  final unidades = await Db.all('unidades',
      where: 'consorcio_id = ?', args: [consorcioId], orderBy: 'piso, numero');
  if (!context.mounted) return null;
  if (unidades.isEmpty) {
    aviso(context, 'Este consorcio todavía no tiene unidades cargadas.');
    return null;
  }
  final pisos = <String, List<Map<String, dynamic>>>{};
  for (final u in unidades) {
    pisos.putIfAbsent((u['piso'] ?? '').toString(), () => []).add(u);
  }
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (c, scroll) => ListView(
        controller: scroll,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Elegí piso y unidad',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          for (final e in pisos.entries)
            ExpansionTile(
              title: Text('Piso ${e.key.isEmpty ? "-" : e.key}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              children: [
                for (final u in e.value)
                  ListTile(
                    minVerticalPadding: 14,
                    title: Text('Unidad ${u['numero'] ?? ''}', style: const TextStyle(fontSize: 18)),
                    subtitle: Text((u['propietario'] ?? '').toString()),
                    onTap: () => Navigator.pop(c, u),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}

// ---------- Dictado por voz ----------
class VozTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final int lineas;
  const VozTextField({super.key, required this.controller, required this.label, this.lineas = 3});

  @override
  State<VozTextField> createState() => _VozTextFieldState();
}

class _VozTextFieldState extends State<VozTextField> {
  final SpeechToText _stt = SpeechToText();
  bool _escuchando = false;

  Future<void> _alternar() async {
    if (_escuchando) {
      await _stt.stop();
      if (mounted) setState(() => _escuchando = false);
      return;
    }
    final ok = await _stt.initialize(
      onError: (e) {
        if (mounted) setState(() => _escuchando = false);
      },
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) {
          setState(() => _escuchando = false);
        }
      },
    );
    if (!ok) {
      if (mounted) {
        aviso(context,
            'El dictado no está disponible. Revisá el permiso de micrófono y que tengas el reconocimiento de voz de Google instalado.');
      }
      return;
    }
    String? localeId;
    try {
      final locs = await _stt.locales();
      for (final l in locs) {
        if (l.localeId.replaceAll('-', '_') == 'es_AR') {
          localeId = l.localeId;
          break;
        }
      }
      localeId ??= locs
          .map((l) => l.localeId)
          .cast<String?>()
          .firstWhere((l) => l!.toLowerCase().startsWith('es'), orElse: () => null);
    } catch (_) {}
    final base = widget.controller.text;
    if (mounted) setState(() => _escuchando = true);
    await _stt.listen(
      localeId: localeId,
      onResult: (r) {
        final t = r.recognizedWords;
        final nuevo = base.isEmpty ? t : '$base $t';
        widget.controller.value = TextEditingValue(
          text: nuevo,
          selection: TextSelection.collapsed(offset: nuevo.length),
        );
      },
    );
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: widget.controller,
        minLines: widget.lineas,
        maxLines: widget.lineas + 4,
        style: const TextStyle(fontSize: 18),
        decoration: deco(widget.label).copyWith(
          suffixIcon: IconButton(
            iconSize: 34,
            tooltip: 'Dictar por voz',
            color: _escuchando ? kRojo : kAzul,
            icon: Icon(_escuchando ? Icons.stop_circle : Icons.mic),
            onPressed: _alternar,
          ),
        ),
      ),
    );
  }
}

// ---------- Fotos / videos ----------
class MediosPicker extends StatefulWidget {
  final List<String> inicial;
  final ValueChanged<List<String>> onChanged;
  final String carpeta;
  final bool video;
  final String etiqueta;
  const MediosPicker({
    super.key,
    required this.inicial,
    required this.onChanged,
    required this.carpeta,
    this.video = false,
    this.etiqueta = 'Fotos',
  });

  @override
  State<MediosPicker> createState() => _MediosPickerState();
}

class _MediosPickerState extends State<MediosPicker> {
  late List<String> _m = List<String>.of(widget.inicial);

  Future<void> _agregar(bool esVid) async {
    try {
      final picker = ImagePicker();
      final XFile? x = esVid
          ? await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 2))
          : await picker.pickImage(source: ImageSource.camera, imageQuality: 75, maxWidth: 1600);
      if (x == null) return;
      final ruta = await guardarArchivo(x.path, widget.carpeta);
      if (!mounted) return;
      setState(() => _m.add(ruta));
      widget.onChanged(List<String>.of(_m));
    } catch (e) {
      if (mounted) aviso(context, 'No se pudo abrir la cámara. Revisá el permiso de cámara.');
    }
  }

  void _ver(String ruta) {
    if (esVideo(ruta)) {
      OpenFilex.open(ruta);
      return;
    }
    showDialog(
      context: context,
      builder: (c) => Dialog(
        child: InteractiveViewer(child: Image.file(File(ruta))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.etiqueta, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
              onPressed: () => _agregar(false),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Foto', style: TextStyle(fontSize: 17)),
            ),
          ),
          if (widget.video) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: () => _agregar(true),
                icon: const Icon(Icons.videocam),
                label: const Text('Video', style: TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ]),
        if (_m.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final ruta in _m)
                Stack(children: [
                  GestureDetector(
                    onTap: () => _ver(ruta),
                    child: Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                          border: Border.all(color: kAzul, width: 2),
                          borderRadius: BorderRadius.circular(8)),
                      child: esVideo(ruta)
                          ? const Icon(Icons.play_circle_fill, size: 44, color: kAzul)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(File(ruta), fit: BoxFit.cover, width: 86, height: 86,
                                  errorBuilder: (c, e, s) => const Icon(Icons.broken_image))),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: () {
                        setState(() => _m.remove(ruta));
                        widget.onChanged(List<String>.of(_m));
                      },
                      child: const CircleAvatar(
                          radius: 13, backgroundColor: kRojo, child: Icon(Icons.close, size: 16, color: Colors.white)),
                    ),
                  ),
                ]),
            ]),
          ),
      ]),
    );
  }
}

// ---------- GPS ----------
Future<Position?> obtenerUbicacion() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 20));
  } catch (_) {
    return null;
  }
}

// ---------- Selector de estado (segmentado grande) ----------
class SelectorEstado extends StatelessWidget {
  final List<String> opciones;
  final String valor;
  final ValueChanged<String> onChanged;
  final Map<String, Color>? colores;
  final Map<String, String>? etiquetas;
  const SelectorEstado(
      {super.key,
      required this.opciones,
      required this.valor,
      required this.onChanged,
      this.colores,
      this.etiquetas});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in opciones)
        ChoiceChip(
          label: Text(etiquetas?[o] ?? o, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: o == valor ? Colors.white : Colors.black)),
          selected: o == valor,
          selectedColor: colores?[o] ?? kAzul,
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          onSelected: (_) => onChanged(o),
        ),
    ]);
  }
}
