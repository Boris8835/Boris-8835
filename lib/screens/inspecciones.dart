import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../db.dart';
import '../pdf_acta.dart';
import '../widgets.dart';

// =====================================================================
// MÓDULO 2: Inspección en campo
// =====================================================================
const kChecklist = [
  'Ascensor',
  'Bomba de agua',
  'Sistema contra incendio',
  'Iluminación de pasillos',
  'Techos',
  'Humedad',
  'Cañerías',
  'Limpieza',
  'Plagas',
  'Estado del SUM',
];

const kEstadoOk = 'ok';
const kEstadoObs = 'obs';
const kEstadoUrg = 'urgente';

String etiquetaEstado(String e) =>
    e == kEstadoOk ? '✅ OK' : (e == kEstadoObs ? '⚠️ Observación' : '🔴 Urgente');

Color colorEstado(String e) => e == kEstadoOk ? kVerde : (e == kEstadoObs ? kAmbar : kRojo);

class InspeccionesScreen extends StatelessWidget {
  const InspeccionesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListaModulo(
      titulo: 'Inspecciones',
      vacio: 'No hay inspecciones guardadas.\nTocá NUEVO para hacer una.',
      cargar: () => Db.all('inspecciones'),
      buscable: (e) => '${e['consorcio_nombre']} ${fmtFecha(e['fecha'])}',
      onNuevo: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const InspeccionForm()));
      },
      item: (c, e, recargar) {
        final items = _decodificarItems(e['items']);
        final urg = items.where((i) => i['estado'] == kEstadoUrg).length;
        final obs = items.where((i) => i['estado'] == kEstadoObs).length;
        return Card(
          child: ListTile(
            minVerticalPadding: 14,
            leading: Icon(Icons.fact_check, size: 38, color: urg > 0 ? kRojo : kAzul),
            title: Text(e['consorcio_nombre']?.toString() ?? '(sin consorcio)',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            subtitle: Text('${fmtFecha(e['fecha'], hora: true)}\n🔴 $urg urgentes · ⚠️ $obs observaciones'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right, size: 30),
            onTap: () async {
              await Navigator.push(
                  c, MaterialPageRoute(builder: (_) => InspeccionForm(existente: e)));
              await recargar();
            },
          ),
        );
      },
    );
  }
}

List<Map<String, dynamic>> _decodificarItems(dynamic raw) {
  if (raw == null || raw.toString().isEmpty) return [];
  try {
    return (jsonDecode(raw as String) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  } catch (_) {
    return [];
  }
}

class _ItemEstado {
  String nombre;
  String estado;
  final TextEditingController ubicacion;
  final TextEditingController nota;
  List<String> medios;
  _ItemEstado(this.nombre, this.estado, String ubic, String nota, this.medios)
      : ubicacion = TextEditingController(text: ubic),
        nota = TextEditingController(text: nota);

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'estado': estado,
        'ubicacion': ubicacion.text.trim(),
        'nota': nota.text.trim(),
        'medios': medios,
      };
}

class InspeccionForm extends StatefulWidget {
  final Map<String, dynamic>? existente;
  const InspeccionForm({super.key, this.existente});

  @override
  State<InspeccionForm> createState() => _InspeccionFormState();
}

