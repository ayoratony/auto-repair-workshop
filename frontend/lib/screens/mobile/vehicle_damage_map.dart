import 'dart:math' as math;
import 'package:flutter/material.dart';

enum DamageType { dent, scratch, cut }

enum VehicleBodyType {
  sedan('Sedan / Saloon', Icons.directions_car),
  suv('SUV / Wagon', Icons.directions_car_filled),
  pickup('Pickup / Double Cab', Icons.fire_truck_outlined),
  lorry('Lorry / Truck', Icons.local_shipping),
  van('Van / Minibus', Icons.airport_shuttle);

  final String label;
  final IconData icon;
  const VehicleBodyType(this.label, this.icon);
}

enum VehicleViewAngle {
  front('Front', 0),
  left('Left Side', 90),
  rear('Rear', 180),
  right('Right Side', 270),
  top('Top / Roof', 360);

  final String label;
  final double defaultDegrees;
  const VehicleViewAngle(this.label, this.defaultDegrees);
}

class DamageMarker {
  /// Normalized X coordinate (0.0 to 1.0) so positions match 100% across Mobile & Web screens
  final double nx;

  /// Normalized Y coordinate (0.0 to 1.0)
  final double ny;

  final DamageType type;
  final VehicleViewAngle viewAngle;

  DamageMarker({
    required this.nx,
    required this.ny,
    required this.type,
    this.viewAngle = VehicleViewAngle.left,
  });

  Map<String, dynamic> toJson() => {
        'nx': nx,
        'ny': ny,
        'type': type.name,
        'viewAngle': viewAngle.name,
      };

  factory DamageMarker.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type']?.toString() ?? 'dent';
    final dmgType = DamageType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => DamageType.dent,
    );

    final angleStr = json['viewAngle']?.toString() ?? 'left';
    final angle = VehicleViewAngle.values.firstWhere(
      (e) => e.name == angleStr,
      orElse: () => VehicleViewAngle.left,
    );

    // Support both normalized (nx, ny in 0..1) and legacy pixel (x, y) coordinates
    double parsedNx;
    double parsedNy;
    if (json['nx'] != null && json['ny'] != null) {
      parsedNx = (json['nx'] as num).toDouble().clamp(0.0, 1.0);
      parsedNy = (json['ny'] as num).toDouble().clamp(0.0, 1.0);
    } else {
      final rawX = (json['x'] as num?)?.toDouble() ?? 150.0;
      final rawY = (json['y'] as num?)?.toDouble() ?? 130.0;
      parsedNx = (rawX > 1.0 ? rawX / 340.0 : rawX).clamp(0.05, 0.95);
      parsedNy = (rawY > 1.0 ? rawY / 260.0 : rawY).clamp(0.05, 0.95);
    }

    return DamageMarker(
      nx: parsedNx,
      ny: parsedNy,
      type: dmgType,
      viewAngle: angle,
    );
  }
}

class VehicleDamageMap extends StatefulWidget {
  final List<DamageMarker>? initialMarkers;
  final VehicleBodyType initialBodyType;
  final ValueChanged<List<DamageMarker>>? onMarkersChanged;
  final ValueChanged<VehicleBodyType>? onBodyTypeChanged;
  final bool readOnly;

  const VehicleDamageMap({
    Key? key,
    this.initialMarkers,
    this.initialBodyType = VehicleBodyType.sedan,
    this.onMarkersChanged,
    this.onBodyTypeChanged,
    this.readOnly = false,
  }) : super(key: key);

  @override
  State<VehicleDamageMap> createState() => _VehicleDamageMapState();
}

class _VehicleDamageMapState extends State<VehicleDamageMap> {
  late List<DamageMarker> _markers;
  late VehicleBodyType _bodyType;
  DamageType _selectedType = DamageType.dent;
  VehicleViewAngle _currentAngle = VehicleViewAngle.front;
  double _rotationDegrees = 0.0; // 0=Front, 90=Left, 180=Rear, 270=Right

  @override
  void initState() {
    super.initState();
    _markers = widget.initialMarkers != null ? List.from(widget.initialMarkers!) : [];
    _bodyType = widget.initialBodyType;
    if (_markers.isNotEmpty) {
      _currentAngle = _markers.first.viewAngle;
      _rotationDegrees = _currentAngle.defaultDegrees % 360;
    }
  }

