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

    final cardColor = hasDebt ? colors.primary : null;
    final textColor = hasDebt ? Colors.black : null;
    final subColor = hasDebt ? Colors.black87 : null;

    return Card(
      color: cardColor,
      child: ListTile(
        onTap: () => context.push(AppRoutes.clienteDetail, extra: item.cliente),
        leading: CircleAvatar(
          backgroundColor: hasDebt ? Colors.black : colors.primary,
          foregroundColor: hasDebt ? colors.primary : colors.onPrimary,
          child: Text(item.cliente.nombre.characters.first.toUpperCase()),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.cliente.nombre,
                style: TextStyle(
                  color: textColor,
                  fontWeight: hasDebt ? FontWeight.bold : null,
                ),
              ),
            ),
            if (hasDebt)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Cobro pendiente',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          hasDebt
              ? 'Debe ${CurrencyFormatter.cop(item.deudaPendiente)}'
              : 'Sin deuda pendiente',
          style: TextStyle(color: subColor),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: textColor,
        ),
      ),
    );
  }
}