class _InspeccionFormState extends State<InspeccionForm> {
  int? _id;
  int? _consorcioId;
  String _consorcioNombre = '';
  late String _fecha;
  double? _lat, _lng;
  bool _buscandoGps = false;
  final _notas = TextEditingController();
  final List<_ItemEstado> _items = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _id = e['id'] as int;
      _consorcioId = e['consorcio_id'] as int?;
      _consorcioNombre = (e['consorcio_nombre'] ?? '').toString();
      _fecha = (e['fecha'] ?? DateTime.now().toIso8601String()).toString();
      _lat = (e['lat'] as num?)?.toDouble();
      _lng = (e['lng'] as num?)?.toDouble();
      _notas.text = (e['notas'] ?? '').toString();
      for (final i in _decodificarItems(e['items'])) {
        _items.add(_ItemEstado(
          i['nombre'].toString(),
          (i['estado'] ?? kEstadoOk).toString(),
          (i['ubicacion'] ?? '').toString(),
          (i['nota'] ?? '').toString(),
          (i['medios'] as List? ?? []).map((x) => x.toString()).toList(),
        ));
      }
    } else {
      _fecha = DateTime.now().toIso8601String();
      for (final n in kChecklist) {
        _items.add(_ItemEstado(n, kEstadoOk, '', '', []));
      }
      _buscarGps();
    }
  }

  Future<void> _buscarGps() async {
    setState(() => _buscandoGps = true);
    final pos = await obtenerUbicacion();
    if (!mounted) return;
    setState(() {
      _buscandoGps = false;
      if (pos != null) {
        _lat = pos.latitude;
        _lng = pos.longitude;
      }
    });
    if (pos == null) {
      aviso(context, 'No se pudo obtener el GPS (activá la ubicación y el permiso). Podés guardar igual.');
    }
  }

  Future<int?> _guardar({bool silencioso = false}) async {
    if (_consorcioNombre.trim().isEmpty) {
      aviso(context, 'Elegí el consorcio.');
      return null;
    }
    final id = await Db.save('inspecciones', {
      'id': _id,
      'consorcio_id': _consorcioId,
      'consorcio_nombre': _consorcioNombre,
      'fecha': _fecha,
      'lat': _lat,
      'lng': _lng,
      'notas': _notas.text.trim(),
      'items': jsonEncode(_items.map((e) => e.toMap()).toList()),
    });
    _id = id;
    if (!silencioso && mounted) {
      aviso(context, 'Inspección guardada.');
    }
    return id;
  }

  Future<void> _acta() async {
    final id = await _guardar(silencioso: true);
    if (id == null) return;
    try {
      final insp = (await Db.one('inspecciones', id))!;
      final cons = _consorcioId == null ? null : await Db.one('consorcios', _consorcioId!);
      final archivo = await generarActaPdf(insp, cons);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Acta PDF generada',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              BotonGrande(
                  icono: Icons.visibility,
                  texto: 'ABRIR',
                  onPressed: () {
                    Navigator.pop(c);
                    OpenFilex.open(archivo.path);
                  }),
              const SizedBox(height: 10),
              BotonGrande(
                  icono: Icons.share,
                  texto: 'ENVIAR AL CONSEJO (WhatsApp / correo)',
                  color: kVerde,
                  onPressed: () {
                    Navigator.pop(c);
                    Share.shareXFiles([XFile(archivo.path)],
                        text: 'Acta de inspección - $_consorcioNombre - ${fmtFecha(_fecha)}');
                  }),
            ]),
          ),
        ),
      );
    } catch (e) {
      if (mounted) aviso(context, 'No se pudo generar el PDF: $e');
    }
  }

  Future<void> _eliminar() async {
    if (!await confirmar(context, 'Se elimina SOLO esta inspección. Gastos, reclamos y órdenes no se tocan.')) return;
    await Db.delete('inspecciones', _id!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _itemPersonalizado() async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Agregar ítem'),
        content: TextField(controller: t, decoration: deco('Ej: Portón del garage')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Agregar')),
        ],
      ),
    );
    if (ok == true && t.text.trim().isNotEmpty) {
      setState(() => _items.add(_ItemEstado(t.text.trim(), kEstadoOk, '', '', [])));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? 'Nueva inspección' : 'Inspección'),
        actions: [
          if (_id != null) IconButton(icon: const Icon(Icons.delete), onPressed: _eliminar),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        ConsorcioDropdown(
          valor: _consorcioId,
          onChanged: (c) => setState(() {
            _consorcioId = c?['id'] as int?;
            _consorcioNombre = c?['nombre']?.toString() ?? _consorcioNombre;
          }),
        ),
        if (_id != null && _consorcioNombre.isNotEmpty && _consorcioId == null)
          Text('Consorcio: $_consorcioNombre', style: const TextStyle(fontSize: 16)),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Fecha y hora: ${fmtFecha(_fecha, hora: true)}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                  _lat == null
                      ? 'GPS: sin ubicación'
                      : 'GPS: ${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                onPressed: _buscandoGps ? null : _buscarGps,
                icon: const Icon(Icons.my_location),
                label: Text(_buscandoGps ? 'Buscando GPS...' : 'Actualizar ubicación GPS'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        const Text('Check-list', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        for (final it in _items)
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colorEstado(it.estado), width: 2.5)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(it.nombre,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  if (!kChecklist.contains(it.nombre))
                    IconButton(
                        icon: const Icon(Icons.close, color: kRojo),
                        onPressed: () => setState(() => _items.remove(it))),
                ]),
                const SizedBox(height: 8),
                SelectorEstado(
                  opciones: const [kEstadoOk, kEstadoObs, kEstadoUrg],
                  valor: it.estado,
                  colores: {kEstadoOk: kVerde, kEstadoObs: kAmbar, kEstadoUrg: kRojo},
                  onChanged: (v) => setState(() => it.estado = v),
                  etiquetas: const {kEstadoOk: '✅ OK', kEstadoObs: '⚠️ Obs.', kEstadoUrg: '🔴 Urgente'},
                ),
                if (it.estado != kEstadoOk) ...[
                  const SizedBox(height: 12),
                  campo(it.ubicacion, 'Ubicación en el edificio (ej: Piso 3, palier)', icono: Icons.place),
                  VozTextField(controller: it.nota, label: 'Anotación (podés dictar)', lineas: 2),
                  MediosPicker(
                    inicial: it.medios,
                    carpeta: 'inspecciones',
                    video: true,
                    etiqueta: 'Fotos / video',
                    onChanged: (l) => it.medios = l,
                  ),
                ],
              ]),
            ),
          ),
        TextButton.icon(
            onPressed: _itemPersonalizado,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Agregar otro ítem', style: TextStyle(fontSize: 17))),
        const SizedBox(height: 6),
        VozTextField(controller: _notas, label: 'Observaciones generales', lineas: 3),
        BotonGrande(icono: Icons.save, texto: 'GUARDAR INSPECCIÓN', onPressed: _guardar),
        const SizedBox(height: 10),
        BotonGrande(
            icono: Icons.picture_as_pdf,
            texto: 'GENERAR ACTA PDF',
            color: kNaranja.withAlpha(255),
            onPressed: _acta),
        const SizedBox(height: 40),
      ]),
    );
  }
}
