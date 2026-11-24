import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../db.dart';
import '../expensas.dart';
import '../widgets.dart';

// =====================================================================
// MÓDULO 1: Consorcios y unidades
// =====================================================================
class ConsorciosScreen extends StatelessWidget {
  const ConsorciosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListaModulo(
      titulo: 'Consorcios',
      vacio: 'Todavía no cargaste consorcios.\nTocá NUEVO para empezar.',
      cargar: () => Db.all('consorcios', orderBy: 'nombre COLLATE NOCASE'),
      buscable: (e) => '${e['nombre']} ${e['direccion']} ${e['cuit']}',
      onNuevo: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConsorcioForm()));
      },
      item: (c, e, recargar) => Card(
        child: ListTile(
          minVerticalPadding: 14,
          leading: const Icon(Icons.apartment, size: 38, color: kAzul),
          title: Text(e['nombre'].toString(),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          subtitle: Text('${e['direccion'] ?? ''}\nCUIT: ${e['cuit'] ?? '-'}'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right, size: 30),
          onTap: () async {
            await Navigator.push(
                c, MaterialPageRoute(builder: (_) => ConsorcioDetalle(id: e['id'] as int)));
            await recargar();
          },
        ),
      ),
    );
  }
}

class ConsorcioForm extends StatefulWidget {
  final Map<String, dynamic>? existente;
  const ConsorcioForm({super.key, this.existente});

  @override
  State<ConsorcioForm> createState() => _ConsorcioFormState();
}

class _ConsorcioFormState extends State<ConsorcioForm> {
  final _k = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.existente?['nombre']);
  late final _cuit = TextEditingController(text: widget.existente?['cuit']);
  late final _dir = TextEditingController(text: widget.existente?['direccion']);
  late final _adm = TextEditingController(text: widget.existente?['admin_nombre']);
  late final _tel = TextEditingController(text: widget.existente?['admin_tel']);
  late final _mail = TextEditingController(text: widget.existente?['admin_email']);
  late final _notas = TextEditingController(text: widget.existente?['notas']);

  Future<void> _guardar() async {
    if (!_k.currentState!.validate()) return;
    final v = <String, dynamic>{
      'id': widget.existente?['id'],
      'nombre': _nombre.text.trim(),
      'cuit': _cuit.text.trim(),
      'direccion': _dir.text.trim(),
      'admin_nombre': _adm.text.trim(),
      'admin_tel': _tel.text.trim(),
      'admin_email': _mail.text.trim(),
      'notas': _notas.text.trim(),
      'creado': widget.existente?['creado'] ?? DateTime.now().toIso8601String(),
    };
    await Db.save('consorcios', v);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existente == null ? 'Nuevo consorcio' : 'Editar consorcio')),
      body: Form(
        key: _k,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          campo(_nombre, 'Nombre del consorcio', obligatorio: true, icono: Icons.apartment),
          campo(_cuit, 'CUIT', tipo: TextInputType.number, icono: Icons.badge),
          campo(_dir, 'Dirección', icono: Icons.place),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Datos del administrador',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          campo(_adm, 'Nombre y apellido / razón social', icono: Icons.person),
          campo(_tel, 'Teléfono', tipo: TextInputType.phone, icono: Icons.phone),
          campo(_mail, 'Correo electrónico', tipo: TextInputType.emailAddress, icono: Icons.email),
          campo(_notas, 'Notas', lineas: 3),
          BotonGrande(icono: Icons.save, texto: 'GUARDAR', onPressed: _guardar),
        ]),
      ),
    );
  }
}

class ConsorcioDetalle extends StatefulWidget {
  final int id;
  const ConsorcioDetalle({super.key, required this.id});

  @override
  State<ConsorcioDetalle> createState() => _ConsorcioDetalleState();
}

