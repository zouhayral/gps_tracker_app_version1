import 'package:flutter/material.dart';

/// Search bar widget for the map page with gated interaction:
/// - Single tap: show/hide suggestions
/// - Double tap or keyboard icon: enable editing mode
/// - Supports real-time search with debouncing
class MapSearchBar extends StatelessWidget {
  const MapSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.focusNode,
    required this.editing,
    required this.onRequestEdit,
    required this.onCloseEditing,
    required this.onSingleTap,
    required this.onDoubleTap,
    required this.onToggleSuggestions,
    required this.suggestionsVisible,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final FocusNode focusNode;
  final bool editing;
  final VoidCallback onRequestEdit;
  final VoidCallback onCloseEditing;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggleSuggestions;
  final bool suggestionsVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = controller.text.isNotEmpty;
    final active = editing || focusNode.hasFocus;
    final borderColor = active ? const Color(0xFFA6CD27) : Colors.black12;

    return GestureDetector(
      onTap: onSingleTap,
      onDoubleTap: onDoubleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor, width: active ? 1.5 : 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.search, color: Colors.grey[700], size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                readOnly: !editing,
                onChanged: onChanged,
                cursorColor: const Color(0xFF49454F),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search vehicle',
                  border: InputBorder.none,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onToggleSuggestions,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  suggestionsVisible ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Colors.black54,
                ),
              ),
            ),
            if (hasText)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 20, color: Colors.black54),
                ),
              )
            else
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => editing ? onCloseEditing() : onRequestEdit(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    editing ? Icons.keyboard_hide : Icons.keyboard,
                    size: 20,
                    color: Colors.black54,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
