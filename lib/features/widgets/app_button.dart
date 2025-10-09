import 'package:flutter/material.dart';

/// Reusable application button with consistent styling.
///
/// Features:
/// - Variants: primary / secondary / destructive / text.
/// - Loading state (shows progress indicator, disables taps).
/// - Disabled state.
/// - Optional leading icon.
/// - Full width or intrinsic sizing.
/// - Adaptive to current ColorScheme.
class AppButton extends StatelessWidget {
	const AppButton.primary({
		super.key,
		required this.label,
		this.onPressed,
		this.icon,
		this.fullWidth = true,
		this.loading = false,
		this.enabled = true,
	}) : variant = _ButtonVariant.primary;

	const AppButton.secondary({
		super.key,
		required this.label,
		this.onPressed,
		this.icon,
		this.fullWidth = true,
		this.loading = false,
		this.enabled = true,
	}) : variant = _ButtonVariant.secondary;

	const AppButton.destructive({
		super.key,
		required this.label,
		this.onPressed,
		this.icon,
		this.fullWidth = true,
		this.loading = false,
		this.enabled = true,
	}) : variant = _ButtonVariant.destructive;

	const AppButton.text({
		super.key,
		required this.label,
		this.onPressed,
		this.icon,
		this.fullWidth = false,
		this.loading = false,
		this.enabled = true,
	}) : variant = _ButtonVariant.text;

	final String label;
	final VoidCallback? onPressed;
	final Widget? icon;
	final bool fullWidth;
	final bool loading;
	final bool enabled;
	final _ButtonVariant variant;

	bool get _effectiveEnabled => enabled && !loading && onPressed != null;

	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		final (bg, fg, border) = switch (variant) {
			_ButtonVariant.primary => (cs.primary, Colors.white, null),
			_ButtonVariant.secondary => (cs.secondaryContainer, cs.onSecondaryContainer, BorderSide(color: cs.secondary)),
			_ButtonVariant.destructive => (const Color(0xFFFF383C), Colors.white, null),
			_ButtonVariant.text => (Colors.transparent, cs.primary, null),
		};

		final disabledBg = switch (variant) {
			_ButtonVariant.text => Colors.transparent,
			_ButtonVariant.secondary => cs.surfaceVariant,
			_ButtonVariant.primary => cs.surfaceVariant,
			_ButtonVariant.destructive => const Color(0x55FF383C),
		};
		final disabledFg = cs.onSurface.withValues(alpha: 0.38);

		final child = Row(
			mainAxisSize: MainAxisSize.min,
			mainAxisAlignment: MainAxisAlignment.center,
			children: [
				if (loading)
					SizedBox(
						width: 18,
						height: 18,
						child: CircularProgressIndicator(
							strokeWidth: 2.2,
							valueColor: AlwaysStoppedAnimation<Color>(_effectiveEnabled ? fg : disabledFg),
						),
					)
				else if (icon != null) ...[
					IconTheme.merge(
						data: IconThemeData(size: 18, color: _effectiveEnabled ? fg : disabledFg),
						child: icon!,
					),
				],
				if (icon != null || loading) const SizedBox(width: 8),
				Flexible(
					child: Text(
						label,
						overflow: TextOverflow.ellipsis,
						style: TextStyle(
							fontSize: 15,
							fontWeight: FontWeight.w600,
							color: _effectiveEnabled ? fg : disabledFg,
							letterSpacing: 0.2,
						),
					),
				),
			],
		);

		Widget button = AnimatedContainer(
			duration: const Duration(milliseconds: 180),
			curve: Curves.easeOut,
			decoration: BoxDecoration(
				color: _effectiveEnabled ? bg : disabledBg,
				borderRadius: BorderRadius.circular(14),
				border: border == null ? null : Border.fromBorderSide(border),
				boxShadow: variant == _ButtonVariant.text
						? null
						: [
								BoxShadow(
									color: Colors.black.withValues(alpha: 0.08),
									blurRadius: 10,
									offset: const Offset(0, 4),
								),
							],
			),
			padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
			child: child,
		);

		if (_effectiveEnabled) {
			button = InkWell(
				borderRadius: BorderRadius.circular(14),
				onTap: onPressed,
				child: button,
			);
		} else {
			button = ExcludeSemantics(child: button);
		}

		if (fullWidth) {
			button = SizedBox(width: double.infinity, child: button);
		}

		return Semantics(
			button: true,
			enabled: _effectiveEnabled,
			label: label,
			child: button,
		);
	}
}

enum _ButtonVariant { primary, secondary, destructive, text }