class _ConsorcioDetalleState extends State<ConsorcioDetalle> {
  Map<String, dynamic>? _c;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final c = await Db.one('consorcios', widget.id);
    if (mounted) setState(() => _c = c);
  }

  Future<void> _eliminar() async {
    final ok = await confirmar(
        context,
        'Se elimina el consorcio con sus unidades y archivos.\n\n'
        'Las inspecciones, órdenes, gastos y reclamos ya guardados NO se borran.');
    if (!ok) return;
    await Db.deleteWhere('unidades', 'consorcio_id = ?', [widget.id]);
    await Db.deleteWhere('documentos', 'consorcio_id = ?', [widget.id]);
    await Db.delete('consorcios', widget.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(c['nombre'].toString()),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar',
              onPressed: () async {
                await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => ConsorcioForm(existente: c)));
                await _cargar();
              },
            ),
            IconButton(icon: const Icon(Icons.delete), tooltip: 'Eliminar', onPressed: _eliminar),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: kNaranja,
            labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            tabs: [Tab(text: 'DATOS'), Tab(text: 'UNIDADES'), Tab(text: 'ARCHIVOS')],
          ),
        ),
        body: TabBarView(children: [
          _Datos(c: c),
          _Unidades(consorcioId: widget.id),
          _Archivos(consorcioId: widget.id),
        ]),
      ),
    );
  }
}

class _Datos extends StatelessWidget {
  final Map<String, dynamic> c;
  const _Datos({required this.c});

  Widget _fila(IconData i, String t, dynamic v) => Card(
        child: ListTile(
          leading: Icon(i, color: kAzul, size: 30),
          title: Text(t, style: const TextStyle(fontSize: 14)),
          subtitle: Text((v == null || v.toString().isEmpty) ? '-' : v.toString(),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.black)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      _fila(Icons.apartment, 'Nombre', c['nombre']),
      _fila(Icons.badge, 'CUIT', c['cuit']),
      _fila(Icons.place, 'Dirección', c['direccion']),
      _fila(Icons.person, 'Administrador', c['admin_nombre']),
      _fila(Icons.phone, 'Teléfono', c['admin_tel']),
      _fila(Icons.email, 'Correo', c['admin_email']),
      _fila(Icons.notes, 'Notas', c['notas']),
    ]);
  }
}

// ---------------- Unidades ----------------
class _Unidades extends StatefulWidget {
  final int consorcioId;
  const _Unidades({required this.consorcioId});

  @override
  State<_Unidades> createState() => _UnidadesState();
}

