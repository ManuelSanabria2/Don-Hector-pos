import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import 'mayoristas_providers.dart';

class MayoristasScreen extends ConsumerStatefulWidget {
  const MayoristasScreen({super.key});

  @override
  ConsumerState<MayoristasScreen> createState() => _MayoristasScreenState();
}

class _MayoristasScreenState extends ConsumerState<MayoristasScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, NIT o teléfono...',
              prefixIcon: const Icon(Icons.search, color: AppColors.blancoD),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.blancoD),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          clientes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Text('Error clientes: $error'),
            data: (items) {
              final query = _searchQuery.trim().toLowerCase();
              final filteredItems = query.isEmpty
                  ? items
                  : items.where((item) {
                      final nombre = item.cliente.nombre.toLowerCase();
                      final nit = item.cliente.nit?.toLowerCase() ?? '';
                      final telefono = item.cliente.telefono?.toLowerCase() ?? '';
                      return nombre.contains(query) ||
                          nit.contains(query) ||
                          telefono.contains(query);
                    }).toList();

              if (filteredItems.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      query.isEmpty
                          ? 'No hay clientes mayoristas'
                          : 'No se encontraron clientes para "$_searchQuery"',
                      style: const TextStyle(color: AppColors.blancoD),
                    ),
                  ),
                );
              }

              int porNombre(ClienteConCuenta a, ClienteConCuenta b) =>
                  a.cliente.nombre.toLowerCase().compareTo(
                        b.cliente.nombre.toLowerCase(),
                      );

              final conDeuda = filteredItems
                  .where((item) => item.tieneCobroPendiente)
                  .toList()
                ..sort(porNombre);
              final sinDeuda = filteredItems
                  .where((item) => !item.tieneCobroPendiente)
                  .toList()
                ..sort(porNombre);

              return Column(
                children: [
                  for (final item in conDeuda)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClienteCard(item: item),
                    ),
                  if (conDeuda.isNotEmpty && sinDeuda.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white24)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'Sin deuda pendiente',
                              style: TextStyle(
                                color: AppColors.blancoD,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.white24)),
                        ],
                      ),
                    ),
                  for (final item in sinDeuda)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClienteCard(item: item),
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

class ClienteCard extends StatelessWidget {
  const ClienteCard({super.key, required this.item});

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
        // El nombre ocupa el ancho completo: los de los clientes reales
        // llegan a más de 30 caracteres y antes competían con el chip.
        title: Text(
          item.cliente.nombre,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontWeight: hasDebt ? FontWeight.bold : null,
          ),
        ),
        subtitle: hasDebt
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                // Wrap y no Row: en pantallas angostas el chip baja de
                // línea en vez de apretar el monto.
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Debe ${CurrencyFormatter.cop(item.deudaPendiente)}',
                      style: TextStyle(
                        color: subColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
              )
            : Text(
                'Sin deuda pendiente',
                style: TextStyle(color: subColor),
              ),
        isThreeLine: hasDebt,
        trailing: Icon(
          Icons.chevron_right,
          color: textColor,
        ),
      ),
    );
  }
}
