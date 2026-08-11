import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/sound_effects.dart';
import '../../data/models/producto.dart';
import '../../data/models/categoria.dart';
import '../../data/models/venta_enums.dart';
import '../../data/repositories/inventario_repository.dart';
import '../../data/repositories/pos_repository.dart';
import '../compras/compras_providers.dart';
import '../inventario/inventario_providers.dart';
import '../contabilidad/contabilidad_providers.dart';
import '../contabilidad/fiados_providers.dart';
import '../mayoristas/mayoristas_providers.dart';
import 'pos_providers.dart';
import 'turbo_add_product_sheet.dart';

class PosTurboScreen extends ConsumerStatefulWidget {
  const PosTurboScreen({super.key});

  @override
  ConsumerState<PosTurboScreen> createState() => _PosTurboScreenState();
}

class _PosTurboScreenState extends ConsumerState<PosTurboScreen> {
  bool _submitting = false;
  bool _editMode = false;
  bool _uploadingImage = false;
  bool _soundMuted = false;
  List<Producto> _editList = [];

  InventarioRepository get _inventarioRepo =>
      ref.read(inventarioRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _initSound();
  }

  Future<void> _initSound() async {
    // Precarga el efecto y lee si el usuario dejó el sonido silenciado.
    await SoundEffects.preload();
    if (mounted) setState(() => _soundMuted = SoundEffects.isMuted);
  }

  void _toggleEditMode() {
    setState(() {
      if (_editMode) {
        _editMode = false;
        _editList = [];
        ref.invalidate(posTurboProductosProvider);
      } else {
        _editMode = true;
        _editList =
            List.of(ref.read(posTurboProductosProvider).value ?? <Producto>[]);
      }
    });
  }

  Future<void> _syncEditList() async {
    ref.invalidate(posTurboProductosProvider);
    final fresh = await ref.read(posTurboProductosProvider.future);
    if (mounted && _editMode) {
      setState(() => _editList = List.of(fresh));
    }
  }

