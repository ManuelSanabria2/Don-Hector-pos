import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';
import 'inventario_providers.dart';

class AlertasStockWidget extends ConsumerWidget {
  const AlertasStockWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockBajo = ref.watch(stockBajoProvider);
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.warning_amber, color: colors.error),
        title: const Text('Alertas de stock'),
        subtitle: stockBajo.maybeWhen(
          data: (items) =>
              Text('${items.length} productos por debajo del minimo'),
          orElse: () => const Text('Monitoreo en tiempo real'),
        ),
        children: [
          stockBajo.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (error, stackTrace) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No se pudieron cargar alertas: $error'),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hay productos con stock bajo'),
                );
              }

              return Column(
                children: [
                  for (final producto in items)
                    ListTile(
                      title: Text(producto.nombre),
                      subtitle: Text(
                        'Stock ${producto.stockActual} / minimo ${producto.stockMinimo}',
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          context.push(AppRoutes.productoForm, extra: producto);
                        },
                        child: const Text('Ajustar stock'),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
