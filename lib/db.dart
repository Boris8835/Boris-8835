import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Base de datos local (SQLite). Cada módulo tiene SUS PROPIAS tablas y
/// no hay claves foráneas con borrado en cascada entre módulos:
/// borrar una inspección nunca toca gastos, reclamos ni órdenes.
/// Los registros guardan una copia del nombre del consorcio, así sobreviven
/// aunque el consorcio se elimine.
class Db {
  static Database? _db;

  static const String _tablaPagos = '''CREATE TABLE pagos(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    unidad_id INTEGER NOT NULL, consorcio_id INTEGER,
    fecha TEXT, monto REAL, medio TEXT, concepto TEXT, expensa_id INTEGER)''';

  static const String _tablaExpensas = '''CREATE TABLE expensas(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    consorcio_id INTEGER NOT NULL, consorcio_nombre TEXT,
    unidad_id INTEGER, unidad_txt TEXT, propietario TEXT,
    periodo TEXT NOT NULL, coeficiente REAL,
    ordinarias REAL, extraordinarias REAL, total REAL,
    estado TEXT, fecha_emision TEXT, fecha_pago TEXT, medio_pago TEXT,
    tipo TEXT DEFAULT 'Expensa', concepto TEXT, pagado REAL DEFAULT 0)''';

  static const String _tablaIngresos = '''CREATE TABLE IF NOT EXISTS ingresos(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    consorcio_id INTEGER, consorcio_nombre TEXT, fecha TEXT,
    concepto TEXT, tipo TEXT, monto REAL, notas TEXT)''';

  static Future<void> _intentar(Database db, String sql) async {
    try {
      await db.execute(sql);
    } catch (_) {
      // la columna ya existe: no pasa nada
    }
  }

  /// v5: pagos parciales, saldos anteriores, firma e ingresos. No pierde datos.
  static Future<void> _migrar5(Database db) async {
    await _intentar(db, "ALTER TABLE expensas ADD COLUMN tipo TEXT DEFAULT 'Expensa'");
    await _intentar(db, 'ALTER TABLE expensas ADD COLUMN concepto TEXT');
    await _intentar(db, 'ALTER TABLE expensas ADD COLUMN pagado REAL DEFAULT 0');
    await _intentar(db, 'ALTER TABLE pagos ADD COLUMN expensa_id INTEGER');
    await _intentar(db, 'ALTER TABLE consorcios ADD COLUMN firma TEXT');
    await db.execute(_tablaIngresos);
    await db.execute("UPDATE expensas SET tipo = 'Expensa' WHERE tipo IS NULL");
    await db.execute("UPDATE expensas SET pagado = total WHERE estado = 'Pagado'");
    await db.execute('UPDATE expensas SET pagado = 0 WHERE pagado IS NULL');

    // El saldo que no tenía detalle (cargado a mano o con la versión anterior)
    // pasa a ser un "Saldo anterior" por unidad, para poder cobrarlo en partes.
    final ahora = DateTime.now();
    final periodo = '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';
    final unidades = await db.query('unidades');
    for (final u in unidades) {
      final saldo = (u['saldo'] as num?)?.toDouble() ?? 0;
      final filas = await db.query('expensas', where: 'unidad_id = ?', whereArgs: [u['id']]);
      double enFilas = 0;
      for (final f in filas) {
        final resta = ((f['total'] as num?)?.toDouble() ?? 0) - ((f['pagado'] as num?)?.toDouble() ?? 0);
        if (resta > 0) enFilas += resta;
      }
      final resto = saldo - enFilas;
      if (resto > 0.005) {
        final cons = await db.query('consorcios', where: 'id = ?', whereArgs: [u['consorcio_id']]);
        await db.insert('expensas', {
          'consorcio_id': u['consorcio_id'],
          'consorcio_nombre': cons.isEmpty ? '' : cons.first['nombre'],
          'unidad_id': u['id'],
          'unidad_txt': 'Piso ${u['piso']} - ${u['numero']}',
          'propietario': u['propietario'] ?? '',
          'periodo': periodo,
          'coeficiente': u['coeficiente'],
          'ordinarias': 0.0,
          'extraordinarias': 0.0,
          'total': double.parse(resto.toStringAsFixed(2)),
          'estado': 'Debe',
          'fecha_emision': ahora.toIso8601String(),
          'tipo': 'Saldo anterior',
          'concepto': 'Saldo anterior',
          'pagado': 0.0,
        });
      }
    }
  }

