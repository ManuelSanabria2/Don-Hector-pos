import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/app_routes.dart';
import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'data/models/cliente_mayorista.dart';
import 'data/models/gasto.dart';
import 'data/models/producto.dart';
import 'features/gastos/gasto_form_screen.dart';
import 'features/home/home_screen.dart';
import 'features/inventario/barcode_scanner_screen.dart';
import 'features/inventario/producto_form_screen.dart';
import 'features/mayoristas/cliente_detail_screen.dart';
import 'features/mayoristas/cliente_form_screen.dart';
import 'features/splash/video_splash_screen.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await initializeDateFormatting('es', null);

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(const ProviderScope(child: LicoresApp()));
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const VideoSplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.productoForm,
        name: 'productoForm',
        builder: (context, state) {
          return ProductoFormScreen(producto: state.extra as Producto?);
        },
      ),
      GoRoute(
        path: AppRoutes.barcodeScanner,
        name: 'barcodeScanner',
        builder: (context, state) => const BarcodeScannerScreen(),
      ),
      GoRoute(
        path: AppRoutes.clienteDetail,
        name: 'clienteDetail',
        builder: (context, state) {
          return ClienteDetailScreen(cliente: state.extra as ClienteMayorista);
        },
      ),
      GoRoute(
        path: AppRoutes.clienteForm,
        name: 'clienteForm',
        builder: (context, state) {
          return ClienteFormScreen(cliente: state.extra as ClienteMayorista?);
        },
      ),
      GoRoute(
        path: AppRoutes.gastoForm,
        name: 'gastoForm',
        builder: (context, state) {
          return GastoFormScreen(gasto: state.extra as Gasto?);
        },
      ),
    ],
  );
});

class LicoresApp extends ConsumerWidget {
  const LicoresApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
