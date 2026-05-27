import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../shared/widgets/app_shell_bar.dart';
import '../contabilidad/contabilidad_providers.dart';
import '../contabilidad/contabilidad_screen.dart';
import '../gastos/gastos_screen.dart';
import '../inventario/inventario_providers.dart';
import '../inventario/inventario_screen.dart';
import '../mayoristas/mayoristas_screen.dart';
import '../pos/pos_screen.dart';

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
      body: Row(
        children: [
          if (isDesktop)
            NavigationRail(
              selectedIndex: selectedIndex,
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
                  label: Text('POS'),
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
              unselectedItemColor: colors.onSurface.withOpacity(0.6),
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
                  label: 'POS',
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
    final stockBajo = ref.watch(stockBajoProvider);
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
                color: colors.primary.withOpacity(0.1),
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

              return Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.primary),
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
                                color: Colors.white.withOpacity(0.8),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.primary.withOpacity(0.1),
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
              );
            },
          ),
          const SizedBox(height: 24),

          stockBajo.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, stack) => Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error en alertas de stock: $error'),
              ),
            ),
            data: (productos) {
              final alertsToShow = productos.take(3).toList();

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: colors.error, size: 28),
                          const SizedBox(width: 8),
                          Text(
                            'Alertas de Stock Bajo',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const Spacer(),
                          if (productos.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                ref.read(homeTabIndexProvider.notifier).state = 1;
                              },
                              child: const Text('Ver todos'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (productos.isEmpty)
                        Text(
                          '🎉 Todo al día. Ningún producto con stock bajo.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        )
                      else ...[
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: alertsToShow.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final p = alertsToShow[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                p.nombre,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Stock actual: ${p.stockActual} / Mínimo: ${p.stockMinimo}',
                                style: TextStyle(color: colors.onSurfaceVariant),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colors.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Agotándose',
                                  style: TextStyle(
                                    color: colors.error,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          InkWell(
            onTap: () {
              ref.read(homeTabIndexProvider.notifier).state = 2;
            },
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.primary),
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
                          'Nueva Venta (POS)',
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
            color: Colors.white.withOpacity(0.7),
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
