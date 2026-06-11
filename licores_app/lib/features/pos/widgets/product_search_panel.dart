import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/producto.dart';
import '../../../data/repositories/inventario_repository.dart';
import '../pos_asistente_provider.dart';
import '../pos_providers.dart';
import 'assistant_aura_animation.dart';

class ProductSearchPanel extends ConsumerWidget {
  const ProductSearchPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productos = ref.watch(posProductosProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VENTA',
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
            ref.read(posBusquedaProvider.notifier).state = value;
          },
          trailing: [
            IconButton(
              tooltip: 'Escanear codigo',
              onPressed: () => _scanBarcode(context, ref),
              icon: const Icon(Icons.qr_code_scanner),
            ),
            const AsistenteVozButton(),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: productos.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) {
              debugPrint('Error loading POS products: $error');
              return const Center(child: Text('No se pudieron cargar los productos'));
            },
            data: (items) {
              if (items.isEmpty) {
                return const Center(child: Text('No hay productos'));
              }

              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return ProductTile(producto: items[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _scanBarcode(BuildContext context, WidgetRef ref) async {
    final codigo = await context.push<String>(AppRoutes.barcodeScanner);
    if (codigo == null || codigo.isEmpty) return;

    try {
      final producto = await ref
          .read(inventarioRepositoryProvider)
          .getProductoPorBarcode(codigo);

      if (producto == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Producto no encontrado')));
        return;
      }

      ref.read(posCartProvider.notifier).addProduct(producto);
    } catch (error) {
      debugPrint('Error scanning barcode: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(
        content: Text('Error al procesar el codigo de barras.'),
      ));
    }
  }
}

class ProductTile extends ConsumerWidget {
  const ProductTile({super.key, required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disabled = producto.stockActual <= 0;

    return Card(
      child: ListTile(
        enabled: !disabled,
        onTap: disabled
            ? null
            : () => ref.read(posCartProvider.notifier).addProduct(
                  producto,
                  cantidad: 1,
                ),
        title: Text(producto.nombre),
        subtitle: Text(
          '${CurrencyFormatter.cop(producto.precioPublico)} · Stock ${producto.stockActual}',
        ),
        trailing: Icon(disabled ? Icons.block : Icons.add_shopping_cart),
      ),
    );
  }
}

class AsistenteVozButton extends ConsumerWidget {
  const AsistenteVozButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(posAsistenteProvider);

    return IconButton(
      tooltip: 'Asistente de voz',
      onPressed: () {
        showAssistantDialog(context);
      },
      icon: Icon(
        Icons.mic,
        color: state.isListening ? Colors.red : AppColors.blanco,
      ),
    );
  }
}