  @override
  void didUpdateWidget(covariant VehicleDamageMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialBodyType != widget.initialBodyType) {
      _bodyType = widget.initialBodyType;
    }
  }

  void _addMarkerNormalized(Offset localPos, Size boxSize) {
    if (widget.readOnly) return;
    if (boxSize.width <= 0 || boxSize.height <= 0) return;

    final nx = (localPos.dx / boxSize.width).clamp(0.03, 0.97);
    final ny = (localPos.dy / boxSize.height).clamp(0.03, 0.97);

    setState(() {
      _markers.add(
        DamageMarker(
          nx: nx,
          ny: ny,
          type: _selectedType,
          viewAngle: _currentAngle,
        ),
      );
    });
    widget.onMarkersChanged?.call(_markers);
  }

  void _clearMarkers() {
    if (widget.readOnly) return;
    setState(() {
      _markers.clear();
    });
    widget.onMarkersChanged?.call(_markers);
  }

  void _onRotationSliderChanged(double deg) {
    setState(() {
      _rotationDegrees = deg;
      if (deg >= 315 || deg < 45) {
        _currentAngle = VehicleViewAngle.front;
      } else if (deg >= 45 && deg < 135) {
        _currentAngle = VehicleViewAngle.left;
      } else if (deg >= 135 && deg < 225) {
        _currentAngle = VehicleViewAngle.rear;
      } else {
        _currentAngle = VehicleViewAngle.right;
      }
    });
  }

  int _countForAngle(VehicleViewAngle angle) {
    return _markers.where((m) => m.viewAngle == angle).length;
  }

  Color _getColorForType(DamageType type) {
    switch (type) {
      case DamageType.dent:
        return Colors.red;
      case DamageType.scratch:
        return Colors.orange.shade800;
      case DamageType.cut:
        return Colors.purple;
    }
  }

  String _getLabelForType(DamageType type) {
    switch (type) {
      case DamageType.dent:
        return 'D';
      case DamageType.scratch:
        return 'S';
      case DamageType.cut:
        return 'C';
    }
  }

  IconData _iconForBodyType(VehicleBodyType t) {
    switch (t) {
      case VehicleBodyType.sedan:
        return Icons.directions_car;
      case VehicleBodyType.suv:
        return Icons.directions_car_filled;
      case VehicleBodyType.pickup:
        return Icons.fire_truck_outlined;
      case VehicleBodyType.lorry:
        return Icons.local_shipping;
      case VehicleBodyType.van:
        return Icons.airport_shuttle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleMarkers = _markers.where((m) => m.viewAngle == _currentAngle).toList();

    // Subtle 3D tilt angle when rotating between cardinal views
    double perspectiveRadians = 0.0;
    if (_currentAngle != VehicleViewAngle.top) {
      final nearestCardinal = _currentAngle.defaultDegrees % 360;
      double diff = _rotationDegrees - nearestCardinal;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      perspectiveRadians = (diff / 45.0).clamp(-1.0, 1.0) * 0.35;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Vehicle Body Type Selector (Sedan, SUV, Pickup, Lorry, Van)
          const Text(
            '1. Select Vehicle Body Type:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: VehicleBodyType.values.map((bt) {
                final isSelected = _bodyType == bt;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    avatar: Icon(
                      _iconForBodyType(bt),
                      size: 16,
                      color: isSelected ? Colors.white : const Color(0xFF1E293B),
                    ),
                    label: Text(bt.label),
                    selected: isSelected,
                    selectedColor: const Color(0xFF0F4C81),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF1E293B),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 12,
                    ),
                    onSelected: widget.readOnly
                        ? null
                        : (sel) {
                            if (sel) {
                              setState(() => _bodyType = bt);
                              widget.onBodyTypeChanged?.call(bt);
                            }
                          },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // 2. 360° View Angle Tabs (Front, Left Side, Rear, Right Side, Top/Roof)
          const Text(
            '2. Select or Rotate 3D Inspection Angle:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: VehicleViewAngle.values.map((angle) {
                final isSelected = _currentAngle == angle;
                final count = _countForAngle(angle);
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _currentAngle = angle;
                        if (angle != VehicleViewAngle.top) {
                          _rotationDegrees = angle.defaultDegrees % 360;
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF2563EB) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            angle.label,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (count > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFF2563EB) : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // 3. Damage Marker Type Toolbar
          if (!widget.readOnly) ...[
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildToolButton(DamageType.dent, 'Dent (D)'),
                        const SizedBox(width: 8),
                        _buildToolButton(DamageType.scratch, 'Scratch (S)'),
                        const SizedBox(width: 8),
                        _buildToolButton(DamageType.cut, 'Cut (C)'),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.undo, color: Colors.grey),
                  onPressed: _markers.isNotEmpty
                      ? () {
                          setState(() => _markers.removeLast());
                          widget.onMarkersChanged?.call(_markers);
                        }
                      : null,
                  tooltip: 'Undo last marker',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _markers.isNotEmpty ? _clearMarkers : null,
                  tooltip: 'Clear all markers',
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // 4. Fixed-Aspect-Ratio 3D Interactive Vehicle Blueprint Canvas
          // Using AspectRatio(16/9) + normalized coordinates guarantees 100% identical marker placement on Mobile & Web!
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boxSize = Size(constraints.maxWidth, constraints.maxHeight);
                    return GestureDetector(
                      onTapDown: (details) => _addMarkerNormalized(details.localPosition, boxSize),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Stack(
                            children: [
                              // 3D Perspective Transformed Vehicle Blueprint
                              Positioned.fill(
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, 0.001)
                                    ..rotateY(perspectiveRadians),
                                  child: CustomPaint(
                                    painter: _VehicleBlueprintPainter(
                                      bodyType: _bodyType,
                                      viewAngle: _currentAngle,
                                    ),
                                  ),
                                ),
                              ),

                              // Top-left Badge showing Current Body Type & View Angle
                              Positioned(
                                left: 10,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A).withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_bodyType.label.toUpperCase()} • ${_currentAngle.label.toUpperCase()} VIEW',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),

                              // Bottom-right Total Damages Counter
                              Positioned(
                                right: 10,
                                bottom: 8,
                                child: Text(
                                  'This View: ${visibleMarkers.length}  |  Total Recorded: ${_markers.length}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                ),
                              ),

                              // Render normalized markers for the active view angle
                              ...visibleMarkers.map((marker) {
                                final px = marker.nx * boxSize.width;
                                final py = marker.ny * boxSize.height;
                                return Positioned(
                                  left: px - 13,
                                  top: py - 13,
                                  child: GestureDetector(
                                    onTap: widget.readOnly
                                        ? null
                                        : () {
                                            setState(() => _markers.remove(marker));
                                            widget.onMarkersChanged?.call(_markers);
                                          },
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: _getColorForType(marker.type),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.25),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          _getLabelForType(marker.type),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),
          // 5. 360° 3D Orbit Rotation Slider
          Row(
            children: [
              const Icon(Icons.threed_rotation, size: 18, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              const Text(
                '360° Rotate:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              Expanded(
                child: Slider(
                  value: _rotationDegrees.clamp(0.0, 360.0),
                  min: 0,
                  max: 360,
                  divisions: 72,
                  activeColor: const Color(0xFF2563EB),
                  label: '${_rotationDegrees.round()}° (${_currentAngle.label})',
                  onChanged: _onRotationSliderChanged,
                ),
              ),
              Text(
                '${_rotationDegrees.round()}°',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(DamageType type, String label) {
    final isSelected = _selectedType == type;
    final color = _getColorForType(type);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            _selectedType = type;
          });
        }
      },
    );
  }
}

/// Custom architectural blueprint painter that draws accurate silhouettes & details
/// for Sedan, SUV, Pickup, Lorry/Truck, and Van across Front, Left, Rear, Right, and Top views.
class _VehicleBlueprintPainter extends CustomPainter {
  final VehicleBodyType bodyType;
  final VehicleViewAngle viewAngle;

  _VehicleBlueprintPainter({required this.bodyType, required this.viewAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Subtle engineering blueprint grid
    final gridPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < w; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (double y = 0; y < h; y += step) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    final bodyFill = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;
    final bodyStroke = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    final glassFill = Paint()
      ..color = const Color(0xFFBAE6FD).withOpacity(0.55)
      ..style = PaintingStyle.fill;
    final detailStroke = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final wheelFill = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    final rimFill = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;

    if (viewAngle == VehicleViewAngle.front || viewAngle == VehicleViewAngle.rear) {
      _drawFrontOrRear(canvas, size, bodyFill, bodyStroke, glassFill, detailStroke, wheelFill, viewAngle == VehicleViewAngle.front);
    } else if (viewAngle == VehicleViewAngle.top) {
      _drawTopView(canvas, size, bodyFill, bodyStroke, glassFill, detailStroke);
    } else {
      final isRight = viewAngle == VehicleViewAngle.right;
      if (isRight) {
        canvas.save();
        canvas.translate(w, 0);
        canvas.scale(-1, 1);
      }
      _drawSideView(canvas, size, bodyFill, bodyStroke, glassFill, detailStroke, wheelFill, rimFill);
      if (isRight) {
        canvas.restore();
      }
      // Orientation labels ("FRONT" / "REAR")
      _drawLabel(canvas, isRight ? 'REAR' : 'FRONT', Offset(24, h * 0.85));
      _drawLabel(canvas, isRight ? 'FRONT' : 'REAR', Offset(w - 58, h * 0.85));
    }
  }

  void _drawFrontOrRear(
    Canvas canvas,
    Size size,
    Paint bodyFill,
    Paint bodyStroke,
    Paint glassFill,
    Paint detailStroke,
    Paint wheelFill,
    bool isFront,
  ) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 10;
    final isTall = bodyType == VehicleBodyType.lorry || bodyType == VehicleBodyType.van || bodyType == VehicleBodyType.suv;
    final bw = bodyType == VehicleBodyType.lorry ? size.width * 0.46 : size.width * 0.42;
    final bh = isTall ? size.height * 0.58 : size.height * 0.46;

    // Left & Right Tires
    final tireW = bw * 0.16;
    final tireH = bh * 0.34;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - bw / 2 + 4, cy + bh / 2 - tireH * 0.55, tireW, tireH), const Radius.circular(6)),
      wheelFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx + bw / 2 - tireW - 4, cy + bh / 2 - tireH * 0.55, tireW, tireH), const Radius.circular(6)),
      wheelFill,
    );

    // Cabin + Lower Body Path
    final path = Path();
    final topW = bodyType == VehicleBodyType.lorry || bodyType == VehicleBodyType.van ? bw * 0.92 : bw * 0.76;
    path.moveTo(cx - topW / 2, cy - bh / 2);
    path.lineTo(cx + topW / 2, cy - bh / 2);
    path.lineTo(cx + bw / 2, cy - bh * 0.05);
    path.lineTo(cx + bw / 2, cy + bh * 0.35);
    path.lineTo(cx - bw / 2, cy + bh * 0.35);
    path.lineTo(cx - bw / 2, cy - bh * 0.05);
    path.close();

    canvas.drawPath(path, bodyFill);
    canvas.drawPath(path, bodyStroke);

    // Side Mirrors
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - bw / 2 - 16, cy - bh * 0.12, 16, 12), const Radius.circular(4)),
      bodyFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - bw / 2 - 16, cy - bh * 0.12, 16, 12), const Radius.circular(4)),
      bodyStroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx + bw / 2, cy - bh * 0.12, 16, 12), const Radius.circular(4)),
      bodyFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx + bw / 2, cy - bh * 0.12, 16, 12), const Radius.circular(4)),
      bodyStroke,
    );

    // Windshield / Rear Window
    final winPath = Path()
      ..moveTo(cx - topW * 0.44, cy - bh * 0.43)
      ..lineTo(cx + topW * 0.44, cy - bh * 0.43)
      ..lineTo(cx + bw * 0.42, cy - bh * 0.06)
      ..lineTo(cx - bw * 0.42, cy - bh * 0.06)
      ..close();
    canvas.drawPath(winPath, glassFill);
    canvas.drawPath(winPath, detailStroke);

    // Headlights (Yellow/White) or Taillights (Red)
    final lightPaint = Paint()
      ..color = isFront ? const Color(0xFFFEF08A) : const Color(0xFFFCA5A5)
      ..style = PaintingStyle.fill;
    final leftLight = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - bw * 0.44, cy + bh * 0.03, bw * 0.18, bh * 0.11),
      const Radius.circular(4),
    );
    final rightLight = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + bw * 0.26, cy + bh * 0.03, bw * 0.18, bh * 0.11),
      const Radius.circular(4),
    );
    canvas.drawRRect(leftLight, lightPaint);
    canvas.drawRRect(leftLight, detailStroke);
    canvas.drawRRect(rightLight, lightPaint);
    canvas.drawRRect(rightLight, detailStroke);

    // Grille / Tailgate & Bumper
    final grilleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - bw * 0.20, cy + bh * 0.04, bw * 0.40, bh * 0.12),
      const Radius.circular(4),
    );
    canvas.drawRRect(grilleRect, detailStroke);

    // License Plate Box
    final plateRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - bw * 0.14, cy + bh * 0.20, bw * 0.28, bh * 0.09),
      const Radius.circular(3),
    );
    canvas.drawRRect(plateRect, Paint()..color = Colors.white);
    canvas.drawRRect(plateRect, detailStroke);

    _drawLabel(canvas, 'LEFT SIDE', Offset(cx - bw / 2 - 48, cy + bh * 0.45));
    _drawLabel(canvas, 'RIGHT SIDE', Offset(cx + bw / 2 - 12, cy + bh * 0.45));
  }

  void _drawSideView(
    Canvas canvas,
    Size size,
    Paint bodyFill,
    Paint bodyStroke,
    Paint glassFill,
    Paint detailStroke,
    Paint wheelFill,
    Paint rimFill,
  ) {
    final w = size.width;
    final h = size.height;
    final groundY = h * 0.74;

    final path = Path();
    final glassPath = Path();

    switch (bodyType) {
      case VehicleBodyType.pickup:
        // Pickup Double-Cab / Single-Cab Silhouette with Open Cargo Bed
        path.moveTo(w * 0.14, groundY - h * 0.10);
        path.lineTo(w * 0.16, groundY - h * 0.26); // Front nose
        path.lineTo(w * 0.30, groundY - h * 0.30); // Hood
        path.lineTo(w * 0.38, groundY - h * 0.48); // Windshield
        path.lineTo(w * 0.58, groundY - h * 0.48); // Cab Roof
        path.lineTo(w * 0.59, groundY - h * 0.30); // Rear cab wall
        path.lineTo(w * 0.86, groundY - h * 0.30); // Pickup cargo bed top rail
        path.lineTo(w * 0.86, groundY - h * 0.10); // Tailgate
        path.close();

        glassPath.moveTo(w * 0.39, groundY - h * 0.45);
        glassPath.lineTo(w * 0.56, groundY - h * 0.45);
        glassPath.lineTo(w * 0.56, groundY - h * 0.30);
        glassPath.lineTo(w * 0.33, groundY - h * 0.30);
        glassPath.close();
        break;

      case VehicleBodyType.lorry:
        // Commercial Lorry / Box Truck Silhouette
        path.moveTo(w * 0.14, groundY - h * 0.10);
        path.lineTo(w * 0.14, groundY - h * 0.38); // Flat cab front
        path.lineTo(w * 0.19, groundY - h * 0.48); // Cab windshield
        path.lineTo(w * 0.33, groundY - h * 0.48); // Cab roof
        path.lineTo(w * 0.33, groundY - h * 0.18); // Cab back
        path.lineTo(w * 0.35, groundY - h * 0.18);
        path.lineTo(w * 0.35, groundY - h * 0.56); // High cargo box front
        path.lineTo(w * 0.87, groundY - h * 0.56); // High cargo box roof
        path.lineTo(w * 0.87, groundY - h * 0.10); // Cargo box rear doors
        path.close();

        glassPath.moveTo(w * 0.16, groundY - h * 0.38);
        glassPath.lineTo(w * 0.20, groundY - h * 0.45);
        glassPath.lineTo(w * 0.30, groundY - h * 0.45);
        glassPath.lineTo(w * 0.30, groundY - h * 0.32);
        glassPath.lineTo(w * 0.16, groundY - h * 0.32);
        glassPath.close();
        break;

      case VehicleBodyType.van:
        // Van / Minibus Silhouette
        path.moveTo(w * 0.14, groundY - h * 0.10);
        path.lineTo(w * 0.15, groundY - h * 0.28);
        path.lineTo(w * 0.24, groundY - h * 0.50);
        path.lineTo(w * 0.84, groundY - h * 0.50);
        path.lineTo(w * 0.86, groundY - h * 0.10);
        path.close();

        glassPath.moveTo(w * 0.25, groundY - h * 0.46);
        glassPath.lineTo(w * 0.81, groundY - h * 0.46);
        glassPath.lineTo(w * 0.82, groundY - h * 0.30);
        glassPath.lineTo(w * 0.20, groundY - h * 0.30);
        glassPath.close();
        break;

      case VehicleBodyType.suv:
        // SUV / Station Wagon Silhouette
        path.moveTo(w * 0.14, groundY - h * 0.10);
        path.lineTo(w * 0.16, groundY - h * 0.27);
        path.lineTo(w * 0.31, groundY - h * 0.30);
        path.lineTo(w * 0.40, groundY - h * 0.49);
        path.lineTo(w * 0.80, groundY - h * 0.49);
        path.lineTo(w * 0.85, groundY - h * 0.28);
        path.lineTo(w * 0.86, groundY - h * 0.10);
        path.close();

        glassPath.moveTo(w * 0.41, groundY - h * 0.45);
        glassPath.lineTo(w * 0.77, groundY - h * 0.45);
        glassPath.lineTo(w * 0.80, groundY - h * 0.30);
        glassPath.lineTo(w * 0.34, groundY - h * 0.30);
        glassPath.close();
        break;

      case VehicleBodyType.sedan:
      default:
        // Sedan / Saloon Silhouette
        path.moveTo(w * 0.14, groundY - h * 0.10);
        path.lineTo(w * 0.16, groundY - h * 0.24);
        path.lineTo(w * 0.32, groundY - h * 0.27);
        path.lineTo(w * 0.42, groundY - h * 0.45);
        path.lineTo(w * 0.67, groundY - h * 0.45);
        path.lineTo(w * 0.77, groundY - h * 0.27);
        path.lineTo(w * 0.86, groundY - h * 0.25);
        path.lineTo(w * 0.86, groundY - h * 0.10);
        path.close();

        glassPath.moveTo(w * 0.43, groundY - h * 0.42);
        glassPath.lineTo(w * 0.65, groundY - h * 0.42);
        glassPath.lineTo(w * 0.73, groundY - h * 0.27);
        glassPath.lineTo(w * 0.35, groundY - h * 0.27);
        glassPath.close();
        break;
    }

    canvas.drawPath(path, bodyFill);
    canvas.drawPath(path, bodyStroke);
    canvas.drawPath(glassPath, glassFill);
    canvas.drawPath(glassPath, detailStroke);

    // Door seam lines
    canvas.drawLine(Offset(w * 0.48, groundY - h * 0.44), Offset(w * 0.48, groundY - h * 0.12), detailStroke);

    // Wheels
    final wheelRadius = h * 0.11;
    final frontWheelCenter = Offset(w * 0.26, groundY - wheelRadius * 0.4);
    final rearWheelCenter = Offset(w * 0.74, groundY - wheelRadius * 0.4);

    canvas.drawCircle(frontWheelCenter, wheelRadius, wheelFill);
    canvas.drawCircle(frontWheelCenter, wheelRadius * 0.55, rimFill);
    canvas.drawCircle(rearWheelCenter, wheelRadius, wheelFill);
    canvas.drawCircle(rearWheelCenter, wheelRadius * 0.55, rimFill);
  }

  void _drawTopView(
    Canvas canvas,
    Size size,
    Paint bodyFill,
    Paint bodyStroke,
    Paint glassFill,
    Paint detailStroke,
  ) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final bw = size.width * 0.64;
    final bh = size.height * 0.48;

    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: bw, height: bh),
      const Radius.circular(24),
    );
    canvas.drawRRect(bodyRect, bodyFill);
    canvas.drawRRect(bodyRect, bodyStroke);

    // Hood / Roof / Trunk divisions
    final roofRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx + (bodyType == VehicleBodyType.pickup ? -bw * 0.08 : 0), cy), width: bw * 0.45, height: bh * 0.76),
      const Radius.circular(10),
    );
    canvas.drawRRect(roofRect, glassFill);
    canvas.drawRRect(roofRect, detailStroke);

    if (bodyType == VehicleBodyType.pickup || bodyType == VehicleBodyType.lorry) {
      // Draw cargo bed ribs on rear half
      final bedRect = Rect.fromLTWH(cx + bw * 0.12, cy - bh * 0.38, bw * 0.34, bh * 0.76);
      canvas.drawRect(bedRect, detailStroke);
    }

    _drawLabel(canvas, 'FRONT', Offset(cx - bw / 2 - 48, cy - 6));
    _drawLabel(canvas, 'REAR', Offset(cx + bw / 2 + 12, cy - 6));
  }

  void _drawLabel(Canvas canvas, String text, Offset pos) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Color(0xFF94A3B8),
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _VehicleBlueprintPainter oldDelegate) {
    return oldDelegate.bodyType != bodyType || oldDelegate.viewAngle != viewAngle;
  }
}
