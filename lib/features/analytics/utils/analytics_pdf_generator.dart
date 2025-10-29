import 'dart:io';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/features/analytics/models/analytics_report.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Utility class for generating PDF reports from analytics data.
///
/// Converts [AnalyticsReport] instances into polished, shareable PDF documents
/// with summary statistics, charts, and branding.
class AnalyticsPdfGenerator {
  /// Brand accent color (lime green).
  static const _accentColor = PdfColor.fromInt(0xFFb4e15c);
  
  /// Darker accent for contrast.
  static const _accentDark = PdfColor.fromInt(0xFF8BC34A);
  
  /// Secondary color for backgrounds.
  static const _lightGray = PdfColor.fromInt(0xFFF5F5F5);
  
  /// Light background for cards.
  static const _cardBg = PdfColor.fromInt(0xFFFAFAFA);
  
  /// Text color.
  static const _darkGray = PdfColor.fromInt(0xFF424242);
  
  /// Success color.
  static const _successColor = PdfColor.fromInt(0xFF4CAF50);
  
  /// Warning color.
  static const _warningColor = PdfColor.fromInt(0xFFFF9800);
  
  /// Info color.
  static const _infoColor = PdfColor.fromInt(0xFF2196F3);

  /// Generates a PDF report from the given [AnalyticsReport].
  ///
  /// The [periodLabel] is used in the filename and title (e.g., "Aujourd'hui", "Derniers 7 jours").
  /// The [t] parameter provides localized strings for all labels in the report.
  ///
  /// Returns a [File] object pointing to the generated PDF in the temporary directory.
  ///
  /// Example:
  /// ```dart
  /// final report = AnalyticsReport(...);
  /// final t = AppLocalizations.of(context)!;
  /// final pdfFile = await AnalyticsPdfGenerator.generate(report, "Aujourd'hui", t);
  /// // Share or display the PDF
  /// ```
  static Future<File> generate(
    AnalyticsReport report,
    String periodLabel,
    AppLocalizations t,
  ) async {
    AppLogger.debug('[PDF] Generating analytics report for: $periodLabel');

    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final now = DateTime.now();
    
    // Determine text direction based on locale
    final textDirection = t.localeName == 'ar' 
        ? pw.TextDirection.rtl 
        : pw.TextDirection.ltr;

    // Build PDF content
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        textDirection: textDirection,
        build: (pw.Context context) {
          return [
            // Modern Header with Icon
            _buildModernHeader(periodLabel, dateFormat, report, t, textDirection),
            pw.SizedBox(height: 24),

            // Key Metrics Cards (Grid)
            _buildKeyMetricsGrid(report, t, textDirection),
            pw.SizedBox(height: 24),

            // Visual Charts Section
            _buildChartsSection(report, t, textDirection),
            pw.SizedBox(height: 24),

            // Period Details Card
            _buildPeriodDetailsCard(report, dateFormat, t, textDirection),
            pw.SizedBox(height: 24),

            // Divider
            pw.Divider(color: _lightGray, thickness: 1.5),
            pw.SizedBox(height: 16),

            // Modern Footer
            _buildModernFooter(now, dateFormat, t, textDirection),
          ];
        },
      ),
    );

    // Save to temporary directory
    try {
      final output = await getTemporaryDirectory();
      final sanitizedLabel = periodLabel.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final file = File('${output.path}/rapport_${sanitizedLabel}_$timestamp.pdf');
      
      await file.writeAsBytes(await pdf.save());
      
      AppLogger.info('[PDF] Report generated successfully: ${file.path}');
      return file;
    } catch (e, stackTrace) {
      AppLogger.error('[PDF] Failed to generate report', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Builds a modern header with emoji and gradient background.
  static pw.Widget _buildModernHeader(
    String periodLabel,
    DateFormat dateFormat,
    AnalyticsReport report,
    AppLocalizations t,
    pw.TextDirection textDirection,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(24),
      decoration: const pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [_accentColor, _accentDark],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(16)),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColors.grey400,
            blurRadius: 10,
            offset: PdfPoint(0, 4),
          ),
        ],
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  t.reportsTitle,
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  textDirection: textDirection,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  periodLabel,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF212121),
                  ),
                  textDirection: textDirection,
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white.flatten(),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
                  ),
                  child: pw.Text(
                    '${t.period}: ${dateFormat.format(report.startTime)} - ${dateFormat.format(report.endTime)}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: _darkGray,
                    ),
                    textDirection: textDirection,
                  ),
                ),
              ],
            ),
          ),
          // Emoji Icon
          pw.Container(
            width: 70,
            height: 70,
            decoration: pw.BoxDecoration(
              color: PdfColors.white.flatten(),
              shape: pw.BoxShape.circle,
            ),
            child: pw.Center(
              child: pw.Text(
                '📊',
                style: const pw.TextStyle(
                  fontSize: 36,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a grid of key metric cards with icons.
  static pw.Widget _buildKeyMetricsGrid(
    AnalyticsReport report,
    AppLocalizations t,
    pw.TextDirection textDirection,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          t.mainStatistics,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: _darkGray,
          ),
          textDirection: textDirection,
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            pw.Expanded(
              child: _buildMetricCard(
                icon: 'distance',
                label: t.distance,
                value: '${report.totalDistanceKm.toStringAsFixed(2)} km',
                color: _infoColor,
                textDirection: textDirection,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _buildMetricCard(
                icon: 'speed',
                label: '${t.avgSpeed}',
                value: '${report.avgSpeed.toStringAsFixed(1)} km/h',
                color: _successColor,
                textDirection: textDirection,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            pw.Expanded(
              child: _buildMetricCard(
                icon: 'max',
                label: '${t.maxSpeed}',
                value: '${report.maxSpeed.toStringAsFixed(0)} km/h',
                color: _warningColor,
                textDirection: textDirection,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _buildMetricCard(
                icon: 'trips',
                label: t.trips,
                value: report.tripCount.toString(),
                color: _accentDark,
                textDirection: textDirection,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds a single metric card with emoji icon.
  static pw.Widget _buildMetricCard({
    required String icon,
    required String label,
    required String value,
    required PdfColor color,
    required pw.TextDirection textDirection,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: const pw.BoxDecoration(
        color: _cardBg,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border(
          top: pw.BorderSide(color: _lightGray, width: 1),
          bottom: pw.BorderSide(color: _lightGray, width: 1),
          left: pw.BorderSide(color: _lightGray, width: 1),
          right: pw.BorderSide(color: _lightGray, width: 1),
        ),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColors.grey300,
            blurRadius: 4,
            offset: PdfPoint(0, 2),
          ),
        ],
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 40,
                height: 40,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: color.flatten(),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: _buildIcon(icon, color, 24),
              ),
              pw.Spacer(),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 11,
              color: PdfColors.grey600,
            ),
            textDirection: textDirection,
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: _darkGray,
            ),
            textDirection: textDirection,
          ),
        ],
      ),
    );
  }

  /// Builds visual charts section with bar chart and pie chart.
  static pw.Widget _buildChartsSection(
    AnalyticsReport report,
    AppLocalizations t,
    pw.TextDirection textDirection,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          t.speedEvolution,
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: _darkGray,
          ),
          textDirection: textDirection,
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Speed Bar Chart
            pw.Expanded(
              flex: 3,
              child: _buildSpeedBarChart(report, t, textDirection),
            ),
            pw.SizedBox(width: 16),
            // Metrics Summary
            pw.Expanded(
              flex: 2,
              child: _buildMetricsSummary(report, t, textDirection),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds a bar chart showing speed metrics.
  static pw.Widget _buildSpeedBarChart(
    AnalyticsReport report,
    AppLocalizations t,
    pw.TextDirection textDirection,
  ) {
    final maxSpeed = report.maxSpeed;
    final avgSpeed = report.avgSpeed;
    const chartMaxHeight = 150.0;
    
    final avgBarHeight = (avgSpeed / maxSpeed) * chartMaxHeight;
    const maxBarHeight = chartMaxHeight;

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: _lightGray, width: 1),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            '${t.speed} (km/h)',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _darkGray,
            ),
            textDirection: textDirection,
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              // Average Speed Bar
              _buildBar(
                height: avgBarHeight,
                label: t.avgSpeed,
                value: avgSpeed.toStringAsFixed(1),
                color: _successColor,
                textDirection: textDirection,
              ),
              // Max Speed Bar
              _buildBar(
                height: maxBarHeight,
                label: t.maxSpeed,
                value: maxSpeed.toStringAsFixed(1),
                color: _warningColor,
                textDirection: textDirection,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds a single bar for the chart.
  static pw.Widget _buildBar({
    required double height,
    required String label,
    required String value,
    required PdfColor color,
    required pw.TextDirection textDirection,
  }) {
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _darkGray,
          ),
          textDirection: textDirection,
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          width: 60,
          height: height < 20 ? 20 : height,
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              begin: pw.Alignment.bottomCenter,
              end: pw.Alignment.topCenter,
              colors: [
                color,
                color.flatten(),
              ],
            ),
            borderRadius: const pw.BorderRadius.vertical(
              top: pw.Radius.circular(8),
            ),
            boxShadow: [
              pw.BoxShadow(
                color: color.flatten(),
                blurRadius: 4,
                offset: const PdfPoint(0, 2),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          width: 70,
          child: pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
            ),
            textAlign: pw.TextAlign.center,
            textDirection: textDirection,
          ),
        ),
      ],
    );
  }

  /// Builds a metrics summary panel.
  static pw.Widget _buildMetricsSummary(
    AnalyticsReport report,
    AppLocalizations t,
    pw.TextDirection textDirection,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: _lightGray, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            t.periodSummary,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _darkGray,
            ),
            textDirection: textDirection,
          ),
          pw.SizedBox(height: 16),
          _buildSummaryItem(
            icon: 'distance',
            label: t.distance,
            value: '${report.totalDistanceKm.toStringAsFixed(2)} km',
            color: _infoColor,
            textDirection: textDirection,
          ),
          pw.SizedBox(height: 12),
          _buildSummaryItem(
            icon: 'trips',
            label: t.trips,
            value: report.tripCount.toString(),
            color: _accentDark,
            textDirection: textDirection,
          ),
          if (report.fuelUsed != null && report.fuelUsed! > 0) ...[
            pw.SizedBox(height: 12),
            _buildSummaryItem(
              icon: 'fuel',
              label: t.fuelUsed,
              value: '${report.fuelUsed!.toStringAsFixed(2)} L',
              color: _warningColor,
              textDirection: textDirection,
            ),
          ],
          pw.SizedBox(height: 20),
          // Visual indicator
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: _successColor.flatten(),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  '✓',
                  style: const pw.TextStyle(
                    fontSize: 14,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Text(
                  'Complete',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a summary item with emoji icon.
  static pw.Widget _buildSummaryItem({
    required String icon,
    required String label,
    required String value,
    required PdfColor color,
    required pw.TextDirection textDirection,
  }) {
    return pw.Row(
      children: [
        pw.Container(
          width: 28,
          height: 28,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            color: color.flatten(),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Center(
            child: _buildIcon(icon, color, 16),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
                textDirection: textDirection,
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _darkGray,
                ),
                textDirection: textDirection,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds period details card with timeline design.
  static pw.Widget _buildPeriodDetailsCard(
    AnalyticsReport report,
    DateFormat dateFormat,
    AppLocalizations t,
    pw.TextDirection textDirection,
  ) {
    final duration = report.endTime.difference(report.startTime);
    final durationText = _formatDuration(duration);

    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: const pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [_cardBg, PdfColors.white],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border(
          top: pw.BorderSide(color: _lightGray, width: 1),
          bottom: pw.BorderSide(color: _lightGray, width: 1),
          left: pw.BorderSide(color: _lightGray, width: 1),
          right: pw.BorderSide(color: _lightGray, width: 1),
        ),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColors.grey300,
            blurRadius: 4,
            offset: PdfPoint(0, 2),
          ),
        ],
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: _infoColor.flatten(),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Text(
                  '🕐', // schedule/clock emoji
                  style: const pw.TextStyle(
                    fontSize: 18,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text(
                t.periodDetails,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: _darkGray,
                ),
                textDirection: textDirection,
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          // Timeline visualization
          _buildTimelineItem(
            icon: 'start',
            label: t.start,
            value: dateFormat.format(report.startTime),
            color: _successColor,
            textDirection: textDirection,
            isFirst: true,
          ),
          pw.SizedBox(height: 4),
          _buildTimelineDivider(),
          pw.SizedBox(height: 4),
          _buildTimelineItem(
            icon: 'duration',
            label: t.duration,
            value: durationText,
            color: _infoColor,
            textDirection: textDirection,
            isFirst: false,
          ),
          pw.SizedBox(height: 4),
          _buildTimelineDivider(),
          pw.SizedBox(height: 4),
          _buildTimelineItem(
            icon: 'end',
            label: t.end,
            value: dateFormat.format(report.endTime),
            color: _warningColor,
            textDirection: textDirection,
            isFirst: false,
          ),
        ],
      ),
    );
  }

  /// Builds a timeline item with emoji icon.
  static pw.Widget _buildTimelineItem({
    required String icon,
    required String label,
    required String value,
    required PdfColor color,
    required pw.TextDirection textDirection,
    required bool isFirst,
  }) {
    return pw.Row(
      children: [
        pw.Container(
          width: 40,
          height: 40,
          decoration: pw.BoxDecoration(
            color: color.flatten(),
            shape: pw.BoxShape.circle,
          ),
          child: pw.Center(
            child: _buildIcon(icon, color, 20),
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey600,
                ),
                textDirection: textDirection,
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _darkGray,
                ),
                textDirection: textDirection,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds a timeline divider line.
  static pw.Widget _buildTimelineDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 19),
      child: pw.Container(
        width: 2,
        height: 16,
        color: _lightGray,
      ),
    );
  }

  /// Builds a modern footer with branding and generation info.
  static pw.Widget _buildModernFooter(
    DateTime now, 
    DateFormat dateFormat,
    AppLocalizations t,
    pw.TextDirection textDirection,
  ) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                pw.Container(
                  width: 30,
                  height: 30,
                  decoration: const pw.BoxDecoration(
                    gradient: pw.LinearGradient(
                      colors: [_accentColor, _accentDark],
                    ),
                    shape: pw.BoxShape.circle,
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      '📍', // gps/location pin emoji
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'GPS Tracker App',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _darkGray,
                      ),
                    ),
                    pw.Text(
                      'Real-time vehicle monitoring',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: pw.BoxDecoration(
                color: _cardBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                border: pw.Border.all(color: _lightGray, width: 1),
              ),
              child: pw.Row(
                children: [
                  pw.Text(
                    '📅', // calendar emoji
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    '${t.generatedOn} ${dateFormat.format(now)}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                    textDirection: textDirection,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Formats a duration into a human-readable string.
  static String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}j ${duration.inHours % 24}h ${duration.inMinutes % 60}min';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}min';
    } else {
      return '${duration.inMinutes}min';
    }
  }

  /// Builds an icon widget using custom drawn shapes
  static pw.Widget _buildIcon(String iconType, PdfColor color, double size) {
    return pw.CustomPaint(
      size: PdfPoint(size, size),
      painter: (PdfGraphics canvas, PdfPoint pdfSize) {
        canvas
          ..setStrokeColor(PdfColors.white)
          ..setFillColor(PdfColors.white)
          ..setLineWidth(2);

        switch (iconType) {
          case 'distance':
            // Draw route/path icon (wavy line)
            canvas
              ..moveTo(pdfSize.x * 0.2, pdfSize.y * 0.3)
              ..lineTo(pdfSize.x * 0.4, pdfSize.y * 0.5)
              ..lineTo(pdfSize.x * 0.6, pdfSize.y * 0.4)
              ..lineTo(pdfSize.x * 0.8, pdfSize.y * 0.6)
              ..strokePath();
            // Add arrow
            canvas
              ..moveTo(pdfSize.x * 0.8, pdfSize.y * 0.6)
              ..lineTo(pdfSize.x * 0.7, pdfSize.y * 0.55)
              ..moveTo(pdfSize.x * 0.8, pdfSize.y * 0.6)
              ..lineTo(pdfSize.x * 0.75, pdfSize.y * 0.68)
              ..strokePath();
            break;

          case 'speed':
            // Draw speedometer icon (arc with needle)
            final centerX = pdfSize.x * 0.5;
            final centerY = pdfSize.y * 0.6;
            final radius = pdfSize.x * 0.35;
            // Arc
            for (var i = 0.7; i <= 2.3; i += 0.1) {
              final x = centerX + radius * 0.8 * cos(i * pi);
              final y = centerY + radius * 0.8 * sin(i * pi);
              if (i == 0.7) {
                canvas.moveTo(x, y);
              } else {
                canvas.lineTo(x, y);
              }
            }
            canvas.strokePath();
            // Needle
            canvas
              ..moveTo(centerX, centerY)
              ..lineTo(centerX + radius * 0.6, centerY - radius * 0.3)
              ..strokePath();
            break;

          case 'max':
            // Draw upward arrow
            canvas
              ..moveTo(pdfSize.x * 0.5, pdfSize.y * 0.2)
              ..lineTo(pdfSize.x * 0.3, pdfSize.y * 0.4)
              ..moveTo(pdfSize.x * 0.5, pdfSize.y * 0.2)
              ..lineTo(pdfSize.x * 0.7, pdfSize.y * 0.4)
              ..moveTo(pdfSize.x * 0.5, pdfSize.y * 0.2)
              ..lineTo(pdfSize.x * 0.5, pdfSize.y * 0.8)
              ..setLineWidth(2.5)
              ..strokePath();
            break;

          case 'trips':
            // Draw car icon (simplified)
            canvas
              // Car body
              ..moveTo(pdfSize.x * 0.2, pdfSize.y * 0.5)
              ..lineTo(pdfSize.x * 0.3, pdfSize.y * 0.3)
              ..lineTo(pdfSize.x * 0.7, pdfSize.y * 0.3)
              ..lineTo(pdfSize.x * 0.8, pdfSize.y * 0.5)
              ..lineTo(pdfSize.x * 0.8, pdfSize.y * 0.7)
              ..lineTo(pdfSize.x * 0.2, pdfSize.y * 0.7)
              ..lineTo(pdfSize.x * 0.2, pdfSize.y * 0.5)
              ..strokePath();
            // Wheels
            canvas.drawEllipse(pdfSize.x * 0.3, pdfSize.y * 0.75, pdfSize.x * 0.08, pdfSize.y * 0.08);
            canvas.drawEllipse(pdfSize.x * 0.7, pdfSize.y * 0.75, pdfSize.x * 0.08, pdfSize.y * 0.08);
            canvas.strokePath();
            break;

          case 'fuel':
            // Draw fuel pump icon
            canvas
              ..drawRect(pdfSize.x * 0.3, pdfSize.y * 0.3, pdfSize.x * 0.4, pdfSize.y * 0.5)
              ..strokePath()
              ..moveTo(pdfSize.x * 0.5, pdfSize.y * 0.45)
              ..lineTo(pdfSize.x * 0.7, pdfSize.y * 0.45)
              ..lineTo(pdfSize.x * 0.7, pdfSize.y * 0.3)
              ..strokePath();
            break;

          case 'start':
            // Draw play/start triangle
            canvas
              ..moveTo(pdfSize.x * 0.3, pdfSize.y * 0.2)
              ..lineTo(pdfSize.x * 0.3, pdfSize.y * 0.8)
              ..lineTo(pdfSize.x * 0.75, pdfSize.y * 0.5)
              ..lineTo(pdfSize.x * 0.3, pdfSize.y * 0.2)
              ..fillPath();
            break;

          case 'duration':
            // Draw clock icon
            canvas.drawEllipse(pdfSize.x * 0.5, pdfSize.y * 0.5, pdfSize.x * 0.4, pdfSize.y * 0.4);
            canvas.strokePath();
            // Clock hands
            canvas
              ..moveTo(pdfSize.x * 0.5, pdfSize.y * 0.5)
              ..lineTo(pdfSize.x * 0.5, pdfSize.y * 0.25)
              ..moveTo(pdfSize.x * 0.5, pdfSize.y * 0.5)
              ..lineTo(pdfSize.x * 0.7, pdfSize.y * 0.5)
              ..strokePath();
            break;

          case 'end':
            // Draw stop square
            canvas
              ..drawRect(pdfSize.x * 0.25, pdfSize.y * 0.25, pdfSize.x * 0.5, pdfSize.y * 0.5)
              ..fillPath();
            break;
        }
      },
    );
  }
}
