import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/currency_formatter.dart';
import 'pos_providers.dart';
import 'widgets/cart_panel.dart';
import 'widgets/product_search_panel.dart';

class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final cart = ref.watch(posCartProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isWide
            ? const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ProductSearchPanel()),
                  SizedBox(width: 16),
                  SizedBox(width: 420, child: CartPanel()),
                ],
              )
            : const ProductSearchPanel(),
      ),
      bottomNavigationBar: isWide
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => _showCartSheet(context),
                  icon: const Icon(Icons.shopping_cart),
                  label: Text(
                    '${cart.totalItems} items · ${CurrencyFormatter.cop(cart.total)}',
                  ),
                ),
              ),
            ),
    );
  }

  void _showCartSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black87,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: const Color(0xFA131310),
            child: const FractionallySizedBox(
              heightFactor: 0.9,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CartPanel(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
