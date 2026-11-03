import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/excel_file_picker_helper.dart';
import 'url_opener_stub.dart' if (dart.library.html) 'url_opener_web.dart';

class BulkPartsImportDialog extends StatefulWidget {
  final String baseUrl;
  final Map<String, String> authHeaders;
  final VoidCallback onImportCompleted;

  const BulkPartsImportDialog({
    super.key,
    required this.baseUrl,
    required this.authHeaders,
    required this.onImportCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required String baseUrl,
    required Map<String, String> authHeaders,
    required VoidCallback onImportCompleted,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BulkPartsImportDialog(
        baseUrl: baseUrl,
        authHeaders: authHeaders,
        onImportCompleted: onImportCompleted,
      ),
    );
  }

  @override
  State<BulkPartsImportDialog> createState() => _BulkPartsImportDialogState();
}

class _BulkPartsImportDialogState extends State<BulkPartsImportDialog> {
  String? _selectedFileName;
  int? _selectedFileSize;

  bool _isPastingCsv = false;
  final TextEditingController _csvTextCtrl = TextEditingController();

  bool _isPreviewing = false;
  bool _isImporting = false;
  String? _errorMessage;

  // Preview data from server
  Map<String, dynamic>? _previewData;
  List<dynamic> _parsedItems = [];
  List<dynamic> _invalidRows = [];
  int _totalRows = 0;
  int _newCount = 0;
  int _updateCount = 0;

  // Import options
  bool _updateExisting = true;
  String _stockMode = 'ADD'; // 'ADD' or 'SET'
  bool _createStockMovements = true;

