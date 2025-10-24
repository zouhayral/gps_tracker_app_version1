import 'package:flutter/material.dart';

/// Reusable action button for map controls
/// Features:
/// - Circular button with icon
/// - Optional loading state (shows spinner)
/// - Disabled state support
/// - Material elevation and ripple effect
class MapActionButton extends StatelessWidget {
  const MapActionButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.isLoading = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null || isLoading;
    final bg = disabled ? Colors.white.withValues(alpha: 0.6) : Colors.white;
    final fg = disabled ? Colors.black26 : Colors.black87;

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 4,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  )
                : Icon(icon, size: 22, color: fg),
          ),
        ),
      ),
    );
  }
}
