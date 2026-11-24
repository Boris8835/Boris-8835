import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'widgets.dart';

// =====================================================================
// Compartir la app por WhatsApp: función reservada al desarrollador.
// Pide un código; solo el desarrollador lo conoce. (El código no se guarda
// en texto: solo su huella con sal y 60.000 repeticiones.)
// =====================================================================
const String kDesarrollador = 'Boris Javier Casanueva Muñoz';
const String kVersionApp = '1.3';
const String kLinkDescarga = 'https://github.com/Boris8835/Boris-8835/releases/latest';

const String _sal = 'c6c25a4e9f3884dc';
const String _huella = '361364e43aee5cf58a3c89b70d1eb4878931976e22a19c8143f3912d718ede68';
const int _repeticiones = 60000;

String _calcular(String pin) {
  List<int> h = utf8.encode('$_sal:$pin');
  for (var i = 0; i < _repeticiones; i++) {
    h = sha256.convert(h).bytes;
  }
  return h.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

int _fallos = 0;

Future<void> compartirApp(BuildContext context) async {
  if (_fallos >= 5) {
    aviso(context, 'Demasiados intentos. Cerrá y volvé a abrir la app para reintentar.');
    return;
  }
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Compartir la app'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
            'Función exclusiva del desarrollador\n$kDesarrollador.\n\nIngresá tu código para continuar.',
            style: TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        TextField(
          controller: c,
          obscureText: true,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(fontSize: 22, letterSpacing: 4),
          decoration: deco('Código del desarrollador', icono: Icons.lock),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Continuar')),
      ],
    ),
  );
  if (ok != true) return;
  if (_calcular(c.text.trim()) != _huella) {
    _fallos++;
    if (context.mounted) aviso(context, 'Código incorrecto. Solo el desarrollador puede compartir la app.');
    return;
  }
  _fallos = 0;
  await Share.share(
      '📲 *Consorcio Field* - App para administradores de consorcios (funciona sin internet).\n'
      'Desarrollada por $kDesarrollador.\n\n'
      'Descargala acá: $kLinkDescarga\n'
      '(Bajá el archivo app-arm64-v8a-release.apk. Al instalarlo, activá "Permitir desde esta fuente").',
      subject: 'Consorcio Field');
}

void mostrarAcercaDe(BuildContext context) {
  showDialog(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Consorcio Field'),
      content: Text('Versión $kVersionApp\n\nDesarrollada por\n$kDesarrollador\nTel. 385 5981413\n\nAdministración de consorcios en terreno, 100 % sin internet.',
          style: const TextStyle(fontSize: 17)),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cerrar'))],
    ),
  );
}
