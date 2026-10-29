import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'platform_launcher.dart';

class VehiclePhotoService {
  static const List<String> presetLabels = [
    '📷 Front View (Security)',
    '📷 Rear Bumper & Plate',
    '📷 Left Side Profile',
    '📷 Right Side Profile',
    '📷 Dashboard & Odometer',
    '📷 Interior & Valuables',
    '⚠️ Existing Scratch / Dent',
    '🔧 Engine Bay / Mechanical',
    '✅ Release Condition Proof',
    '📁 General Condition Photo',
  ];

  /// Prompts user to pick an image file, choose a security tag & notes,
  /// and uploads it to Neon S3 (car-pics bucket).
  static Future<Map<String, dynamic>?> pickAndUploadPhoto({
    required BuildContext context,
    required String baseUrl,
    required String registrationNo,
    String? jobCardId,
    String? defaultLabel,
  }) async {
    try {
      final PlatformFile? file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (file == null) return null;
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(backgroundColor: Colors.red, content: Text('Could not read image bytes.')),
          );
        }
        return null;
      }

      // Show Tag & Details Confirmation Dialog before uploading
      String selectedLabel = defaultLabel ?? presetLabels.first;
      String category = selectedLabel.contains('Scratch') ? 'DAMAGE' : 'SECURITY';
      final notesCtrl = TextEditingController();
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
                      child: const Icon(Icons.shield_outlined, color: Color(0xFF1E3A8A)),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Vehicle Security Photo (Neon S3)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 440,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image Thumbnail Preview
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            height: 180,
                            width: double.infinity,
                            color: Colors.black12,
                            child: Image.memory(
                              bytes,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text('Photo Category & Security Tag *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: selectedLabel,
                          isExpanded: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          items: presetLabels
                              .map((lbl) => DropdownMenuItem(value: lbl, child: Text(lbl, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDlg(() {
                                selectedLabel = v;
                                category = v.contains('Scratch') ? 'DAMAGE' : (v.contains('Release') ? 'RELEASE' : 'SECURITY');
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Condition Notes / Specific Details (Optional)',
                            hintText: 'e.g. Minor paint scratch near left front door',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'File: ${file.name} (${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB) \u2022 Target: Neon S3',
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
                    label: const Text('Upload to Neon S3', style: TextStyle(fontWeight: FontWeight.bold)),
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
                Text('Uploading vehicle security photo to Neon S3...'),
              ],
            ),
          ),
        );
      }

      // Convert to base64
      final mime = file.extension?.toLowerCase() == 'png'
          ? 'image/png'
          : (file.extension?.toLowerCase() == 'webp' ? 'image/webp' : 'image/jpeg');
      final base64String = 'data:$mime;base64,${base64Encode(bytes)}';

      final res = await http.post(
        Uri.parse('$baseUrl/vehicles/upload-image'),
        headers: AuthService.instance.authHeaders,
        body: json.encode({
          'image': base64String,
          'filename': file.name,
          'registrationNo': registrationNo.trim().toUpperCase(),
          'jobCardId': jobCardId,
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
              content: Text('✓ Vehicle security photo stored securely on Neon S3.'),
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
    final label = photo['label']?.toString() ?? 'Security Photo';
    final notes = photo['notes']?.toString() ?? '';
    final uploadedAt = photo['uploadedAt']?.toString() ?? '';
    final uploadedBy = photo['uploadedBy']?.toString() ?? '';
    final regNo = photo['registrationNo']?.toString() ?? '';
    final streamUrl = key.isNotEmpty ? '$baseUrl/storage/file?key=${Uri.encodeComponent(key)}' : (photo['url']?.toString() ?? '');
    final directUrl = photo['url']?.toString() ?? photo['publicUrl']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: 720,
          constraints: const BoxConstraints(maxHeight: 780),
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
                    child: const Text('☁️ Neon S3 Object Storage', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                  ),
                  const SizedBox(width: 8),
                  if (uploadedAt.isNotEmpty)
                    Text(
                      'Uploaded: ${_formatDate(uploadedAt)}${uploadedBy.isNotEmpty ? " by $uploadedBy" : ""}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  const Spacer(),
                  if (directUrl.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('Open Direct S3 URL', style: TextStyle(fontSize: 11.5)),
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
                            title: const Text('Delete Security Photo?'),
                            content: const Text('Are you sure you want to permanently delete this photo from Neon S3?'),
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
          Text('Failed to load image from Neon S3', style: TextStyle(color: Colors.white70)),
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
    final label = photo['label']?.toString() ?? 'Security Photo';
    final streamUrl = key.isNotEmpty ? '$baseUrl/storage/file?key=${Uri.encodeComponent(key)}' : (photo['url']?.toString() ?? '');
    final isDamage = (photo['category'] ?? '').toString().toUpperCase() == 'DAMAGE';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: height + 36,
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
            // Thumbnail image
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
                Positioned(
                  bottom: 2,
                  left: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(4)),
                    child: const Text('Neon S3', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            // Caption & Label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                label.replaceAll('📷 ', '').replaceAll('⚠️ ', '').replaceAll('🔧 ', '').replaceAll('✅ ', ''),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isDamage ? Colors.red.shade800 : const Color(0xFF0F172A),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
