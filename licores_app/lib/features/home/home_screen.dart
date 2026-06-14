import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_strings.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../shared/widgets/app_shell_bar.dart';
import '../contabilidad/contabilidad_providers.dart';
import '../contabilidad/contabilidad_screen.dart';
import '../gastos/gastos_screen.dart';
import '../inventario/inventario_screen.dart';
import '../mayoristas/mayoristas_screen.dart';
import '../pos/pos_screen.dart';
import '../pos/widgets/assistant_aura_animation.dart';

final homeTabIndexProvider = StateProvider<int>((ref) => 0);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _screens = [
    _DashboardView(),
    InventarioScreen(),
    PosScreen(),
    MayoristasScreen(),
    GastosScreen(),
    ContabilidadScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(homeTabIndexProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppShellBar(
        title: AppStrings.businessName,
      ),
      floatingActionButton: selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () => showAssistantDialog(context),
              backgroundColor: colors.primary,
              child: const Icon(Icons.graphic_eq, color: Colors.white),
            )
          : null,
      body: Row(
        children: [
          if (isDesktop)
            NavigationRail(
              selectedIndex: selectedIndex,
              useIndicator: false,
              indicatorColor: Colors.transparent,
              onDestinationSelected: (index) {
                ref.read(homeTabIndexProvider.notifier).state = index;
              },
              labelType: NavigationRailLabelType.all,
              selectedIconTheme: IconThemeData(color: colors.primary),
              selectedLabelTextStyle: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.bold,
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('Inicio'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: Text('Inventario'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.point_of_sale_outlined),
                  selectedIcon: Icon(Icons.point_of_sale),
                  label: Text('VENTA'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.storefront_outlined),
                  selectedIcon: Icon(Icons.storefront),
                  label: Text('Mayoristas'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: Text('Gastos'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: Text('Contabilidad'),
                ),
              ],
            ),
          Expanded(child: _screens[selectedIndex]),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : BottomNavigationBar(
              currentIndex: selectedIndex,
              onTap: (index) {
                ref.read(homeTabIndexProvider.notifier).state = index;
              },
              type: BottomNavigationBarType.fixed,
              selectedItemColor: colors.primary,
              unselectedItemColor: colors.onSurface.withOpacity(0.85),
              showUnselectedLabels: true,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined),
                  activeIcon: Icon(Icons.dashboard),
                  label: 'Inicio',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.inventory_2_outlined),
                  activeIcon: Icon(Icons.inventory_2),
                  label: 'Inventario',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.point_of_sale_outlined),
                  activeIcon: Icon(Icons.point_of_sale),
                  label: 'VENTA',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.storefront_outlined),
                  activeIcon: Icon(Icons.storefront),
                  label: 'Mayoristas',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.receipt_long_outlined),
                  activeIcon: Icon(Icons.receipt_long),
                  label: 'Gastos',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.bar_chart_outlined),
                  activeIcon: Icon(Icons.bar_chart),
                  label: 'Contabilidad',
                ),
              ],
            ),
    );
  }
}

class _DashboardView extends ConsumerWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumenHoy = ref.watch(resumenHoyProvider);
    final colors = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(resumenHoyProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¡Hola, Don Héctor!',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Resumen rápido del negocio para hoy',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                color: colors.primary.withOpacity(0.25),
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.person, color: colors.primary),
              ),
            ],
          ),
          const SizedBox(height: 24),

          resumenHoy.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, stack) => Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error al cargar ventas: $error'),
              ),
            ),
            data: (resumen) {
              final total = (resumen['total_ventas'] as num?)?.toDouble() ?? 0.0;
              final numVentas = resumen['num_ventas'] as int? ?? 0;
              final publico = (resumen['ventas_publico'] as num?)?.toDouble() ?? 0.0;
              final mayorista = (resumen['ventas_mayorista'] as num?)?.toDouble() ?? 0.0;

              return ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFA131310), // 98% opacidad oscura
                      border: Border.all(color: const Color(0xFF262626)),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.monetization_on, color: Colors.white, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          'VENTAS DE HOY',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.primary.withOpacity(0.25),
                            border: Border.all(color: colors.primary),
                          ),
                          child: Text(
                            '$numVentas ventas',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      formatCOP(total),
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _subMetrica(context, 'Al Público', formatCOP(publico)),
                        _subMetrica(context, 'Mayoristas', formatCOP(mayorista)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
            },
          ),
          const SizedBox(height: 24),

          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    ref.read(homeTabIndexProvider.notifier).state = 2;
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: const Color(0xFA131310), // 98% opacidad oscura
                      border: Border.all(color: const Color(0xFF262626)),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: colors.primary,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(
                      Icons.point_of_sale,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nueva Venta',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.primary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Registra ventas rápidas desde el mostrador',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, color: colors.primary, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
        ],
      ),
    );
  }

  Widget _subMetrica(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.blancoD,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
