import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../db.dart';
import '../widgets.dart';

// =====================================================================
// MÓDULO 5: Reclamos vecinales (cada reclamo tiene su propio historial)
// =====================================================================
const kEstadosReclamo = ['Abierto', 'En gestión', 'Resuelto'];
const kColoresReclamo = {'Abierto': kRojo, 'En gestión': kAmbar, 'Resuelto': kVerde};

class ReclamosScreen extends StatelessWidget {
  const ReclamosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListaModulo(
      titulo: 'Reclamos vecinales',
      vacio: 'No hay reclamos registrados.\nTocá NUEVO para cargar uno.',
      cargar: () => Db.all('reclamos'),
      buscable: (e) => '${e['consorcio_nombre']} ${e['propietario']} ${e['unidad']} ${e['descripcion']}',
      onNuevo: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReclamoForm()));
      },
      item: (c, e, recargar) {
        final estado = (e['estado'] ?? 'Abierto').toString();
        return Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: kColoresReclamo[estado] ?? kAzul, width: 2.5)),
          child: ListTile(
            minVerticalPadding: 12,
            title: Text('${e['propietario'] ?? ''} · ${e['unidad'] ?? ''}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            subtitle: Text(
                '${e['consorcio_nombre'] ?? ''}\n${e['descripcion'] ?? ''}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            isThreeLine: true,
            trailing: Chip(
                label: Text(estado,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                backgroundColor: kColoresReclamo[estado]),
            onTap: () async {
              await Navigator.push(c, MaterialPageRoute(builder: (_) => ReclamoForm(existente: e)));
              await recargar();
            },
          ),
        );
      },
    );
  }
}

class ReclamoForm extends StatefulWidget {
  final Map<String, dynamic>? existente;
  const ReclamoForm({super.key, this.existente});

  @override
  State<ReclamoForm> createState() => _ReclamoFormState();
}

