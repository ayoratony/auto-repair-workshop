import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'image_picker_helper.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'platform_launcher.dart';

class VehiclePhotoService {
  // Category constants
  static const String categoryIntake = 'INTAKE';
  static const String categoryFinding = 'ADDITIONAL_FINDING';
  static const String categoryRelease = 'RELEASE';

  // Preset labels per category
  static const List<String> intakeLabels = [
    '📷 Front View',
    '📷 Rear Bumper & Plate',
    '📷 Left Side Profile',
    '📷 Right Side Profile',
    '📷 Dashboard & Odometer Proof',
    '📷 Interior & Valuables Check',
    '⚠️ Existing Scratch / Dent / Body Damage',
    '🔧 Engine Bay / Fluid Leaks',
    '📁 General Intake Photo',
  ];

  static const List<String> findingLabels = [
    '🔍 Worn Brake Pads / Scored Discs',
    '🔍 Oil / Coolant Fluid Leak',
    '🔍 Suspension / Bushing / Ball Joint Tear',
    '🔍 Damaged Belt / Pulley / Alternator',
    '🔍 Electrical / Melted Wiring Fault',
    '🔍 Exhaust / Underbody Rust & Hole',
    '⚠️ Unexpected Mechanical Hazard',
    '🔧 Additional Repair Recommended',
  ];

  static const List<String> releaseLabels = [
    '✅ Completed Work Evidence',
    '✅ Replaced Old Parts Display',
    '✅ Final Clean Delivery Condition',
    '✅ Customer Handover Signature/Proof',
  ];

  static const List<String> presetLabels = intakeLabels;

  static List<String> getLabelsForCategory(String category) {
    switch (category) {
      case categoryFinding:
        return findingLabels;
      case categoryRelease:
        return releaseLabels;
      case categoryIntake:
      default:
        return intakeLabels;
    }
  }

