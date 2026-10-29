import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'platform_launcher.dart';

class VehiclePhotoService {
  static const List<String> presetLabels = [
    '📷 Front View',
    '📷 Rear Bumper & Plate',
    '📷 Left Side Profile',
    '📷 Right Side Profile',
    '📷 Dashboard & Odometer',
    '📷 Interior & Valuables',
    '⚠️ Existing Scratch / Dent',
    '🔧 Engine Bay / Mechanical',
    '✅ Release Condition Proof',
    '📁 General Photo',
  ];

  /// Stretches and burns an immutable anti-dispute verification watermark banner
  /// directly into the image pixel data (Registration plate, Job Card #, Issue date, Timestamp).
  static Future<Uint8List> stampWatermarkOnImage({
    required Uint8List rawBytes,
    required String registrationNo,
    String? jobNumber,
    String? jobCreatedAt,
    required String label,
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

      // Top security accent line
      final stripePaint = Paint()..color = const Color(0xFF2563EB);
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
      final tp2 = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'TIMESTAMP: $timeStr   •   TAG: $cleanLabel   •   OFFICIAL WORKSHOP INTAKE RECORD',
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
      final finalImg = await picture.toImage(image.width, image.height);
      final byteData = await finalImg.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
      return rawBytes;
    } catch (e) {
      debugPrint('Failed to stamp watermark: $e');
      return rawBytes;
    }
  }

  /// Prompts user to pick an image file, stamps official timestamp & job card details,
  /// and uploads it as a verified vehicle photo.
  static Future<Map<String, dynamic>?> pickAndUploadPhoto({
    required BuildContext context,
    required String baseUrl,
    required String registrationNo,
    String? jobCardId,
    String? jobNumber,
    String? jobCreatedAt,
    String? defaultLabel,
  }) async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (files.isEmpty) return null;
      final PlatformFile file = files.first;
      final Uint8List rawBytes = await file.readAsBytes();
      if (rawBytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(backgroundColor: Colors.red, content: Text('Could not read image bytes.')),
          );
        }
        return null;
      }

      String selectedLabel = defaultLabel ?? presetLabels.first;
      String category = selectedLabel.contains('Scratch') ? 'DAMAGE' : (selectedLabel.contains('Release') ? 'RELEASE' : 'PHOTO');
      final notesCtrl = TextEditingController();

      // Stamp official anti-dispute watermark with vehicle reg, job card #, and date/time
      Uint8List bytes = await stampWatermarkOnImage(
        rawBytes: rawBytes,
        registrationNo: registrationNo,
        jobNumber: jobNumber,
        jobCreatedAt: jobCreatedAt,
        label: selectedLabel,
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
                  width: 460,
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
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, size: 15, color: Color(0xFF16A34A)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Timestamp & Job # embedded on photo for customer dispute proof',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text('Photo Category *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: selectedLabel,
                          isExpanded: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          items: presetLabels
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
                              );
                              setDlg(() {
                                selectedLabel = v;
                                bytes = updatedBytes;
                                category = v.contains('Scratch') ? 'DAMAGE' : (v.contains('Release') ? 'RELEASE' : 'PHOTO');
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Notes / Specific Details (Optional)',
                            hintText: 'e.g. Minor paint scratch near left front door',
                            border: OutlineInputBorder(),
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
          'filename': 'stamped_${file.name.replaceAll(RegExp(r'\.[^\.]+$'), '')}.png',
          'registrationNo': registrationNo.trim().toUpperCase(),
          'jobCardId': jobCardId,
          'jobNumber': jobNumber,
          'jobCreatedAt': jobCreatedAt,
          'label': selectedLabel,
          'category': category,
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
    final streamUrl = key.isNotEmpty ? '$baseUrl/storage/file?key=${Uri.encodeComponent(key)}' : (photo['url']?.toString() ?? '');
    final directUrl = photo['url']?.toString() ?? photo['publicUrl']?.toString() ?? '';

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
                        const Icon(Icons.verified, size: 14, color: Color(0xFF4ADE80)),
                        const SizedBox(width: 4),
                        Text(
                          'Official Intake Proof • $regNo',
                          style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11, fontWeight: FontWeight.bold),
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
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey.shade100),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sticky_note_2_outlined, size: 16, color: Color(0xFF2563EB)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(notes, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: const Text('📷 Verified Intake Photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
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
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      tooltip: 'Delete Photo',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (delCtx) => AlertDialog(
                            title: const Text('Delete Photo?'),
                            content: const Text('Are you sure you want to permanently delete this photo?'),
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

  /// Builds a card thumbnail widget representing a vehicle photo
  static Widget buildPhotoCard({
    required Map<String, dynamic> photo,
    required String baseUrl,
    required VoidCallback onTap,
    VoidCallback? onDelete,
    double width = 120,
    double height = 120,
  }) {
    final key = photo['key']?.toString() ?? '';
    final label = photo['label']?.toString() ?? 'Vehicle Photo';
    final uploadedAt = photo['uploadedAt']?.toString() ?? '';
    final jobNumber = photo['jobNumber']?.toString() ?? '';
    final streamUrl = key.isNotEmpty ? '$baseUrl/storage/file?key=${Uri.encodeComponent(key)}' : (photo['url']?.toString() ?? '');
    final isDamage = (photo['category'] ?? '').toString().toUpperCase() == 'DAMAGE';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: height + 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDamage ? Colors.red.shade300 : Colors.blueGrey.shade200),
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
            // Thumbnail image with timestamp watermark overlay
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                  child: Container(
                    height: height - 16,
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
                label.replaceAll('📷 ', '').replaceAll('⚠️ ', '').replaceAll('🔧 ', '').replaceAll('✅ ', ''),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDamage ? Colors.red.shade800 : const Color(0xFF0F172A),
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
