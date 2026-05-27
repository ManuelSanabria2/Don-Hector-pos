import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/producto.dart';
import 'inventario_providers.dart';

class InventarioScreen extends ConsumerWidget {
  const InventarioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productos = ref.watch(inventarioProductosProvider);
    final categorias = ref.watch(inventarioCategoriasProvider);
    final selectedCategory = ref.watch(inventarioCategoriaProvider);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Inventario',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: AppColors.blanco,
                ),
          ),
          const SizedBox(height: 16),
          SearchBar(
            leading: const Icon(Icons.search),
            hintText: 'Buscar producto',
            onChanged: (value) {
              ref.read(inventarioBusquedaProvider.notifier).state = value;
            },
          ),
          const SizedBox(height: 12),
          categorias.when(
            loading: () => const SizedBox(
              height: 40,
              child: Center(child: LinearProgressIndicator()),
            ),
            error: (error, stackTrace) => Text('Error categorias: $error'),
            data: (items) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('Todas'),
                      selected: selectedCategory == null,
                      onSelected: (_) {
                        ref.read(inventarioCategoriaProvider.notifier).state =
                            null;
                      },
                    ),
                  ),
                  for (final categoria in items)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(categoria.nombre),
                        selected: selectedCategory == categoria.id,
                        onSelected: (_) {
                          ref.read(inventarioCategoriaProvider.notifier).state =
                              categoria.id;
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          productos.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Text('Error productos: $error'),
            data: (items) {
              if (items.isEmpty) {
                return const _EmptyInventory();
              }

              return Column(
                children: [
                  for (final producto in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ProductoTile(producto: producto),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.productoForm),
        icon: const Icon(Icons.add),
        label: const Text('Producto'),
      ),
    );
  }
}

class _ProductoTile extends StatelessWidget {
  const _ProductoTile({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        onTap: () => context.push(AppRoutes.productoForm, extra: producto),
        title: Row(
          children: [
            Expanded(child: Text(producto.nombre)),
            if (producto.stockBajo)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.error,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Stock bajo',
                  style: TextStyle(
                    color: colors.onError,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${CurrencyFormatter.cop(producto.precioPublico)}  ·  Stock ${producto.stockActual}/${producto.stockMinimo}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  const _EmptyInventory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          'No hay productos para mostrar',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