  /// Stretches and burns an immutable anti-dispute verification watermark banner
  /// directly into the image pixel data (Registration plate, Job Card #, Issue date, Timestamp, Category Seal).
  static Future<Uint8List> stampWatermarkOnImage({
    required Uint8List rawBytes,
    required String registrationNo,
    String? jobNumber,
    String? jobCreatedAt,
    required String label,
    String category = categoryIntake,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final ui.Image image = frame.image;

      final width = image.width.toDouble();
      final height = image.height.toDouble();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

      // 1. Draw base photo
      canvas.drawImage(image, Offset.zero, Paint());

      // 2. Compute proportional banner dimensions at bottom of image
      final bannerHeight = (height * 0.09).clamp(56.0, 120.0);
      final bannerRect = Rect.fromLTWH(0, height - bannerHeight, width, bannerHeight);

      // Deep dark navy backdrop for high-contrast readability
      final bgPaint = Paint()..color = const Color(0xF00A0F1D);
      canvas.drawRect(bannerRect, bgPaint);

      // Top security accent line (Blue for Intake, Amber for Finding, Green for Release)
      final stripeColor = category == categoryFinding
          ? const Color(0xFFF59E0B) // Amber
          : (category == categoryRelease
              ? const Color(0xFF10B981) // Emerald Green
              : const Color(0xFF2563EB)); // Electric Blue
      final stripePaint = Paint()..color = stripeColor;
      canvas.drawRect(
        Rect.fromLTWH(0, height - bannerHeight, width, (bannerHeight * 0.04).clamp(2.5, 4.0)),
        stripePaint,
      );

      // Format date and time
      final now = DateTime.now();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
      final ampm = now.hour >= 12 ? 'PM' : 'AM';
      final min = now.minute.toString().padLeft(2, '0');
      final sec = now.second.toString().padLeft(2, '0');
      final timeStr = '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year} $hour:$min:$sec $ampm';

      final cleanReg = registrationNo.trim().toUpperCase();
      final cleanJob = (jobNumber != null && jobNumber.trim().isNotEmpty) ? jobNumber.trim() : 'INTAKE';
      final issuePart = (jobCreatedAt != null && jobCreatedAt.trim().isNotEmpty)
          ? '  •  Issued: ${_formatDateShort(jobCreatedAt.trim())}'
          : '';
      final cleanLabel = label.replaceAll(RegExp(r'[^\w\s\/\-\&]'), '').trim();

      // Proportional font sizing
      final titleSize = (bannerHeight * 0.32).clamp(13.0, 26.0);
      final subSize = (bannerHeight * 0.22).clamp(10.0, 18.0);
      final paddingH = (width * 0.025).clamp(14.0, 32.0);

      // Row 1: Registration Plate + Job Card # + Issue Date
      final tp1 = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'VEHICLE: $cleanReg   ',
              style: TextStyle(
                color: const Color(0xFF38BDF8),
                fontSize: titleSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            TextSpan(
              text: 'JOB: $cleanJob$issuePart',
              style: TextStyle(
                color: Colors.white,
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: width - (paddingH * 2));

      final line1Y = height - bannerHeight + (bannerHeight * 0.16);
      tp1.paint(canvas, Offset(paddingH, line1Y));

      // Row 2: Official Timestamp & Condition Category Seal
      final categoryBadge = category == categoryFinding
          ? 'DISCOVERED DURING REPAIR (SUPPLEMENTAL FINDING)'
          : (category == categoryRelease
              ? 'FINAL RELEASE & DELIVERY PROOF'
              : 'OFFICIAL INTAKE RECORD (LOCKED)');

      final tp2 = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'TIMESTAMP: $timeStr   •   TAG: $cleanLabel   •   $categoryBadge',
              style: TextStyle(
                color: const Color(0xFFCBD5E1),
                fontSize: subSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: width - (paddingH * 2));

      final line2Y = height - bannerHeight + (bannerHeight * 0.56);
      tp2.paint(canvas, Offset(paddingH, line2Y));

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
      return rawBytes;
    } catch (e) {
      debugPrint('Failed to stamp watermark: $e');
      return rawBytes;
    }
  }

  /// Prompts user to pick an image file, choose category (Intake vs Additional Finding vs Release),
  /// stamps official timestamp & job card details, and uploads it as a verified vehicle photo.
  static Future<Map<String, dynamic>?> pickAndUploadPhoto({
    required BuildContext context,
    required String baseUrl,
    required String registrationNo,
    String? jobCardId,
    String? jobNumber,
    String? jobCreatedAt,
    String? defaultCategory,
    String? defaultLabel,
  }) async {
    try {
      final PickedFileData? file = await ImagePickerHelper.pickImage();
      if (file == null) return null;

      final Uint8List rawBytes = file.bytes;
      if (rawBytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(backgroundColor: Colors.red, content: Text('Could not read image bytes.')),
          );
        }
        return null;
      }

      String currentCategory = defaultCategory ?? categoryIntake;
      List<String> currentLabels = getLabelsForCategory(currentCategory);
      String selectedLabel = defaultLabel ?? currentLabels.first;
      final notesCtrl = TextEditingController();

      // Stamp official anti-dispute watermark with vehicle reg, job card #, category, and date/time
      Uint8List bytes = await stampWatermarkOnImage(
        rawBytes: rawBytes,
        registrationNo: registrationNo,
        jobNumber: jobNumber,
        jobCreatedAt: jobCreatedAt,
        label: selectedLabel,
        category: currentCategory,
      );

      bool confirmed = false;

      if (!context.mounted) return null;
      confirmed = await showDialog<bool>(
            context: context,
            builder: (dlgCtx) => StatefulBuilder(
              builder: (dlgCtx, setDlg) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFF1E3A8A).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.verified_outlined, color: Color(0xFF1E3A8A)),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Vehicle Photo & Timestamp Stamp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image Thumbnail Preview with Watermark Stamped
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            height: 190,
                            width: double.infinity,
                            color: Colors.black12,
                            child: Image.memory(
                              bytes,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Categorization Toggle
                        const Text('Select Category *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                avatar: const Icon(Icons.shield_outlined, size: 14),
                                label: const Text('🛡️ Intake', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                selected: currentCategory == categoryIntake,
                                selectedColor: const Color(0xFFDBEAFE),
                                onSelected: (sel) async {
                                  if (sel) {
                                    final newLabels = getLabelsForCategory(categoryIntake);
                                    final newLbl = newLabels.first;
                                    final updatedBytes = await stampWatermarkOnImage(
                                      rawBytes: rawBytes,
                                      registrationNo: registrationNo,
                                      jobNumber: jobNumber,
                                      jobCreatedAt: jobCreatedAt,
                                      label: newLbl,
                                      category: categoryIntake,
                                    );
                                    setDlg(() {
                                      currentCategory = categoryIntake;
                                      currentLabels = newLabels;
                                      selectedLabel = newLbl;
                                      bytes = updatedBytes;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ChoiceChip(
                                avatar: const Icon(Icons.search, size: 14),
                                label: const Text('🔍 Finding', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                selected: currentCategory == categoryFinding,
                                selectedColor: const Color(0xFFFEF3C7),
                                onSelected: (sel) async {
                                  if (sel) {
                                    final newLabels = getLabelsForCategory(categoryFinding);
                                    final newLbl = newLabels.first;
                                    final updatedBytes = await stampWatermarkOnImage(
                                      rawBytes: rawBytes,
                                      registrationNo: registrationNo,
                                      jobNumber: jobNumber,
                                      jobCreatedAt: jobCreatedAt,
                                      label: newLbl,
                                      category: categoryFinding,
                                    );
                                    setDlg(() {
                                      currentCategory = categoryFinding;
                                      currentLabels = newLabels;
                                      selectedLabel = newLbl;
                                      bytes = updatedBytes;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ChoiceChip(
                                avatar: const Icon(Icons.check_circle_outline, size: 14),
                                label: const Text('🏁 Release', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                selected: currentCategory == categoryRelease,
                                selectedColor: const Color(0xFFD1FAE5),
                                onSelected: (sel) async {
                                  if (sel) {
                                    final newLabels = getLabelsForCategory(categoryRelease);
                                    final newLbl = newLabels.first;
                                    final updatedBytes = await stampWatermarkOnImage(
                                      rawBytes: rawBytes,
                                      registrationNo: registrationNo,
                                      jobNumber: jobNumber,
                                      jobCreatedAt: jobCreatedAt,
                                      label: newLbl,
                                      category: categoryRelease,
                                    );
                                    setDlg(() {
                                      currentCategory = categoryRelease;
                                      currentLabels = newLabels;
                                      selectedLabel = newLbl;
                                      bytes = updatedBytes;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Security notice banner based on chosen category
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: currentCategory == categoryFinding
                                ? const Color(0xFFFFFBEB)
                                : (currentCategory == categoryRelease ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: currentCategory == categoryFinding
                                  ? const Color(0xFFFDE68A)
                                  : (currentCategory == categoryRelease ? const Color(0xFFA7F3D0) : const Color(0xFFBFDBFE)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                currentCategory == categoryFinding
                                    ? Icons.info_outline
                                    : (currentCategory == categoryRelease ? Icons.task_alt : Icons.lock_outline),
                                size: 14,
                                color: currentCategory == categoryFinding
                                    ? Colors.amber.shade900
                                    : (currentCategory == categoryRelease ? Colors.green.shade900 : const Color(0xFF1E3A8A)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  currentCategory == categoryFinding
                                      ? 'Supplemental finding discovered during repair. Stamped separately from arrival intake.'
                                      : (currentCategory == categoryRelease
                                          ? 'Proof of completed repairs and vehicle delivery condition.'
                                          : 'Baseline intake photo: Permanently locked upon job issuance to prevent tampering.'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: currentCategory == categoryFinding
                                        ? Colors.amber.shade900
                                        : (currentCategory == categoryRelease ? Colors.green.shade900 : const Color(0xFF1E3A8A)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        const Text('Photo Tag / View *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          key: ValueKey(currentCategory),
                          initialValue: currentLabels.contains(selectedLabel) ? selectedLabel : currentLabels.first,
                          isExpanded: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          items: currentLabels
                              .map((lbl) => DropdownMenuItem(value: lbl, child: Text(lbl, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) async {
                            if (v != null) {
                              final updatedBytes = await stampWatermarkOnImage(
                                rawBytes: rawBytes,
                                registrationNo: registrationNo,
                                jobNumber: jobNumber,
                                jobCreatedAt: jobCreatedAt,
                                label: v,
                                category: currentCategory,
                              );
                              setDlg(() {
                                selectedLabel = v;
                                bytes = updatedBytes;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notesCtrl,
                          decoration: InputDecoration(
                            labelText: currentCategory == categoryFinding
                                ? 'Mechanic Findings & Recommended Fix *'
                                : (currentCategory == categoryRelease ? 'Release & Handover Notes' : 'Intake Notes / Scratch Location (Optional)'),
                            hintText: currentCategory == categoryFinding
                                ? 'e.g. Brake pads worn to 2mm, disc grooved beyond safe thickness'
                                : 'e.g. Minor paint scratch near left front door',
                            border: const OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'File: ${file.name} (${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB) • Vehicle: $registrationNo',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancel')),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                    label: const Text('Upload Photo', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => Navigator.pop(dlgCtx, true),
                  ),
                ],
              ),
            ),
          ) ??
          false;

      if (!confirmed) return null;

      // Show uploading snackbar
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            content: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 12),
                Text('Uploading vehicle photo with timestamp stamp...'),
              ],
            ),
          ),
        );
      }

      // Convert to base64
      final base64String = 'data:image/png;base64,${base64Encode(bytes)}';

      final res = await http.post(
        Uri.parse('$baseUrl/vehicles/upload-image'),
        headers: AuthService.instance.authHeaders,
        body: json.encode({
          'image': base64String,
          'filename': file.name,
          'registrationNo': registrationNo.trim().toUpperCase(),
          'jobCardId': jobCardId,
          'jobNumber': jobNumber,
          'jobCreatedAt': jobCreatedAt,
          'label': selectedLabel,
          'category': currentCategory,
          'notes': notesCtrl.text.trim(),
        }),
      );

      if (res.statusCode == 201 || res.statusCode == 200) {
        final data = json.decode(res.body);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('✓ Vehicle photo uploaded successfully.'),
            ),
          );
        }
        return Map<String, dynamic>.from(data['photo']);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text('Upload failed: ${res.body}')),
          );
        }
        return null;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error uploading photo: $e')),
        );
      }
      return null;
    }
  }

  /// High-resolution full screen dialog for viewing an uploaded photo
  static void showFullPhotoDialog({
    required BuildContext context,
    required String baseUrl,
    required Map<String, dynamic> photo,
    VoidCallback? onDelete,
  }) {
    final key = photo['key']?.toString() ?? '';
    final label = photo['label']?.toString() ?? 'Vehicle Photo';
    final notes = photo['notes']?.toString() ?? '';
    final uploadedAt = photo['uploadedAt']?.toString() ?? '';
    final uploadedBy = photo['uploadedBy']?.toString() ?? '';
    final regNo = photo['registrationNo']?.toString() ?? '';
    final jobNumber = photo['jobNumber']?.toString() ?? '';
    final jobCreatedAt = photo['jobCreatedAt']?.toString() ?? '';
    final category = (photo['category'] ?? categoryIntake).toString().toUpperCase();
    final isFinding = category == categoryFinding;
    final isRelease = category == categoryRelease;
    // ignore: unused_local_variable
    final isIntake = !isFinding && !isRelease;

    final streamUrl = key.isNotEmpty ? '$baseUrl/storage/file?key=${Uri.encodeComponent(key)}' : (photo['url']?.toString() ?? '');
    final directUrl = photo['url']?.toString() ?? photo['publicUrl']?.toString() ?? '';

    final isAdmin = AuthService.instance.isManager;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: 760,
          constraints: const BoxConstraints(maxHeight: 820),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF1E3A8A).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(regNo, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A), fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 10),

              // Image display
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Container(
                      width: double.infinity,
                      color: Colors.black,
                      child: Image.network(
                        streamUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (c, child, progress) {
                          if (progress == null) return child;
                          return const Center(child: CircularProgressIndicator(color: Colors.white));
                        },
                        errorBuilder: (c, err, stack) {
                          if (directUrl.isNotEmpty && directUrl != streamUrl) {
                            return Image.network(
                              directUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _errorPlaceholder(),
                            );
                          }
                          return _errorPlaceholder();
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Official Verification Stamp Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time_filled, size: 15, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 6),
                        Text(
                          'Captured: ${_formatDate(uploadedAt)}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (jobNumber.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.assignment_outlined, size: 14, color: Color(0xFFFBBF24)),
                          const SizedBox(width: 4),
                          Text(
                            'Job Card: $jobNumber${jobCreatedAt.isNotEmpty ? " (Issued: ${_formatDateShort(jobCreatedAt)})" : ""}',
                            style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFinding ? Icons.search : (isRelease ? Icons.check_circle : Icons.shield),
                          size: 14,
                          color: isFinding ? const Color(0xFFFBBF24) : (isRelease ? const Color(0xFF34D399) : const Color(0xFF4ADE80)),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isFinding ? 'Finding During Repair' : (isRelease ? 'Release Proof' : 'Official Intake Proof'),
                          style: TextStyle(
                            color: isFinding ? const Color(0xFFFDE68A) : (isRelease ? const Color(0xFFA7F3D0) : const Color(0xFF86EFAC)),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Metadata & Notes
              if (notes.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isFinding ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isFinding ? const Color(0xFFFDE68A) : Colors.blueGrey.shade100),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isFinding ? Icons.warning_amber_rounded : Icons.sticky_note_2_outlined,
                        size: 16,
                        color: isFinding ? const Color(0xFFD97706) : const Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          notes,
                          style: TextStyle(
                            fontSize: 13,
                            color: isFinding ? const Color(0xFF92400E) : const Color(0xFF1E293B),
                            fontWeight: isFinding ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isFinding ? const Color(0xFFFEF3C7) : (isRelease ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF)),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isFinding ? const Color(0xFFFCD34D) : (isRelease ? const Color(0xFFA7F3D0) : const Color(0xFFBFDBFE)),
                      ),
                    ),
                    child: Text(
                      isFinding
                          ? '🔍 Finding During Repair'
                          : (isRelease ? '🏁 Final Release Proof' : '🛡️ Locked Intake Record'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isFinding
                            ? const Color(0xFF92400E)
                            : (isRelease ? const Color(0xFF047857) : const Color(0xFF1E3A8A)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (uploadedBy.isNotEmpty)
                    Text(
                      'Recorded by: $uploadedBy',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  const Spacer(),
                  if (directUrl.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('View Full Image', style: TextStyle(fontSize: 11.5)),
                      onPressed: () => PlatformLauncher.openUrl(directUrl),
                    ),
                  if (onDelete != null)
                    if (isIntake && !isAdmin)
                      Tooltip(
                        message: 'Intake baseline photos are legally locked to protect both customer and workshop against tampering.',
                        child: IconButton(
                          icon: const Icon(Icons.lock, color: Colors.grey, size: 20),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Colors.orange,
                                content: Text('Intake photos are legally locked. Only an Administrator can authorize deletion.'),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        tooltip: isIntake ? 'Delete (Admin Override - Logged to Audit)' : 'Delete Photo',
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: ctx,
                            builder: (delCtx) => AlertDialog(
                              title: Text(isIntake ? 'Admin Override: Delete Intake Photo?' : 'Delete Photo?'),
                              content: Text(isIntake
                                  ? 'Warning: This photo is an official arrival intake record. Deleting it will be permanently recorded in the Job Card Audit Log.'
                                  : 'Are you sure you want to permanently delete this photo?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(delCtx, false), child: const Text('Cancel')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                  onPressed: () => Navigator.pop(delCtx, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            Navigator.pop(ctx);
                            onDelete();
                          }
                        },
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _errorPlaceholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
          SizedBox(height: 8),
          Text('Failed to load image', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $hour:$min $ampm';
    } catch (_) {
      return iso;
    }
  }

  static String _formatTimeShort(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${months[dt.month - 1]} $hour:$min $ampm';
    } catch (_) {
      return '';
    }
  }

  static String _formatDateShort(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  /// Compact photo thumbnail card with category badges and watermarked timestamp
  static Widget buildPhotoCard({
    required Map<String, dynamic> photo,
    required String baseUrl,
    required VoidCallback onTap,
    VoidCallback? onDelete,
    double width = 125,
    double height = 120,
  }) {
    final key = photo['key']?.toString() ?? '';
    final label = photo['label']?.toString() ?? 'Vehicle Photo';
    final uploadedAt = photo['uploadedAt']?.toString() ?? '';
    final jobNumber = photo['jobNumber']?.toString() ?? '';
    final streamUrl = key.isNotEmpty ? '$baseUrl/storage/file?key=${Uri.encodeComponent(key)}' : (photo['url']?.toString() ?? '');
    final category = (photo['category'] ?? categoryIntake).toString().toUpperCase();
    final isFinding = category == categoryFinding;
    final isRelease = category == categoryRelease;
    // ignore: unused_local_variable
    final isIntake = !isFinding && !isRelease;

    final borderColor = isFinding
        ? Colors.amber.shade600
        : (isRelease ? Colors.green.shade600 : const Color(0xFF93C5FD));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: height + 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: isFinding ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail image with category chip & timestamp watermark overlay
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                  child: Container(
                    height: height - 12,
                    width: width,
                    color: const Color(0xFFF1F5F9),
                    child: Image.network(
                      streamUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (c, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
                      },
                      errorBuilder: (c, err, stack) {
                        final direct = photo['url']?.toString() ?? '';
                        if (direct.isNotEmpty && direct != streamUrl) {
                          return Image.network(
                            direct,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 28, color: Colors.grey),
                          );
                        }
                        return const Icon(Icons.broken_image, size: 28, color: Colors.grey);
                      },
                    ),
                  ),
                ),

                // Category pill on top-left
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isFinding
                          ? const Color(0xFFD97706)
                          : (isRelease ? const Color(0xFF059669) : const Color(0xFF1E3A8A)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isFinding ? '🔍 Finding' : (isRelease ? '🏁 Release' : '🛡️ Intake'),
                      style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                // Timestamp pill at bottom of image
                if (uploadedAt.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_filled, size: 8, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 2.5),
                          Expanded(
                            child: Text(
                              _formatTimeShort(uploadedAt),
                              style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Delete button
                if (onDelete != null)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: InkWell(
                      onTap: onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),

            // Caption & Label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                label.replaceAll('📷 ', '').replaceAll('⚠️ ', '').replaceAll('🔧 ', '').replaceAll('✅ ', '').replaceAll('🔍 ', ''),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isFinding
                      ? const Color(0xFFB45309)
                      : (isRelease ? const Color(0xFF047857) : const Color(0xFF0F172A)),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (jobNumber.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'Job: $jobNumber',
                  style: const TextStyle(fontSize: 8.5, color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
