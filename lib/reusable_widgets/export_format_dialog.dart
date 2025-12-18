import 'package:flutter/material.dart';
import '../services/export_service.dart';

/// Dialog for selecting export format
class ExportFormatDialog extends StatelessWidget {
  final String title;
  final String? subtitle;

  const ExportFormatDialog({super.key, required this.title, this.subtitle});

  static Future<ExportFormat?> show(
    BuildContext context, {
    required String title,
    String? subtitle,
  }) async {
    return await showDialog<ExportFormat>(
      context: context,
      builder: (context) =>
          ExportFormatDialog(title: title, subtitle: subtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.download, color: Color(0xFF00897B)),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) ...[
            Text(
              subtitle!,
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 16),
          ],
          _FormatOption(
            format: ExportFormat.csv,
            icon: Icons.table_chart,
            title: 'CSV',
            description: 'Compatible with Excel, Google Sheets',
            color: Colors.green,
            onTap: () => Navigator.pop(context, ExportFormat.csv),
          ),
          const SizedBox(height: 12),
          _FormatOption(
            format: ExportFormat.json,
            icon: Icons.code,
            title: 'JSON',
            description: 'Structured data for APIs and programming',
            color: Colors.blue,
            onTap: () => Navigator.pop(context, ExportFormat.json),
          ),
          const SizedBox(height: 12),
          _FormatOption(
            format: ExportFormat.excel,
            icon: Icons.grid_on,
            title: 'Excel (XLSX)',
            description: 'Professional spreadsheet with formatting',
            color: Colors.green[700]!,
            onTap: () => Navigator.pop(context, ExportFormat.excel),
          ),
          const SizedBox(height: 12),
          _FormatOption(
            format: ExportFormat.pdf,
            icon: Icons.picture_as_pdf,
            title: 'PDF',
            description: 'Printable professional reports',
            color: Colors.red,
            onTap: () => Navigator.pop(context, ExportFormat.pdf),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _FormatOption extends StatelessWidget {
  final ExportFormat format;
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _FormatOption({
    required this.format,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
