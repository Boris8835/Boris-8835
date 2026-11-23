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

  static const String _tablaLiquidaciones = '''CREATE TABLE liquidaciones(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    consorcio_id INTEGER NOT NULL, periodo TEXT NOT NULL,
    total REAL, detalle TEXT, aplicada TEXT)''';

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'consorcio_field.db'),
      version: 2,
      onUpgrade: (db, viejo, nuevo) async {
        if (viejo < 2) {
          await db.execute(_tablaLiquidaciones);
        }
      },
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE consorcios(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nombre TEXT NOT NULL, cuit TEXT, direccion TEXT,
          admin_nombre TEXT, admin_tel TEXT, admin_email TEXT, notas TEXT,
          creado TEXT)''');
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