  Future<void> _persistOrder() async {
    final ids = _editList.map((p) => p.id).toList();
    try {
      await _inventarioRepo.actualizarOrdenTurbo(ids);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el orden')),
      );
      await _syncEditList();
    }
  }

  Future<void> _removeFromTurbo(Producto product) async {
    setState(() => _editList.removeWhere((p) => p.id == product.id));
    try {
      await _inventarioRepo.setProductoTurbo(product.id, false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.nombre} quitado del menú turbo')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo quitar el producto')),
      );
      await _syncEditList();
    }
  }

  Future<void> _pickImageFor(Producto product) async {
    if (_uploadingImage) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      await _inventarioRepo.subirImagenProducto(
        productoId: product.id,
        bytes: bytes,
      );
      await _syncEditList();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo subir la imagen')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _openAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFA131310),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (_) => const TurboAddProductSheet(),
    );
    if (mounted) await _syncEditList();
  }

  Future<void> _submitVenta(
    num total,
    MetodoPago metodo, {
    String? deudorNombre,
  }) async {
    final cartState = ref.read(posCartProvider);
    if (cartState.items.isEmpty) return;

    final esFiado = metodo == MetodoPago.credito;
    final nombre = deudorNombre?.trim();
    if (esFiado && (nombre == null || nombre.isEmpty)) return;

    setState(() => _submitting = true);

    try {
      final ventaId = await ref.read(posRepositoryProvider).registrarVenta(
            tipo: TipoVenta.publico,
            metodoPago: metodo,
            items: cartState.items,
            descuento: cartState.descuento,
            deudorNombre: esFiado ? nombre : null,
          );

      // Invalidate providers
      ref.read(posCartProvider.notifier).clear();
      ref.invalidate(posTurboProductosProvider);
      ref.invalidate(inventarioProductosProvider);
      ref.invalidate(stockBajoProvider);
      ref.invalidate(resumenHoyProvider);
      ref.invalidate(metricasMesProvider);
      ref.invalidate(ventasPorRangoProvider);
      ref.invalidate(mayoristasClientesProvider);
      ref.invalidate(estadoCuentaFiadosProvider);
      ref.invalidate(totalFiadosPendienteProvider);
      ref.invalidate(resumenPatrimonioProvider);

      if (!mounted) return;
      
      setState(() => _submitting = false);
      
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _SuccessCheckoutDialog(
          total: total,
          metodo: metodo,
          deudorNombre: esFiado ? nombre : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al registrar venta: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final productsAsync = ref.watch(posTurboProductosProvider);
    final cartState = ref.watch(posCartProvider);
    final categoriesAsync = ref.watch(inventarioCategoriasProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A08),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Icon(Icons.bolt, color: AppColors.ambar, size: 28),
        actions: [
          IconButton(
            icon: Icon(
              _editMode ? Icons.check_circle : Icons.edit,
              size: 26,
              color: _editMode ? Colors.greenAccent : null,
            ),
            tooltip: _editMode ? 'Terminar edición' : 'Editar menú',
            onPressed: _toggleEditMode,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 28),
            onPressed: () {
              ref.read(posCartProvider.notifier).clear();
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(context, isDesktop, productsAsync, cartState, categoriesAsync),
          if (_uploadingImage)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context, isDesktop, cartState),
    );
  }

  /// Interruptor para activar/silenciar el sonido de agregar producto.
  /// Solo visible en el modo de edición del menú turbo.
  Widget _buildSoundToggle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: !_soundMuted,
          activeThumbColor: AppColors.ambar,
          secondary: Icon(
            _soundMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            color: _soundMuted ? Colors.white38 : AppColors.ambar,
          ),
          title: const Text(
            'Sonido al agregar producto',
            style: TextStyle(color: AppColors.blancoD, fontSize: 14),
          ),
          subtitle: Text(
            _soundMuted ? 'Silenciado' : 'Activado',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          onChanged: (enabled) async {
            await SoundEffects.setMuted(!enabled);
            if (mounted) setState(() => _soundMuted = !enabled);
            // Vista previa del sonido al reactivarlo.
            if (enabled) SoundEffects.playAddProduct();
          },
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool isDesktop,
    AsyncValue<List<Producto>> productsAsync,
    PosCartState cartState,
    AsyncValue<List<Categoria>> categoriesAsync,
  ) {
    return Row(
        children: [
          // Sección de productos (Grid)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  if (_editMode) _buildSoundToggle(),
                  Expanded(
                    child: productsAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Center(
                        child: Text(
                          'Error: $err',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                      data: (products) {
                        final gridDelegate =
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isDesktop ? 4 : 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.1,
                        );

                        if (_editMode) {
                          return ReorderableGridView.count(
                            crossAxisCount: isDesktop ? 4 : 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.1,
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                final moved = _editList.removeAt(oldIndex);
                                _editList.insert(newIndex, moved);
                              });
                              _persistOrder();
                            },
                            footer: [
                              _AddProductTile(onTap: _openAddSheet),
                            ],
                            children: [
                              for (final product in _editList)
                                _ProductGridItem(
                                  key: ValueKey(product.id),
                                  product: product,
                                  editMode: true,
                                  onRemove: () => _removeFromTurbo(product),
                                  onPickImage: () => _pickImageFor(product),
                                  onTap: () {},
                                ),
                            ],
                          );
                        }

                        if (products.isEmpty) {
                          return const Center(
                            child: Text(
                              'No se encontraron productos coincidentes.',
                              style: TextStyle(color: AppColors.blancoD),
                            ),
                          );
                        }

                        return GridView.builder(
                          gridDelegate: gridDelegate,
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final product = products[index];
                            final categories = categoriesAsync.value ?? [];
                            final cervezaCategory = categories.firstWhere(
                              (c) => c.nombre.toLowerCase() == 'cerveza',
                              orElse: () => const Categoria(id: '', nombre: ''),
                            );
                            final isCerveza = cervezaCategory.id.isNotEmpty &&
                                product.categoriaId == cervezaCategory.id;

                            return _ProductGridItem(
                              product: product,
                              onTap: () {
                                ref.read(posCartProvider.notifier).addProduct(
                                  product,
                                  cantidad: isCerveza ? 6 : 1,
                                );
                                // Feedback confiable multiplataforma: sonido corto
                                // + vibración ligera (subtil, no molesta).
                                SoundEffects.playAddProduct();
                                HapticFeedback.selectionClick();
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Barra lateral de compra (solo en Desktop)
          if (isDesktop)
            Container(
              width: 380,
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFF262626), width: 1),
                ),
                color: Color(0xFA131310),
              ),
              child: _SidebarCart(
                cartState: cartState,
                submitting: _submitting,
                onSubmit: _submitVenta,
              ),
            ),
        ],
      );
  }

  Widget? _buildBottomBar(
    BuildContext context,
    bool isDesktop,
    PosCartState cartState,
  ) {
    return !isDesktop
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFF262626), width: 1),
                ),
                color: Color(0xFA131310),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${cartState.totalItems} productos',
                            style: const TextStyle(color: AppColors.blancoD, fontSize: 13),
                          ),
                          Text(
                            formatCOP(cartState.total.toDouble()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: cartState.items.isEmpty
                          ? null
                          : () {
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: const Color(0xFA131310),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(20),
                                    topRight: Radius.circular(20),
                                  ),
                                ),
                                builder: (_) => DraggableScrollableSheet(
                                  initialChildSize: 0.65,
                                  maxChildSize: 0.9,
                                  expand: false,
                                  builder: (_, scrollCtrl) {
                                    return Consumer(
                                      builder: (context, ref, _) {
                                        final localCart = ref.watch(posCartProvider);
                                        return _SidebarCart(
                                          cartState: localCart,
                                          submitting: _submitting,
                                          onSubmit: (tot, met,
                                              {String? deudorNombre}) async {
                                            Navigator.of(context).pop(); // Cerrar sheet
                                            await _submitVenta(tot, met,
                                                deudorNombre: deudorNombre);
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              );
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                      child: const Text('Proceder al pago'),
                    ),
                  ],
                ),
              ),
            )
          : null;
  }
}

