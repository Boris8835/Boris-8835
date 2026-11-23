import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets.dart';

// =====================================================================
// MÓDULO 7: Plantillas de mensajes (copiar y pegar en WhatsApp / mail)
// Los datos entre {llaves} se completan en pantalla.
// =====================================================================
class _Plantilla {
  final String titulo;
  final String texto;
  const _Plantilla(this.titulo, this.texto);
}

const _plantillas = <_Plantilla>[
  _Plantilla('Recordatorio de expensas',
      'Hola {nombre}, te escribo de la administración de {consorcio}. Te recordamos que la expensa de {mes} (Unidad {unidad}) vence el {vencimiento}. Saldo actual: {monto}. Podés abonar por transferencia o en la administración. ¡Gracias!'),
  _Plantilla('Aviso de corte de agua',
      'Estimados vecinos de {consorcio}: el día {fecha} entre las {desde} y las {hasta} hs se cortará el suministro de agua por {motivo}. Disculpen las molestias. Administración.'),
  _Plantilla('Ascensor fuera de servicio',
      'Estimados vecinos de {consorcio}: informamos que el ascensor está fuera de servicio desde {fecha}. Ya se dio aviso a {proveedor} y estimamos la reparación para {estimado}. Disculpen las molestias. Administración.'),
  _Plantilla('Convocatoria a asamblea',
      'Estimados propietarios de {consorcio}: se los convoca a asamblea {tipo} el día {fecha} a las {hora} hs en {lugar}. Orden del día: {orden}. Su presencia es importante. Administración.'),
  _Plantilla('Respuesta a un reclamo',
      'Hola {nombre}, recibimos tu reclamo sobre "{asunto}" (Unidad {unidad}, {consorcio}). Ya lo estamos gestionando con {proveedor}. Te mantendremos al tanto. Saludos, {administrador}.'),
  _Plantilla('Aviso de fumigación',
      'Estimados vecinos de {consorcio}: el día {fecha} se realizará la fumigación / desinfección de las áreas comunes. Se pide mantener cerradas las puertas de los palieres entre las {desde} y las {hasta} hs. Administración.'),
  _Plantilla('Pedido de presupuesto a proveedor',
      'Buenas tardes {proveedor}, soy {administrador}, administrador de {consorcio} ({direccion}). Necesito un presupuesto para: {trabajo}. ¿Podrías pasar a verlo esta semana? Gracias.'),
  _Plantilla('Envío de acta de inspección',
      'Estimados miembros del consejo de {consorcio}: les adjunto el acta de la inspección realizada el {fecha}. Quedo a disposición para coordinar las acciones necesarias. Saludos, {administrador}.'),
];

class PlantillasScreen extends StatelessWidget {
  const PlantillasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plantillas de mensajes')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final p in _plantillas)
          Card(
            child: ListTile(
              minVerticalPadding: 16,
              leading: const Icon(Icons.chat, color: kAzul, size: 36),
              title: Text(p.titulo, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              trailing: const Icon(Icons.chevron_right, size: 30),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => _EditorPlantilla(plantilla: p))),
            ),
          ),
      ]),
    );
  }
}

class _EditorPlantilla extends StatefulWidget {
  final _Plantilla plantilla;
  const _EditorPlantilla({required this.plantilla});

  @override
  State<_EditorPlantilla> createState() => _EditorPlantillaState();
}

class _EditorPlantillaState extends State<_EditorPlantilla> {
  final Map<String, TextEditingController> _c = {};

  @override
  void initState() {
    super.initState();
    final re = RegExp(r'\{(\w+)\}');
    for (final m in re.allMatches(widget.plantilla.texto)) {
      final k = m.group(1)!;
      _c.putIfAbsent(k, () => TextEditingController()..addListener(() => setState(() {})));
    }
  }

  String get _resultado {
    return widget.plantilla.texto.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final v = _c[m.group(1)!]?.text.trim() ?? '';
      return v.isEmpty ? '[${m.group(1)}]' : v;
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.plantilla.titulo)),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        for (final e in _c.entries) campo(e.value, e.key[0].toUpperCase() + e.key.substring(1)),
        const SizedBox(height: 6),
        const Text('Vista previa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Card(
          color: const Color(0xFFE8F5E9),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(_resultado, style: const TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(height: 8),
        BotonGrande(
            icono: Icons.copy,
            texto: 'COPIAR MENSAJE',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _resultado));
              if (context.mounted) aviso(context, 'Copiado. Pegalo en WhatsApp o tu correo.');
            }),
        const SizedBox(height: 10),
        BotonGrande(
            icono: Icons.send,
            texto: 'ENVIAR (WhatsApp / correo)',
            color: kVerde,
            onPressed: () => Share.share(_resultado)),
        const SizedBox(height: 30),
      ]),
    );
  }
}