  @override
  void dispose() {
    _csvTextCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final file = await ExcelFilePickerHelper.pickSpreadsheetFile();
      if (file == null) return;

      if (file.bytes.isEmpty) {
        setState(() {
          _errorMessage = 'Selected file is empty. Please choose a valid Excel or CSV file.';
        });
        return;
      }

      final base64String = base64Encode(file.bytes);

      setState(() {
        _selectedFileName = file.name;
        _selectedFileSize = file.size;
        _isPastingCsv = false;
      });

      await _requestPreview(fileBase64: base64String, fileName: file.name);
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking file: $e';
      });
    }
  }

  Future<void> _requestPreview({String? fileBase64, String? fileName, String? csvText}) async {
    setState(() {
      _isPreviewing = true;
      _errorMessage = null;
      _previewData = null;
    });

    try {
      final payload = <String, dynamic>{};
      if (fileBase64 != null) {
        payload['fileBase64'] = fileBase64;
        payload['fileName'] = fileName ?? 'parts_import.xlsx';
      } else if (csvText != null && csvText.trim().isNotEmpty) {
        payload['csvText'] = csvText.trim();
        payload['fileName'] = 'pasted_parts.csv';
      } else {
        setState(() => _isPreviewing = false);
        return;
      }

      final res = await http.post(
        Uri.parse('${widget.baseUrl}/parts/bulk-preview'),
        headers: {'Content-Type': 'application/json', ...widget.authHeaders},
        body: json.encode(payload),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _previewData = data;
          _parsedItems = (data['items'] is List) ? data['items'] : [];
          _invalidRows = (data['errors'] is List) ? data['errors'] : [];
          _totalRows = (data['totalRows'] as num?)?.toInt() ?? 0;
          _newCount = (data['newCount'] as num?)?.toInt() ?? 0;
          _updateCount = (data['updateCount'] as num?)?.toInt() ?? 0;
        });
      } else {
        final err = json.decode(res.body);
        setState(() {
          _errorMessage = err['error'] ?? 'Failed to preview file (${res.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to connect to server: $e';
      });
    } finally {
      if (mounted) setState(() => _isPreviewing = false);
    }
  }

  Future<void> _executeImport() async {
    if (_parsedItems.isEmpty) return;

    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final payload = {
        'items': _parsedItems,
        'fileName': _selectedFileName ?? (_isPastingCsv ? 'pasted_parts.csv' : 'bulk_parts.xlsx'),
        'updateExisting': _updateExisting,
        'stockMode': _stockMode,
        'createStockMovements': _createStockMovements,
      };

      final res = await http.post(
        Uri.parse('${widget.baseUrl}/parts/bulk-import'),
        headers: {'Content-Type': 'application/json', ...widget.authHeaders},
        body: json.encode(payload),
      );

      if (res.statusCode == 200) {
        final result = json.decode(res.body);
        widget.onImportCompleted();

        if (mounted) {
          await showDialog(
            context: context,
            builder: (dCtx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF10B981), size: 26),
                  SizedBox(width: 10),
                  Text('Bulk Import Successful'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result['message'] ?? 'Successfully imported spare parts into catalog.',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 12),
                  _resultMetricRow('New Parts Created', '${result['createdCount'] ?? 0}', Colors.green),
                  _resultMetricRow('Existing Parts Updated', '${result['updatedCount'] ?? 0}', Colors.blue),
                  if ((result['skippedCount'] ?? 0) > 0)
                    _resultMetricRow('Skipped (Existing)', '${result['skippedCount']}', Colors.grey),
                  const SizedBox(height: 8),
                  const Text(
                    'All stock quantities and initial stock ledger transactions have been recorded.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(dCtx);
                    Navigator.pop(context);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        }
      } else {
        final err = json.decode(res.body);
        setState(() {
          _errorMessage = err['error'] ?? 'Import failed with status code ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error executing bulk import: $e';
      });
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Widget _resultMetricRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }

  void _downloadTemplate() {
    final templateUri = '${widget.baseUrl}/parts/import-template';
    openUrlInNewTab(templateUri);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
        decoration: const BoxDecoration(
          color: Color(0xFF0F4C81),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
        ),
        child: Row(
          children: [
            const Icon(Icons.file_upload_outlined, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bulk Import Spare Parts (Excel / CSV)',
                    style: TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Upload your price list or inventory spreadsheet to add multiple parts instantly',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _isImporting ? null : () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 840,
        height: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -------------------------------------------------------------
              // STEP 1: TEMPLATE & FILE UPLOAD
              // -------------------------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('1. Select Excel or CSV File', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A))),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      foregroundColor: const Color(0xFF0F4C81),
                      side: const BorderSide(color: Color(0xFF0F4C81)),
                    ),
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('Download CSV Sample Template', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    onPressed: _downloadTemplate,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Upload Drop Area
              InkWell(
                onTap: _isImporting || _isPreviewing ? null : _pickFile,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedFileName != null ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                      width: _selectedFileName != null ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _selectedFileName != null ? Icons.check_circle_outline : Icons.cloud_upload_outlined,
                        size: 40,
                        color: _selectedFileName != null ? const Color(0xFF10B981) : const Color(0xFF0F4C81),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedFileName != null
                            ? 'Selected: $_selectedFileName (${((_selectedFileSize ?? 0) / 1024).toStringAsFixed(1)} KB)'
                            : 'Click here to pick Excel (.xlsx, .xls) or CSV (.csv) file',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: _selectedFileName != null ? const Color(0xFF065F46) : const Color(0xFF0F4C81),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedFileName != null
                            ? 'Tap to select a different file'
                            : 'Supports Microsoft Excel (.xlsx, .xls) and Comma-Separated Values (.csv)',
                        style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Paste CSV toggle
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isPastingCsv = !_isPastingCsv;
                      if (!_isPastingCsv) _csvTextCtrl.clear();
                    });
                  },
                  icon: Icon(_isPastingCsv ? Icons.expand_less : Icons.expand_more, size: 16),
                  label: Text(_isPastingCsv ? 'Hide Text Input' : 'Or paste CSV / Spreadsheet text directly', style: const TextStyle(fontSize: 11.5)),
                ),
              ),

              if (_isPastingCsv) ...[
                const SizedBox(height: 4),
                TextField(
                  controller: _csvTextCtrl,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Paste CSV or Tab-Delimited Rows (include headers: Part Number, Description, Price, Stock...)',
                    border: OutlineInputBorder(),
                    hintText: 'Part Number,Description,Brand,Cost Price,Unit Price,Stock Quantity\nOIL-001,Oil Filter,Toyota,450,850,20\nBRK-002,Brake Pads,Brembo,3000,5000,10',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                    icon: const Icon(Icons.analytics_outlined, size: 14),
                    label: const Text('Parse & Preview Pasted Text', style: TextStyle(fontSize: 12)),
                    onPressed: _isPreviewing ? null : () => _requestPreview(csvText: _csvTextCtrl.text),
                  ),
                ),
              ],

              // Error notification
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!, style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
                      ),
                    ],
                  ),
                ),
              ],

              // Loading Preview indicator
              if (_isPreviewing) ...[
                const SizedBox(height: 24),
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(strokeWidth: 2.5),
                      SizedBox(height: 8),
                      Text('Analyzing columns and matching existing catalog parts...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],

              // -------------------------------------------------------------
              // STEP 2: PREVIEW METRICS & OPTIONS
              // -------------------------------------------------------------
              if (_previewData != null && !_isPreviewing) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text('2. Validation Summary & Options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A))),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _metricBadge('Total Rows', '$_totalRows', Colors.blueGrey),
                    const SizedBox(width: 10),
                    _metricBadge('Valid Parts', '${_parsedItems.length}', const Color(0xFF047857)),
                    const SizedBox(width: 10),
                    _metricBadge('New to Catalog', '$_newCount', const Color(0xFF1D4ED8)),
                    const SizedBox(width: 10),
                    _metricBadge('Existing (Matches)', '$_updateCount', const Color(0xFFB45309)),
                    if (_invalidRows.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      _metricBadge('Skipped / Empty', '${_invalidRows.length}', Colors.red),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // Import Rules Settings
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Update existing parts if Part Number already exists in catalog', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        subtitle: const Text('Updates selling price, cost price, shelf location, and adjusts stock count', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        value: _updateExisting,
                        onChanged: (val) => setState(() => _updateExisting = val ?? true),
                      ),
                      if (_updateExisting && _updateCount > 0) ...[
                        const Padding(
                          padding: EdgeInsets.only(left: 32, top: 4, bottom: 4),
                          child: Text('Stock Quantity Adjustment Mode for Existing Parts:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: () => setState(() => _stockMode = 'ADD'),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _stockMode == 'ADD' ? Icons.radio_button_checked : Icons.radio_button_off,
                                      size: 18,
                                      color: _stockMode == 'ADD' ? const Color(0xFF0F4C81) : Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('(+) Add to current stock (Received stock delivery)', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              InkWell(
                                onTap: () => setState(() => _stockMode = 'SET'),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _stockMode == 'SET' ? Icons.radio_button_checked : Icons.radio_button_off,
                                      size: 18,
                                      color: _stockMode == 'SET' ? const Color(0xFF0F4C81) : Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('(=) Overwrite stock quantity (Stocktake count)', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Record stock ledger movements for initial or updated stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        subtitle: const Text('Creates "RECEIVED" stock movements with reference "Bulk Import" for audit traceability', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        value: _createStockMovements,
                        onChanged: (val) => setState(() => _createStockMovements = val ?? true),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Preview Data Table
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Data Preview (First ${(_previewData!['preview'] as List).length} rows):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    Text('Columns automatically mapped from spreadsheet headers', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
                const SizedBox(height: 8),

                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 34,
                        dataRowMinHeight: 32,
                        dataRowMaxHeight: 36,
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                        columns: const [
                          DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                          DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                          DataColumn(label: Text('Part Number', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                          DataColumn(label: Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                          DataColumn(label: Text('Brand', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                          DataColumn(label: Text('Compatibility', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                          DataColumn(label: Text('Cost (KES)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                          DataColumn(label: Text('Retail (KES)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                          DataColumn(label: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                          DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                        ],
                        rows: (_previewData!['preview'] as List).map<DataRow>((item) {
                          final isEx = item['isExisting'] == true;
                          return DataRow(
                            cells: [
                              DataCell(Text('${item['rowNumber'] ?? ''}', style: const TextStyle(fontSize: 11))),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isEx ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: isEx ? const Color(0xFF93C5FD) : const Color(0xFFA7F3D0)),
                                  ),
                                  child: Text(
                                    isEx ? 'UPDATE' : 'NEW',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isEx ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(Text(item['partNumber'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                              DataCell(Text(item['description'] ?? '', style: const TextStyle(fontSize: 11.5))),
                              DataCell(Text(item['brand'] ?? '-', style: const TextStyle(fontSize: 11.5))),
                              DataCell(Text(item['compatibility'] ?? '-', style: const TextStyle(fontSize: 11.5))),
                              DataCell(Text((item['costPrice'] as num?)?.toStringAsFixed(0) ?? '0', style: const TextStyle(fontSize: 11.5))),
                              DataCell(Text((item['unitPrice'] as num?)?.toStringAsFixed(0) ?? '0', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                              DataCell(Text('${item['stockQuantity'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                              DataCell(Text(item['location'] ?? 'Main Store', style: const TextStyle(fontSize: 11.5))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.all(16),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F4C81),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: _isImporting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.file_upload, size: 18),
          label: Text(
            _isImporting
                ? 'Importing Parts...'
                : (_parsedItems.isNotEmpty
                    ? 'Import ${_parsedItems.length} Parts ($_newCount new, $_updateCount updates)'
                    : 'Select File to Import'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: _isImporting || _parsedItems.isEmpty ? null : _executeImport,
        ),
      ],
    );
  }

  Widget _metricBadge(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}
