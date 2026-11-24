import 'package:flutter/material.dart';
import '../db.dart';
import '../expensas.dart';
import '../widgets.dart';
import 'consorcios.dart';

// =====================================================================
// Propietarios: lista de todas las unidades con su propietario/inquilino.
// Tocá una para cargar o editar nombre, teléfono, coeficiente y saldo.
// =====================================================================
class PropietariosScreen extends StatelessWidget {
  const PropietariosScreen({super.key});

  Future<List<Map<String, dynamic>>> _cargar() async {
    final unidades = await Db.all('unidades', orderBy: 'consorcio_id, piso, numero');
    final cons = await Db.all('consorcios');
    final nombres = {for (final c in cons) c['id'] as int: c['nombre'].toString()};
    final res = <Map<String, dynamic>>[];
    for (final u in unidades) {
      final m = Map<String, dynamic>.from(u);
      m['consorcio_nombre'] = nombres[u['consorcio_id']] ?? '(consorcio eliminado)';
      res.add(m);
    }
    res.sort((a, b) => a['consorcio_nombre'].toString().toLowerCase().compareTo(b['consorcio_nombre'].toString().toLowerCase()));
    return res;
  }

  Future<void> _nuevo(BuildContext context) async {
    int? elegido;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿En qué consorcio?'),
        content: ConsorcioDropdown(valor: null, onChanged: (m) => elegido = m?['id'] as int?),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Seguir')),
        ],
      ),
    );
    if (ok != true || elegido == null || !context.mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => UnidadForm(consorcioId: elegido!)));
  }

  @override
  Widget build(BuildContext context) {
    return ListaModulo(
      titulo: 'Propietarios',
      vacio: 'Todavía no hay unidades.\nPrimero cargá un consorcio y generá sus unidades en "Consorcios y unidades", o tocá NUEVO para agregar una unidad con su propietario.',
      cargar: _cargar,
      buscable: (e) => '${e['propietario']} ${e['consorcio_nombre']} ${e['piso']} ${e['numero']} ${e['telefono']}',
      onNuevo: () => _nuevo(context),
      item: (c, u, recargar) {
        final sin = (u['propietario'] ?? '').toString().trim().isEmpty;
        return Card(
          child: ListTile(
            minVerticalPadding: 12,
            leading: CircleAvatar(
              radius: 26,
              backgroundColor: sin ? kAmbar : kAzul,
              child: Icon(sin ? Icons.person_add : Icons.person, color: Colors.white),
            ),
            title: Text(sin ? 'Sin propietario - tocá para cargar' : u['propietario'].toString(),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: sin ? kAmbar : Colors.black)),
            subtitle: Text(
                '${u['consorcio_nombre']}\nPiso ${u['piso']} · Unidad ${u['numero']}${(u['telefono'] ?? '').toString().isEmpty ? '' : ' · Tel ${u['telefono']}'}'),
            isThreeLine: true,
            trailing: EstadoDeuda(u['saldo'] as num?),
            onTap: () async {
              await Navigator.push(
                  c,
                  MaterialPageRoute(
                      builder: (_) => UnidadForm(consorcioId: u['consorcio_id'] as int, existente: u)));
              await recargar();
            },
          ),
        );
      },
    );
  }
}
