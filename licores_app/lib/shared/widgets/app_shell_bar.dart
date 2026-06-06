import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

class AppShellBar extends StatelessWidget implements PreferredSizeWidget {
  const AppShellBar({required this.title, this.actions, super.key});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(80.0);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'DON',
              style: GoogleFonts.firaMono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.5,
                color: AppColors.blancoD,
              ),
            ),
            Text(
              'Héctor',
              style: GoogleFonts.libreBaskerville(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: AppColors.blanco,
                height: 0.95,
              ),
            ),
          ],
        ),
      ),
      toolbarHeight: 80,
      actions: actions,
    );
  }
}