class _UnidadesState extends State<_Unidades> {
  List<Map<String, dynamic>> _u = [];
  String _f = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final l = await Db.all('unidades',
        where: 'consorcio_id = ?', args: [widget.consorcioId], orderBy: 'piso, numero');
    if (mounted) setState(() => _u = l);
  }

  Future<void> _generar() async {
    final pisos = TextEditingController(text: '5');
    final deptos = TextEditingController(text: '2');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Generar unidades'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Crea Planta Baja + pisos, con deptos A, B, C... y coeficientes iguales. Después podés editar cada una.'),
          const SizedBox(height: 12),
          TextField(controller: pisos, keyboardType: TextInputType.number, decoration: deco('Cantidad de pisos (sin PB)')),
          const SizedBox(height: 10),
          TextField(controller: deptos, keyboardType: TextInputType.number, decoration: deco('Deptos por piso')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Generar')),
        ],
      ),
    );
    if (ok != true) return;
    final np = int.tryParse(pisos.text) ?? 0;
    final nd = int.tryParse(deptos.text) ?? 0;
    if (np < 0 || nd < 1 || np > 60 || nd > 12) {
      if (mounted) aviso(context, 'Valores fuera de rango.');
      return;
    }
    final total = (np + 1) * nd;
    final coef = double.parse((100 / total).toStringAsFixed(4));
    for (var piso = 0; piso <= np; piso++) {
      for (var d = 0; d < nd; d++) {
        await Db.save('unidades', {
          'consorcio_id': widget.consorcioId,
          'piso': piso == 0 ? 'PB' : piso.toString().padLeft(2, '0'),
          'numero': String.fromCharCode(65 + d),
          'propietario': '',
          'telefono': '',
          'coeficiente': coef,
          'saldo': 0.0,
        });
      }
    }
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final f = _f.toLowerCase();
    final vis = f.isEmpty
        ? _u
        : _u.where((e) => '${e['piso']} ${e['numero']} ${e['propietario']}'.toLowerCase().contains(f)).toList();
    final sumaCoef = _u.fold<double>(0, (a, e) => a + ((e['coeficiente'] as num?)?.toDouble() ?? 0));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          style: const TextStyle(fontSize: 18),
          decoration: deco('Buscar piso, unidad o propietario', icono: Icons.search),
          onChanged: (v) => setState(() => _f = v),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          Expanded(
            child: Text('${_u.length} unidades · Σ coef. ${sumaCoef.toStringAsFixed(2)}%',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
              onPressed: _generar, icon: const Icon(Icons.auto_awesome), label: const Text('Generar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kNaranja, foregroundColor: Colors.black),
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => UnidadForm(consorcioId: widget.consorcioId)));
              await _cargar();
            },
            icon: const Icon(Icons.add),
            label: const Text('Unidad'),
          ),
        ]),
      ),
      Expanded(
        child: vis.isEmpty
            ? const Center(child: Text('Sin unidades.', style: TextStyle(fontSize: 18)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: vis.length,
                itemBuilder: (c, i) {
                  final u = vis[i];
                  final saldo = (u['saldo'] as num?)?.toDouble() ?? 0;
                  return Card(
                    child: ListTile(
                      minVerticalPadding: 12,
                      leading: CircleAvatar(
                          radius: 26,
                          backgroundColor: kAzul,
                          child: Text('${u['piso'] ?? ''}${u['numero'] ?? ''}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                      title: Text(
                          (u['propietario'] ?? '').toString().isEmpty ? '(sin propietario)' : u['propietario'].toString(),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          'Piso ${u['piso']} · Unidad ${u['numero']} · Coef. ${u['coeficiente']}%'),
                      trailing: Text(fmtPlata(saldo),
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800, color: saldo > 0 ? kRojo : kVerde)),
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    UnidadForm(consorcioId: widget.consorcioId, existente: u)));
                        await _cargar();
                      },
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class UnidadForm extends StatefulWidget {
  final int consorcioId;
  final Map<String, dynamic>? existente;
  const UnidadForm({super.key, required this.consorcioId, this.existente});

  @override
  State<UnidadForm> createState() => _UnidadFormState();
}

class _UnidadFormState extends State<UnidadForm> {
  final _k = GlobalKey<FormState>();
  late final _piso = TextEditingController(text: widget.existente?['piso']);
  late final _num = TextEditingController(text: widget.existente?['numero']);
  late final _prop = TextEditingController(text: widget.existente?['propietario']);
  late final _tel = TextEditingController(text: widget.existente?['telefono']);
  late final _coef = TextEditingController(
      text: widget.existente == null ? '' : widget.existente!['coeficiente'].toString());
  late final _saldo = TextEditingController(
      text: widget.existente == null ? '0' : widget.existente!['saldo'].toString());

  List<Map<String, dynamic>> _exp = [];

  @override
  void initState() {
    super.initState();
    _recargarCuenta();
  }

  Future<void> _recargarCuenta() async {
    final id = widget.existente?['id'] as int?;
    if (id == null) return;
    final u = await Db.one('unidades', id);
    final e = await Expensas.deUnidad(id);
    if (!mounted) return;
    setState(() {
      _exp = e;
      if (u != null) _saldo.text = u['saldo'].toString();
    });
  }

  List<Widget> _seccionCuenta() {
    final saldo = parseNumero(_saldo.text) ?? 0;
    final debe = saldo > 0.005;
    return [
      const SizedBox(height: 18),
      Card(
        color: debe ? const Color(0xFFFDECEA) : const Color(0xFFE8F5E9),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: debe ? kRojo : kVerde, width: 2.5)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(debe ? Icons.warning_amber_rounded : Icons.check_circle,
                size: 40, color: debe ? kRojo : kVerde),
            const SizedBox(width: 12),
            Expanded(
              child: Text(debe ? 'DEBE ${fmtPlata(saldo)}' : 'AL DÍA',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: debe ? kRojo : kVerde)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      BotonGrande(
          icono: Icons.picture_as_pdf,
          texto: 'COMPARTIR ESTADO DE CUENTA (PDF)',
          color: kVerde,
          onPressed: () => compartirEstadoCuenta(context, widget.existente!['id'] as int)),
      const SizedBox(height: 18),
      const Text('Expensas de esta unidad', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      if (_exp.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Todavía no hay expensas emitidas. Se emiten desde "Liquidación de expensas".',
                style: TextStyle(fontSize: 16))),
      for (final e in _exp) TarjetaExpensa(key: ValueKey(e['id']), e: e, mostrarUnidad: false, onCambio: _recargarCuenta),
      const SizedBox(height: 30),
    ];
  }

  Future<void> _guardar() async {
    if (!_k.currentState!.validate()) return;
    await Db.save('unidades', {
      'id': widget.existente?['id'],
      'consorcio_id': widget.consorcioId,
      'piso': _piso.text.trim(),
      'numero': _num.text.trim(),
      'propietario': _prop.text.trim(),
      'telefono': _tel.text.trim(),
      'coeficiente': parseNumero(_coef.text) ?? 0.0,
      'saldo': parseNumero(_saldo.text) ?? 0.0,
    });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _eliminar() async {
    if (!await confirmar(context, 'Se elimina solo esta unidad.')) return;
    await Db.delete('unidades', widget.existente!['id'] as int);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existente == null ? 'Nueva unidad' : 'Editar unidad'),
        actions: [
          if (widget.existente != null) IconButton(icon: const Icon(Icons.delete), onPressed: _eliminar),
        ],
      ),
      body: Form(
        key: _k,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          campo(_piso, 'Piso (ej: PB, 01, 02)', obligatorio: true),
          campo(_num, 'Unidad / Depto (ej: A, 12)', obligatorio: true),
          campo(_prop, 'Propietario / inquilino (nombre y apellido)', icono: Icons.person),
          campo(_tel, 'Teléfono', tipo: TextInputType.phone, icono: Icons.phone),
          campo(_coef, 'Coeficiente de expensas (%)', tipo: const TextInputType.numberWithOptions(decimal: true)),
          campo(_saldo, 'Saldo pendiente de expensas (\$)', tipo: const TextInputType.numberWithOptions(decimal: true)),
          BotonGrande(icono: Icons.save, texto: 'GUARDAR', onPressed: _guardar),
          if (widget.existente != null) ..._seccionCuenta(),
        ]),
      ),
    );
  }
}

