import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/gastos_repository.dart';
import 'gastos_providers.dart';

class GastosScreen extends ConsumerWidget {
  const GastosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gastosAsync = ref.watch(gastosDelMesProvider);
    final categoriasAsync = ref.watch(categoriasGastoProvider);
    final selectedCat = ref.watch(selectedCategoriaGastoProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gastos del Mes',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w400,
                color: AppColors.blanco,
              ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: categoriasAsync.when(
            data: (categorias) {
              return SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          'Todos',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppColors.blancoD,
                              ),
                        ),
                        selected: selectedCat == null,
                        onSelected: (_) => ref.read(selectedCategoriaGastoProvider.notifier).state = null,
                      ),
                    ),
                    ...categorias.map((c) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            c.nombre,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.blancoD,
                                ),
                          ),
                          selected: selectedCat == c.id,
                          onSelected: (_) => ref.read(selectedCategoriaGastoProvider.notifier).state = c.id,
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
            loading: () => const SizedBox(height: 50, child: Center(child: CircularProgressIndicator())),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
      ),
      body: gastosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (gastos) {
          if (gastos.isEmpty) {
            return const Center(child: Text('No hay gastos registrados.'));
          }

          final total = gastos.fold<num>(0, (sum, g) => sum + g.monto);

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: gastos.length,
                  itemBuilder: (context, index) {
                    final gasto = gastos[index];
                    return ListTile(
                      title: Text(gasto.descripcion),
                      subtitle: Text(DateFormat('yyyy-MM-dd').format(gasto.fecha)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('\$ ${NumberFormat('#,##0.00').format(gasto.monto)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final conf = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Eliminar Gasto'),
                                  content: const Text('¿Está seguro?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
                                  ],
                                ),
                              );
                              if (conf == true) {
                                await ref.read(gastosRepositoryProvider).deleteGasto(gasto.id);
                                ref.invalidate(gastosDelMesProvider);
                              }
                            },
                          )
                        ],
                      ),
                      onTap: () {
                        context.push(AppRoutes.gastoForm, extra: gasto);
                      },
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total:', style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        '\$ ${NumberFormat('#,##0.00').format(total)}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              )
            ],
          );
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60), // Eleva el botón para que quede por encima de la barra de total
        child: FloatingActionButton(
          onPressed: () => context.push(AppRoutes.gastoForm),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
