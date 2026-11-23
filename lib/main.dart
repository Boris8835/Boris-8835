import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/consorcios.dart';
import 'screens/consulta.dart';
import 'screens/gastos.dart';
import 'screens/inspecciones.dart';
import 'screens/liquidacion.dart';
import 'screens/ordenes.dart';
import 'screens/plantillas.dart';
import 'screens/reclamos.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_AR');
  runApp(const ConsorcioFieldApp());
}

class ConsorcioFieldApp extends StatelessWidget {
  const ConsorcioFieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    final esquema = ColorScheme.fromSeed(
      seedColor: kAzul,
      primary: kAzul,
      secondary: kNaranja,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Consorcio Field',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'AR'),
      supportedLocales: const [Locale('es', 'AR'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: esquema,
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: kAzul,
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
          iconTheme: IconThemeData(size: 28, color: Colors.white),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 17, color: Colors.black),
          bodyLarge: TextStyle(fontSize: 18, color: Colors.black),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      home: const Inicio(),
    );
  }
}

class _Modulo {
  final String titulo;
  final IconData icono;
  final Color color;
  final Widget Function() pantalla;
  const _Modulo(this.titulo, this.icono, this.color, this.pantalla);
}

class Inicio extends StatelessWidget {
  const Inicio({super.key});

  @override
  Widget build(BuildContext context) {
    final modulos = <_Modulo>[
      _Modulo('Consorcios y unidades', Icons.apartment, kAzul, () => const ConsorciosScreen()),
      _Modulo('Inspecciones', Icons.fact_check, const Color(0xFF1565C0), () => const InspeccionesScreen()),
      _Modulo('Órdenes de trabajo', Icons.build, const Color(0xFF6A1B9A), () => const OrdenesScreen()),
      _Modulo('Gastos', Icons.receipt_long, kVerde, () => const GastosScreen()),
      _Modulo('Liquidación de expensas', Icons.calculate, const Color(0xFF283593), () => const LiquidacionScreen()),
      _Modulo('Reclamos vecinales', Icons.record_voice_over, kRojo, () => const ReclamosScreen()),
      _Modulo('Consulta rápida', Icons.search, kAmbar, () => const ConsultaScreen()),
      _Modulo('Plantillas de mensajes', Icons.chat, const Color(0xFF00796B), () => const PlantillasScreen()),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.shield, color: kNaranja),
          SizedBox(width: 10),
          Text('Consorcio Field'),
        ]),
      ),
      body: SafeArea(
        child: GridView.count(
          padding: const EdgeInsets.all(14),
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.0,
          children: [
            for (final m in modulos)
              Material(
                color: m.color,
                borderRadius: BorderRadius.circular(18),
                elevation: 3,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => m.pantalla())),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(m.icono, size: 54, color: Colors.white),
                        const SizedBox(height: 10),
                        Text(m.titulo,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