class _ProductGridItem extends StatelessWidget {
  const _ProductGridItem({
    super.key,
    required this.product,
    required this.onTap,
    this.editMode = false,
    this.onRemove,
    this.onPickImage,
  });

  final Producto product;
  final VoidCallback onTap;
  final bool editMode;
  final VoidCallback? onRemove;
  final VoidCallback? onPickImage;

  @override
  Widget build(BuildContext context) {
    final hasStock = product.stockActual > 0;
    final isLowStock = product.stockActual <= 10 && hasStock;
    final hasImage = (product.imagenUrl ?? '').isNotEmpty;

    Color stockColor = Colors.green;
    String stockLabel = '${product.stockActual} uds';
    if (!hasStock) {
      stockColor = Colors.redAccent;
      stockLabel = 'Agotado';
    } else if (isLowStock) {
      stockColor = Colors.amber;
      stockLabel = '${product.stockActual} uds';
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF262626), width: 1),
      ),
      color: hasStock ? const Color(0xFF16181C) : const Color(0xFF131310).withOpacity(0.5),
      child: InkWell(
        onTap: editMode ? null : (hasStock ? onTap : null),
        child: Stack(
          children: [
            if (hasImage) ...[
              Positioned.fill(
                child: Image.network(
                  product.imagenUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              // Gradiente para mantener legibles nombre y precio.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.80),
                        Colors.black.withOpacity(0.25),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stock pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: hasImage
                          ? Colors.black.withOpacity(0.55)
                          : stockColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      stockLabel,
                      style: TextStyle(
                        color: stockColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Title
                  Text(
                    product.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasStock ? Colors.white : Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      decoration: hasStock ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Price
                  Text(
                    formatCOP(product.precioPublico.toDouble()),
                    style: const TextStyle(
                      color: AppColors.ambar,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (editMode) ...[
              Positioned(
                top: 6,
                right: 6,
                child: _EditActionButton(
                  icon: Icons.close,
                  background: Colors.redAccent,
                  onTap: onRemove,
                ),
              ),
              Positioned(
                bottom: 6,
                right: 6,
                child: _EditActionButton(
                  icon: Icons.photo_camera,
                  background: Colors.black87,
                  onTap: onPickImage,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditActionButton extends StatelessWidget {
  const _EditActionButton({
    required this.icon,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _AddProductTile extends StatelessWidget {
  const _AddProductTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.ambar, width: 1.2),
      ),
      color: const Color(0xFF16181C),
      child: InkWell(
        onTap: onTap,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, color: AppColors.ambar, size: 34),
              SizedBox(height: 8),
              Text(
                'Agregar producto',
                style: TextStyle(
                  color: AppColors.ambar,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarCart extends StatefulWidget {
  const _SidebarCart({
    required this.cartState,
    required this.submitting,
    required this.onSubmit,
  });

  final PosCartState cartState;
  final bool submitting;
  final Future<void> Function(num total, MetodoPago metodo,
      {String? deudorNombre}) onSubmit;

  @override
  State<_SidebarCart> createState() => _SidebarCartState();
}

class _SidebarCartState extends State<_SidebarCart> {
  MetodoPago _selectedMetodo = MetodoPago.efectivo;
  final _deudorCtrl = TextEditingController();

  bool get _esFiado => _selectedMetodo == MetodoPago.credito;

  /// Un fiado sin nombre no se puede cobrar después; la base lo rechaza.
  bool get _faltaDeudor => _esFiado && _deudorCtrl.text.trim().isEmpty;

  @override
  void dispose() {
    _deudorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabecera Carrito
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'PEDIDO ACTUAL (${widget.cartState.totalItems})',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.blancoD,
              letterSpacing: 1.1,
            ),
          ),
        ),
        
        const Divider(height: 1, color: Color(0xFF262626)),

        // Lista de items
        Expanded(
          child: widget.cartState.items.isEmpty
              ? const Center(
                  child: Text(
                    'El carrito está vacío',
                    style: TextStyle(color: AppColors.blancoD),
                  ),
                )
              : Consumer(
                  builder: (context, ref, _) {
                    final controller = ref.read(posCartProvider.notifier);
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: widget.cartState.items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF262626)),
                      itemBuilder: (context, idx) {
                        final item = widget.cartState.items[idx];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.producto.nombre,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      formatCOP(item.precioUnitario.toDouble()),
                                      style: const TextStyle(color: AppColors.blancoD, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                                    onPressed: () => controller.decrement(item.producto.id),
                                  ),
                                  Text(
                                    '${item.cantidad}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 20),
                                    onPressed: () => controller.increment(item.producto.id),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        ),

        const Divider(height: 1, color: Color(0xFF262626)),

        // Métodos de pago
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'MÉTODO DE PAGO',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.blancoD),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _MetodoButton(
                    label: 'Efectivo',
                    icon: Icons.money,
                    selected: _selectedMetodo == MetodoPago.efectivo,
                    onTap: () => setState(() => _selectedMetodo = MetodoPago.efectivo),
                  ),
                  _MetodoButton(
                    label: 'Nequi',
                    icon: Icons.phone_android,
                    selected: _selectedMetodo == MetodoPago.nequi,
                    onTap: () => setState(() => _selectedMetodo = MetodoPago.nequi),
                  ),
                  _MetodoButton(
                    label: 'Transf.',
                    icon: Icons.account_balance,
                    selected: _selectedMetodo == MetodoPago.transferencia,
                    onTap: () => setState(() => _selectedMetodo = MetodoPago.transferencia),
                  ),
                  _MetodoButton(
                    label: 'Fiado',
                    icon: Icons.handshake_outlined,
                    selected: _esFiado,
                    onTap: () => setState(() => _selectedMetodo = MetodoPago.credito),
                  ),
                ],
              ),
              // El campo solo aparece al fiar, para no estorbar la venta
              // rápida de mostrador.
              if (_esFiado) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _deudorCtrl,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '¿A quién se le fía?',
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                    filled: true,
                    fillColor: const Color(0xFF262626),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Resumen total y botón
        Container(
          color: const Color(0xFF0F0F0D),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(fontSize: 14, color: AppColors.blancoD)),
                      Text(
                        formatCOP(widget.cartState.total.toDouble()),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ambar,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: widget.cartState.items.isEmpty ||
                            widget.submitting ||
                            _faltaDeudor
                        ? null
                        : () => widget.onSubmit(
                              widget.cartState.total,
                              _selectedMetodo,
                              deudorNombre: _deudorCtrl.text,
                            ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.ambar,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: widget.submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.bolt, size: 20),
                    label: const Text(
                      '⚡ REGISTRAR VENTA',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetodoButton extends StatelessWidget {
  const _MetodoButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: selected ? AppColors.ambar : const Color(0xFF262626),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? Colors.black : Colors.white,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.black : AppColors.blancoD,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessCheckoutDialog extends StatefulWidget {
  const _SuccessCheckoutDialog({
    required this.total,
    required this.metodo,
    this.deudorNombre,
  });

  final num total;
  final MetodoPago metodo;

  /// Solo en fiados: a quién se le fió.
  final String? deudorNombre;

  @override
  State<_SuccessCheckoutDialog> createState() => _SuccessCheckoutDialogState();
}

class _SuccessCheckoutDialogState extends State<_SuccessCheckoutDialog> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2500)).then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: AlertDialog(
        backgroundColor: const Color(0xFF0F0F0D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF262626), width: 1.5),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 48, color: Colors.green),
            ),
            const SizedBox(height: 16),
            const Text(
              'VENTA REGISTRADA',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              formatCOP(widget.total.toDouble()),
              style: const TextStyle(
                color: AppColors.ambar,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.metodo == MetodoPago.credito
                  ? 'Método: FIADO'
                  : 'Método: ${widget.metodo.value.toUpperCase()}',
              style: const TextStyle(color: AppColors.blancoD, fontSize: 13),
            ),
            if (widget.metodo == MetodoPago.credito &&
                (widget.deudorNombre?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 4),
              Text(
                'Queda debiendo: ${widget.deudorNombre!.trim()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ambar,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF262626)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('LISTO / CERRAR'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Se cerrará automáticamente en unos segundos...',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
