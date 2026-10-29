import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class SyncEvent {
  final String id;
  final String type;
  final String entityId;
  final String actorName;
  final String actorRole;
  final String message;
  final Map<String, dynamic> metadata;
  final String timestamp;

  SyncEvent({
    required this.id,
    required this.type,
    required this.entityId,
    required this.actorName,
    required this.actorRole,
    required this.message,
    required this.metadata,
    required this.timestamp,
  });

  factory SyncEvent.fromJson(Map<String, dynamic> json) {
    return SyncEvent(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      entityId: (json['entityId'] ?? '').toString(),
      actorName: (json['actorName'] ?? '').toString(),
      actorRole: (json['actorRole'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      metadata: json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata']) : {},
      timestamp: (json['timestamp'] ?? '').toString(),
    );
  }
}

class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  static const String _baseUrl = 'https://auto.zksms.online/api';
  Timer? _pollingTimer;
  String? _lastSyncTimestamp;
  bool _isSyncing = false;
  bool _hasLiveConnection = true;
  DateTime? _lastSuccessfulSync;

  final StreamController<SyncEvent> _eventStreamController = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get onSyncEvent => _eventStreamController.stream;

  bool get isSyncing => _isSyncing;
  bool get hasLiveConnection => _hasLiveConnection;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;

  /// Start the background auto-sync polling loop (runs every 6-8 seconds)
  void startAutoSync({int intervalSeconds = 7}) {
    _pollingTimer?.cancel();
    _checkSyncStatus(); // Initial check
    _pollingTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      _checkSyncStatus();
    });
  }

  void stopAutoSync() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Manually force an immediate check & trigger synchronization
  Future<void> triggerSync() async {
    await _checkSyncStatus(force: true);
  }

  Future<void> _checkSyncStatus({bool force = false}) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final uri = Uri.parse('$_baseUrl/sync/status').replace(
        queryParameters: _lastSyncTimestamp != null && !force
            ? {'since': _lastSyncTimestamp}
            : null,
      );

      final resp = await http.get(uri, headers: AuthService.instance.authHeaders).timeout(
        const Duration(seconds: 5),
      );

      if (resp.statusCode == 200) {
        _hasLiveConnection = true;
        _lastSuccessfulSync = DateTime.now();
        final data = json.decode(resp.body);
        final String? serverLastUpdated = data['lastUpdated']?.toString();
        final bool hasChanges = data['hasChanges'] == true;
        final rawEvents = (data['events'] as List<dynamic>?) ?? [];

        final newEvents = rawEvents.map((e) => SyncEvent.fromJson(Map<String, dynamic>.from(e))).toList();

        // Dispatch new events to listeners
        for (final evt in newEvents) {
          _eventStreamController.add(evt);
        }

        if (hasChanges || _lastSyncTimestamp == null) {
          _lastSyncTimestamp = serverLastUpdated ?? DateTime.now().toIso8601String();
          notifyListeners();
        } else if (serverLastUpdated != null) {
          _lastSyncTimestamp = serverLastUpdated;
        }
      } else {
        _hasLiveConnection = false;
      }
    } catch (_) {
      _hasLiveConnection = false;
    } finally {
      _isSyncing = false;
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _eventStreamController.close();
    super.dispose();
  }
}