  static const String _tablaLiquidaciones = '''CREATE TABLE liquidaciones(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    consorcio_id INTEGER NOT NULL, periodo TEXT NOT NULL,
    total REAL, detalle TEXT, aplicada TEXT)''';

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'consorcio_field.db'),
      version: 5,
      onUpgrade: (db, viejo, nuevo) async {
        if (viejo < 2) {
          await db.execute(_tablaLiquidaciones);
        }
        if (viejo < 3) {
          await db.execute(_tablaExpensas);
        }
        if (viejo < 4) {
          await db.execute(_tablaPagos);
        }
        if (viejo < 5) {
          await _migrar5(db);
        }
      },
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE consorcios(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nombre TEXT NOT NULL, cuit TEXT, direccion TEXT,
          admin_nombre TEXT, admin_tel TEXT, admin_email TEXT, notas TEXT,
          creado TEXT, firma TEXT)''');
        await db.execute('''CREATE TABLE unidades(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          consorcio_id INTEGER NOT NULL, piso TEXT, numero TEXT,
          propietario TEXT, telefono TEXT, coeficiente REAL DEFAULT 0,
          saldo REAL DEFAULT 0)''');
        await db.execute('''CREATE TABLE documentos(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          consorcio_id INTEGER NOT NULL, tipo TEXT, nombre TEXT,
          ruta TEXT, vencimiento TEXT)''');
        await db.execute('''CREATE TABLE inspecciones(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          consorcio_id INTEGER, consorcio_nombre TEXT, fecha TEXT,
          lat REAL, lng REAL, notas TEXT, items TEXT)''');
        await db.execute('''CREATE TABLE ordenes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          consorcio_id INTEGER, consorcio_nombre TEXT, descripcion TEXT,
          fotos TEXT, proveedor TEXT, fecha_limite TEXT,
          estado TEXT, factura TEXT, creado TEXT)''');
        await db.execute('''CREATE TABLE gastos(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          consorcio_id INTEGER, consorcio_nombre TEXT, fecha TEXT,
          concepto TEXT, proveedor TEXT, cuit TEXT, monto REAL,
          tipo TEXT, forma_pago TEXT, cuotas INTEGER, pagado REAL,
          foto TEXT, texto_ocr TEXT)''');
        await db.execute('''CREATE TABLE reclamos(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          consorcio_id INTEGER, consorcio_nombre TEXT, unidad TEXT,
          propietario TEXT, telefono TEXT, descripcion TEXT,
          fotos TEXT, estado TEXT, creado TEXT)''');
        await db.execute(_tablaLiquidaciones);
        await db.execute(_tablaExpensas);
        await db.execute(_tablaPagos);
        await db.execute(_tablaIngresos);
        await db.execute('''CREATE TABLE reclamo_historial(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          reclamo_id INTEGER NOT NULL, fecha TEXT, texto TEXT, foto TEXT)''');
      },
    );
    return _db!;
  }

  static Future<List<Map<String, dynamic>>> all(String tabla,
      {String? where, List<Object?>? args, String orderBy = 'id DESC'}) async {
    final d = await _open();
    final r = await d.query(tabla, where: where, whereArgs: args, orderBy: orderBy);
    return r.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<Map<String, dynamic>?> one(String tabla, int id) async {
    final r = await all(tabla, where: 'id = ?', args: [id]);
    return r.isEmpty ? null : r.first;
  }

  /// Inserta (sin id) o actualiza (con id). Devuelve el id.
  static Future<int> save(String tabla, Map<String, dynamic> valores) async {
    final d = await _open();
    final id = valores['id'];
    final data = Map<String, Object?>.from(valores)..remove('id');
    if (id == null) {
      return d.insert(tabla, data);
    }
    await d.update(tabla, data, where: 'id = ?', whereArgs: [id]);
    return id as int;
  }

  static Future<void> delete(String tabla, int id) async {
    final d = await _open();
    await d.delete(tabla, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteWhere(String tabla, String where, List<Object?> args) async {
    final d = await _open();
    await d.delete(tabla, where: where, whereArgs: args);
  }
}

/// Copia un archivo (foto, video, PDF) a la carpeta privada de la app para que
/// no se pierda si el sistema limpia la caché.
Future<String> guardarArchivo(String origen, String carpeta) async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'media', carpeta));
  await dir.create(recursive: true);
  final destino =
      p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}${p.extension(origen)}');
  await File(origen).copy(destino);
  return destino;
}
