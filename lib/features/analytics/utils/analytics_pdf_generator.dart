import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:my_app_gps/features/analytics/models/analytics_report.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';

/// Utility class for generating PDF reports from analytics data.
///
/// Converts [AnalyticsReport] instances into polished, shareable PDF documents
/// with summary statistics, charts, and branding.
class AnalyticsPdfGenerator {
  /// Brand accent color (lime green).
  static final _accentColor = PdfColor.fromInt(0xFFb4e15c);
  
  /// Secondary color for backgrounds.
  static final _lightGray = PdfColor.fromInt(0xFFF5F5F5);
  
  /// Text color.
  static final _darkGray = PdfColor.fromInt(0xFF424242);

  /// Generates a PDF report from the given [AnalyticsReport].
  ///
  /// The [periodLabel] is used in the filename and title (e.g., "Aujourd'hui", "Derniers 7 jours").
  ///
  /// Returns a [File] object pointing to the generated PDF in the temporary directory.
  ///
  /// Example:
  /// ```dart
  /// final report = AnalyticsReport(...);
  /// final pdfFile = await AnalyticsPdfGenerator.generate(report, "Aujourd'hui");
  /// // Share or display the PDF
  /// ```
  static Future<File> generate(
    AnalyticsReport report,
    String periodLabel,
  ) async {
    AppLogger.debug('[PDF] Generating analytics report for: $periodLabel');

    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final now = DateTime.now();

    // Build PDF content
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // Header Section
            _buildHeader(periodLabel, dateFormat, report),
            pw.SizedBox(height: 30),

            // Summary Statistics Table
            _buildSummarySection(report),
            pw.SizedBox(height: 30),

            // Period Details
            _buildPeriodDetails(report, dateFormat),
            pw.SizedBox(height: 30),

            // Charts Placeholder
            _buildChartsPlaceholder(),
            pw.SizedBox(height: 30),

            // Divider
            pw.Divider(color: _lightGray, thickness: 2),
            pw.SizedBox(height: 20),

            // Footer
            _buildFooter(now, dateFormat),
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

  /// Builds the header section with title and subtitle.
  static pw.Widget _buildHeader(
    String periodLabel,
    DateFormat dateFormat,
    AnalyticsReport report,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: _accentColor.flatten(),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'GPS Report – $periodLabel',
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Period: ${dateFormat.format(report.startTime)} - ${dateFormat.format(report.endTime)}',
            style: pw.TextStyle(
              fontSize: 12,
              color: _darkGray,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the summary statistics section with key metrics.
  static pw.Widget _buildSummarySection(AnalyticsReport report) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Main Statistics',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: _darkGray,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: _lightGray, width: 1),
          children: [
            // Header row
            _buildTableRow(
              'Metric',
              'Value',
              isHeader: true,
            ),
            // Data rows
            _buildTableRow(
              'Total Distance',
              '${report.totalDistanceKm.toStringAsFixed(2)} km',
            ),
            _buildTableRow(
              'Average Speed',
              '${report.avgSpeed.toStringAsFixed(1)} km/h',
            ),
            _buildTableRow(
              'Maximum Speed',
              '${report.maxSpeed.toStringAsFixed(1)} km/h',
            ),
            _buildTableRow(
              'Number of Trips',
              report.tripCount.toString(),
            ),
            if (report.fuelUsed != null && report.fuelUsed! > 0)
              _buildTableRow(
                'Fuel Used',
                '${report.fuelUsed!.toStringAsFixed(2)} L',
              ),
          ],
        ),
      ],
    );
  }

  /// Builds a table row with two columns.
  static pw.TableRow _buildTableRow(
    String label,
    String value, {
    bool isHeader = false,
  }) {
    final textStyle = pw.TextStyle(
      fontSize: isHeader ? 12 : 11,
      fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: isHeader ? PdfColors.white : _darkGray,
    );

    final backgroundColor = isHeader ? _accentColor.flatten() : PdfColors.white;

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: backgroundColor),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Text(label, style: textStyle),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Text(
            value,
            style: textStyle.copyWith(
              fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// Builds the period details section.
  static pw.Widget _buildPeriodDetails(
    AnalyticsReport report,
    DateFormat dateFormat,
  ) {
    final duration = report.endTime.difference(report.startTime);
    final durationText = _formatDuration(duration);

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _lightGray,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Period Details',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _darkGray,
            ),
          ),
          pw.SizedBox(height: 12),
          _buildDetailRow('Start', dateFormat.format(report.startTime)),
          pw.SizedBox(height: 6),
          _buildDetailRow('End', dateFormat.format(report.endTime)),
          pw.SizedBox(height: 6),
          _buildDetailRow('Duration', durationText),
        ],
      ),
    );
  }

  /// Builds a detail row with label and value.
  static pw.Widget _buildDetailRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          '$label:',
          style: pw.TextStyle(
            fontSize: 11,
            color: _darkGray,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _darkGray,
          ),
        ),
      ],
    );
  }

  /// Builds the charts placeholder section.
  static pw.Widget _buildChartsPlaceholder() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _lightGray, width: 2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Icon(
            pw.IconData(0xe4a7), // chart icon
            size: 40,
            color: _lightGray,
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Charts not included',
            style: pw.TextStyle(
              fontSize: 12,
              color: PdfColors.grey600,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Speed and trip charts will be added in a future update',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey500,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Builds the footer section with generation timestamp and app info.
  static pw.Widget _buildFooter(DateTime now, DateFormat dateFormat) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'Generated on ${dateFormat.format(now)}',
          style: pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey600,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'GPS Tracker App',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _accentColor.flatten(),
          ),
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
}