class _ReclamoFormState extends State<ReclamoForm> {
  final _k = GlobalKey<FormState>();
  int? _id;
  int? _consorcioId;
  String _consorcioNombre = '';
  final _unidad = TextEditingController();
  final _prop = TextEditingController();
  final _tel = TextEditingController();
  final _desc = TextEditingController();
  String _estado = 'Abierto';
  String _estadoOriginal = 'Abierto';
  List<String> _fotos = [];
  List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _id = e['id'] as int;
      _consorcioId = e['consorcio_id'] as int?;
      _consorcioNombre = (e['consorcio_nombre'] ?? '').toString();
      _unidad.text = (e['unidad'] ?? '').toString();
      _prop.text = (e['propietario'] ?? '').toString();
      _tel.text = (e['telefono'] ?? '').toString();
      _desc.text = (e['descripcion'] ?? '').toString();
      _estado = (e['estado'] ?? 'Abierto').toString();
      _estadoOriginal = _estado;
      _fotos = listaDeJson(e['fotos']);
      _cargarHistorial();
    }
  }

  Future<void> _cargarHistorial() async {
    if (_id == null) return;
    final h = await Db.all('reclamo_historial', where: 'reclamo_id = ?', args: [_id], orderBy: 'id DESC');
    if (mounted) setState(() => _historial = h);
  }

  Future<void> _elegirUnidad() async {
    if (_consorcioId == null) {
      aviso(context, 'Primero elegí el consorcio.');
      return;
    }
    final u = await elegirUnidad(context, _consorcioId!);
    if (u == null) return;
    setState(() {
      _unidad.text = 'Piso ${u['piso']} - Unidad ${u['numero']}';
      if (_prop.text.isEmpty) _prop.text = (u['propietario'] ?? '').toString();
      if (_tel.text.isEmpty) _tel.text = (u['telefono'] ?? '').toString();
    });
  }

  Future<void> _guardar() async {
    if (!_k.currentState!.validate()) return;
    if (_consorcioNombre.isEmpty) {
      aviso(context, 'Elegí el consorcio.');
      return;
    }
    final eraNuevo = _id == null;
    final id = await Db.save('reclamos', {
      'id': _id,
      'consorcio_id': _consorcioId,
      'consorcio_nombre': _consorcioNombre,
      'unidad': _unidad.text.trim(),
      'propietario': _prop.text.trim(),
      'telefono': _tel.text.trim(),
      'descripcion': _desc.text.trim(),
      'fotos': jsonEncode(_fotos),
      'estado': _estado,
      'creado': widget.existente?['creado'] ?? DateTime.now().toIso8601String(),
    });
    _id = id;
    if (eraNuevo) {
      await Db.save('reclamo_historial', {
        'reclamo_id': id,
        'fecha': DateTime.now().toIso8601String(),
        'texto': 'Reclamo registrado.',
      });
    } else if (_estado != _estadoOriginal) {
      await Db.save('reclamo_historial', {
        'reclamo_id': id,
        'fecha': DateTime.now().toIso8601String(),
        'texto': 'Estado cambiado a: $_estado',
      });
    }
    _estadoOriginal = _estado;
    await _cargarHistorial();
    if (mounted) aviso(context, 'Reclamo guardado. Podés agregar seguimientos abajo.');
  }

  Future<void> _eliminar() async {
    if (!await confirmar(context, 'Se elimina SOLO este reclamo y su historial.')) return;
    await Db.deleteWhere('reclamo_historial', 'reclamo_id = ?', [_id]);
    await Db.delete('reclamos', _id!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _nuevoSeguimiento() async {
    final texto = TextEditingController();
    List<String> foto = [];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Agregar al historial'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            VozTextField(controller: texto, label: 'Novedad (podés dictar)', lineas: 3),
            MediosPicker(inicial: const [], carpeta: 'reclamos', onChanged: (l) => foto = l),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || (texto.text.trim().isEmpty && foto.isEmpty)) return;
    await Db.save('reclamo_historial', {
      'reclamo_id': _id,
      'fecha': DateTime.now().toIso8601String(),
      'texto': texto.text.trim(),
      'foto': foto.isEmpty ? null : foto.first,
    });
    await _cargarHistorial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? 'Nuevo reclamo' : 'Reclamo'),
        actions: [if (_id != null) IconButton(icon: const Icon(Icons.delete), onPressed: _eliminar)],
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
          BotonGrande(
              icono: Icons.meeting_room,
              texto: 'ELEGIR PISO / UNIDAD',
              color: const Color(0xFF1565C0),
              onPressed: _elegirUnidad),
          const SizedBox(height: 12),
          campo(_unidad, 'Unidad', obligatorio: true, icono: Icons.door_front_door),
          campo(_prop, 'Propietario / inquilino', obligatorio: true, icono: Icons.person),
          campo(_tel, 'Teléfono', tipo: TextInputType.phone, icono: Icons.phone),
          VozTextField(controller: _desc, label: 'Detalle del reclamo (podés dictar)', lineas: 3),
          MediosPicker(
              inicial: _fotos, carpeta: 'reclamos', etiqueta: 'Foto del reclamo', onChanged: (l) => _fotos = l),
          const Text('Estado', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectorEstado(
              opciones: kEstadosReclamo,
              valor: _estado,
              colores: kColoresReclamo,
              onChanged: (v) => setState(() => _estado = v)),
          const SizedBox(height: 14),
          BotonGrande(icono: Icons.save, texto: 'GUARDAR RECLAMO', onPressed: _guardar),
          if (_id != null) ...[
            const SizedBox(height: 22),
            Row(children: [
              const Expanded(
                  child: Text('Historial de este reclamo',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kNaranja, foregroundColor: Colors.black),
                onPressed: _nuevoSeguimiento,
                icon: const Icon(Icons.add),
                label: const Text('Novedad'),
              ),
            ]),
            for (final h in _historial)
              Card(
                child: ListTile(
                  title: Text((h['texto'] ?? '').toString().isEmpty ? '(foto)' : h['texto'].toString(),
                      style: const TextStyle(fontSize: 17)),
                  subtitle: Text(fmtFecha(h['fecha']?.toString(), hora: true)),
                  leading: h['foto'] != null && File(h['foto'].toString()).existsSync()
                      ? Image.file(File(h['foto'].toString()), width: 50, height: 50, fit: BoxFit.cover)
                      : const Icon(Icons.history, color: kAzul),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: kRojo),
                    onPressed: () async {
                      if (!await confirmar(context, 'Se elimina solo esta entrada del historial.')) return;
                      await Db.delete('reclamo_historial', h['id'] as int);
                      await _cargarHistorial();
                    },
                  ),
                ),
              ),
          ],
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}
