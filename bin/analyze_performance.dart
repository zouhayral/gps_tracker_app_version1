/// Performance Analysis Script
/// 
/// Run this script to analyze widget rebuild performance
/// 
/// Usage:
/// ```
/// flutter run --profile lib/main.dart
/// # Then in another terminal:
/// flutter attach
/// ```

void main() {
  print('');
  print('═══════════════════════════════════════════════════════════');
  print('  PERFORMANCE ANALYSIS UTILITY');
  print('═══════════════════════════════════════════════════════════');
  print('');
  print('This script helps analyze widget rebuild performance.');
  print('');
  print('To use:');
  print('1. Run the app in profile mode:');
  print('   flutter run --profile');
  print('');
  print('2. In the app, call:');
  print('   PerformanceAnalyzer.instance.startAnalysis();');
  print('');
  print('3. Navigate through MapPage and NotificationsPage');
  print('');
  print('4. After 10 seconds, see the report in console');
  print('');
  print('Or manually call in your code:');
  print('   if (kDebugMode) {');
  print('     PerformanceAnalyzer.instance.startAnalysis(');
  print('       duration: Duration(seconds: 10)');
  print('     );');
  print('   }');
  print('');
  print('═══════════════════════════════════════════════════════════');
}
