import 'package:flutter/material.dart';
import 'package:my_app_gps/theme/app_colors.dart';

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(seedColor: AppColors.seed);
  return ThemeData(
    colorScheme: colorScheme,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceTint,
      indicatorColor: AppColors.seed,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
        const base = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
        if (states.contains(WidgetState.selected)) {
          return base.copyWith(color: AppColors.seed);
        }
        return base.copyWith(color: AppColors.neutral);
      }),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Colors.white);
        }
        return const IconThemeData(color: AppColors.neutral);
      }),
      elevation: 0,
      height: 64,
    ),
  );
}
