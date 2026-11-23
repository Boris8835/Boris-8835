import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../db.dart';
import '../widgets.dart';

// =====================================================================
// MÓDULO 3: Órdenes de trabajo
// =====================================================================
const kEstadosOrden = ['Pendiente', 'En curso', 'Finalizado'];
const kColoresOrden = {'Pendiente': kRojo, 'En curso': kAmbar, 'Finalizado': kVerde};

class OrdenesScreen extends StatefulWidget {
  const OrdenesScreen({super.key});

  @override
  State<OrdenesScreen> createState() => _OrdenesScreenState();
}

class _OrdenesScreenState extends State<OrdenesScreen> {
  String _filtro = 'Todas';
  final _lista = GlobalKey<ListaModuloState>();

  @override
  Widget build(BuildContext context) {
    return ListaModulo(
      key: _lista,
      titulo: 'Órdenes de trabajo',
      vacio: 'No hay órdenes.\nTocá NUEVO para crear una.',
      cargar: () => Db.all('ordenes',
          where: _filtro == 'Todas' ? null : 'estado = ?',
          args: _filtro == 'Todas' ? null : [_filtro]),
      buscable: (e) => '${e['consorcio_nombre']} ${e['descripcion']} ${e['proveedor']}',
      arriba: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: double.infinity,
          child: Wrap(spacing: 8, children: [
            for (final f in ['Todas', ...kEstadosOrden])
              ChoiceChip(
                label: Text(f, style: const TextStyle(fontSize: 16)),
                selected: _filtro == f,
                onSelected: (_) {
                  setState(() => _filtro = f);
                  _lista.currentState?.recargar();
                },
              ),
          ]),
        ),
      ),
      onNuevo: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdenForm()));
      },
      item: (c, e, recargar) {
        final estado = (e['estado'] ?? 'Pendiente').toString();
        final idx = kEstadosOrden.indexOf(estado);
        return Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: kColoresOrden[estado] ?? kAzul, width: 2.5)),
          child: Column(children: [
            ListTile(
              minVerticalPadding: 12,
              title: Text(e['descripcion'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${e['consorcio_nombre'] ?? ''}\nProveedor: ${(e['proveedor'] ?? '').toString().isEmpty ? '-' : e['proveedor']}\nLímite: ${fmtFecha(e['fecha_limite']?.toString())}'),
              isThreeLine: true,
              trailing: Chip(
                  label: Text(estado,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  backgroundColor: kColoresOrden[estado]),
              onTap: () async {
                await Navigator.push(c, MaterialPageRoute(builder: (_) => OrdenForm(existente: e)));
                await recargar();
              },
            ),
            if (idx >= 0 && idx < 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: BotonGrande(
                  icono: Icons.arrow_forward,
                  texto: 'Pasar a "${kEstadosOrden[idx + 1]}"',
                  color: kColoresOrden[kEstadosOrden[idx + 1]],
                  onPressed: () async {
                    final nuevo = Map<String, dynamic>.from(e)..['estado'] = kEstadosOrden[idx + 1];
                    await Db.save('ordenes', nuevo);
                    await recargar();
                  },
                ),
              ),
          ]),
        );
      },
    );
  }
}

class OrdenForm extends StatefulWidget {
  final Map<String, dynamic>? existente;
  const OrdenForm({super.key, this.existente});

  @override
  State<OrdenForm> createState() => _OrdenFormState();
}

class _OrdenFormState extends State<OrdenForm> {
  final _k = GlobalKey<FormState>();
  int? _consorcioId;
  String _consorcioNombre = '';
  final _desc = TextEditingController();
  final _prov = TextEditingController();
  DateTime? _limite;
  String _estado = 'Pendiente';
  List<String> _fotos = [];
  String? _factura;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _consorcioId = e['consorcio_id'] as int?;
      _consorcioNombre = (e['consorcio_nombre'] ?? '').toString();
      _desc.text = (e['descripcion'] ?? '').toString();
      _prov.text = (e['proveedor'] ?? '').toString();
      _limite = DateTime.tryParse((e['fecha_limite'] ?? '').toString());
      _estado = (e['estado'] ?? 'Pendiente').toString();
      _fotos = listaDeJson(e['fotos']);
      _factura = e['factura']?.toString();
    }
  }

  Future<void> _guardar() async {
    if (!_k.currentState!.validate()) return;
    if (_consorcioNombre.isEmpty) {
      aviso(context, 'Elegí el consorcio.');
      return;
    }
    await Db.save('ordenes', {
      'id': widget.existente?['id'],
      'consorcio_id': _consorcioId,
      'consorcio_nombre': _consorcioNombre,
      'descripcion': _desc.text.trim(),
      'fotos': jsonEncode(_fotos),
      'proveedor': _prov.text.trim(),
      'fecha_limite': _limite?.toIso8601String(),
      'estado': _estado,
      'factura': _factura,
      'creado': widget.existente?['creado'] ?? DateTime.now().toIso8601String(),
    });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _eliminar() async {
    if (!await confirmar(context, 'Se elimina SOLO esta orden de trabajo.')) return;
    await Db.delete('ordenes', widget.existente!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _adjuntarFactura() async {
    final op = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Sacar foto de la factura', style: TextStyle(fontSize: 18)),
              onTap: () => Navigator.pop(c, 'foto')),
          ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Elegir archivo (PDF / imagen)', style: TextStyle(fontSize: 18)),
              onTap: () => Navigator.pop(c, 'archivo')),
        ]),
      ),
    );
    if (op == null) return;
    String? origen;
    if (op == 'foto') {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1800);
      origen = x?.path;
    } else {
      final r = await FilePicker.platform.pickFiles();
      origen = r?.files.single.path;
    }
    if (origen == null) return;
    final ruta = await guardarArchivo(origen, 'facturas');
    if (mounted) setState(() => _factura = ruta);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existente == null ? 'Nueva orden' : 'Orden de trabajo'),
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
          VozTextField(controller: _desc, label: 'Descripción del fallo *', lineas: 3),
          MediosPicker(
              inicial: _fotos,
              carpeta: 'ordenes',
              etiqueta: 'Fotos tomadas en el lugar',
              onChanged: (l) => _fotos = l),
          campo(_prov, 'Proveedor / encargado asignado', icono: Icons.engineering),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
            icon: const Icon(Icons.event),
            label: Text(_limite == null ? 'Fecha límite' : 'Fecha límite: ${fmtFecha(_limite!.toIso8601String())}',
                style: const TextStyle(fontSize: 17)),
            onPressed: () async {
              final f = await elegirFecha(context, _limite);
              if (f != null) setState(() => _limite = f);
            },
          ),
          const SizedBox(height: 14),
          const Text('Estado', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectorEstado(
              opciones: kEstadosOrden,
              valor: _estado,
              colores: kColoresOrden,
              onChanged: (v) => setState(() => _estado = v)),
          const SizedBox(height: 14),
          if (_estado == 'Finalizado') ...[
            const Text('Factura del trabajo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            BotonGrande(
                icono: Icons.receipt_long,
                texto: _factura == null ? 'ADJUNTAR FACTURA' : 'CAMBIAR FACTURA',
                color: kVerde,
                onPressed: _adjuntarFactura),
            if (_factura != null)
              TextButton.icon(
                  onPressed: () => OpenFilex.open(_factura!),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ver factura adjunta', style: TextStyle(fontSize: 17))),
            const SizedBox(height: 14),
          ],
          BotonGrande(icono: Icons.save, texto: 'GUARDAR ORDEN', onPressed: _guardar),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}