// ---------------- Archivos ----------------
const kTiposDoc = [
  'Reglamento',
  'Acta',
  'Seguro',
  'Matrícula',
  'Certificación contra incendio',
  'Otro'
];

class _Archivos extends StatefulWidget {
  final int consorcioId;
  const _Archivos({required this.consorcioId});

  @override
  State<_Archivos> createState() => _ArchivosState();
}

class _ArchivosState extends State<_Archivos> {
  List<Map<String, dynamic>> _d = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final l = await Db.all('documentos', where: 'consorcio_id = ?', args: [widget.consorcioId]);
    if (mounted) setState(() => _d = l);
  }

  Future<void> _agregar() async {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.single.path == null) return;
    final origen = r.files.single.path!;
    final nombre = TextEditingController(text: r.files.single.name);
    String tipo = kTiposDoc.first;
    DateTime? venc;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Datos del archivo'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nombre, decoration: deco('Nombre')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: tipo,
                isExpanded: true,
                decoration: deco('Tipo'),
                items: kTiposDoc.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setD(() => tipo = v ?? tipo),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                icon: const Icon(Icons.event),
                label: Text(venc == null ? 'Vencimiento (opcional)' : 'Vence: ${fmtFecha(venc!.toIso8601String())}'),
                onPressed: () async {
                  final f = await elegirFecha(c, venc);
                  if (f != null) setD(() => venc = f);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final ruta = await guardarArchivo(origen, 'documentos');
    await Db.save('documentos', {
      'consorcio_id': widget.consorcioId,
      'tipo': tipo,
      'nombre': nombre.text.trim().isEmpty ? 'Sin nombre' : nombre.text.trim(),
      'ruta': ruta,
      'vencimiento': venc?.toIso8601String(),
    });
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: BotonGrande(
            icono: Icons.attach_file, texto: 'AGREGAR ARCHIVO', color: kNaranja.withAlpha(255), onPressed: _agregar),
      ),
      Expanded(
        child: _d.isEmpty
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Guardá acá el reglamento, actas, seguros y matrículas para consultarlos sin internet.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 18))))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: _d.length,
                itemBuilder: (c, i) {
                  final d = _d[i];
                  return Card(
                    child: ListTile(
                      minVerticalPadding: 12,
                      leading: const Icon(Icons.description, size: 36, color: kAzul),
                      title: Text(d['nombre'].toString(),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${d['tipo']}${d['vencimiento'] != null ? '\nVence: ${fmtFecha(d['vencimiento'])}' : ''}'),
                      onTap: () async {
                        final r = await OpenFilex.open(d['ruta'].toString());
                        if (r.type != ResultType.done && context.mounted) {
                          aviso(context, 'No hay una app para abrir este archivo.');
                        }
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: kRojo),
                        onPressed: () async {
                          if (!await confirmar(context, 'Se elimina solo este archivo.')) return;
                          await Db.delete('documentos', d['id'] as int);
                          await _cargar();
                        },
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
