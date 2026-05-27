import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import 'mayoristas_providers.dart';

class MayoristasScreen extends ConsumerWidget {
  const MayoristasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientes = ref.watch(mayoristasClientesProvider);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Mayoristas',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: AppColors.blanco,
                ),
          ),
          const SizedBox(height: 16),
          clientes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Text('Error clientes: $error'),
            data: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No hay clientes mayoristas')),
                );
              }

              return Column(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ClienteCard(item: item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.clienteForm),
        icon: const Icon(Icons.person_add),
        label: const Text('Cliente'),
      ),
    );
  }
}

class _ClienteCard extends StatelessWidget {
  const _ClienteCard({required this.item});

  final ClienteConCuenta item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasDebt = item.tieneCobroPendiente;

    return Card(
      color: hasDebt ? Colors.amber.shade50 : null,
      child: ListTile(
        onTap: () => context.push(AppRoutes.clienteDetail, extra: item.cliente),
        leading: CircleAvatar(
          backgroundColor: hasDebt ? Colors.amber.shade700 : colors.primary,
          foregroundColor: hasDebt ? Colors.black : colors.onPrimary,
          child: Text(item.cliente.nombre.characters.first.toUpperCase()),
        ),
        title: Row(
          children: [
            Expanded(child: Text(item.cliente.nombre)),
            if (hasDebt)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Cobro pendiente',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        subtitle: Text(
          hasDebt
              ? 'Debe ${CurrencyFormatter.cop(item.deudaPendiente)}'
              : 'Sin deuda pendiente',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
