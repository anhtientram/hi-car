import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/services/api_service.dart';
import './utils/device_utils.dart';

class AppLog {
  final String id;
  final DateTime timestamp;
  final String message;
  final String? type;
  final Map<String, dynamic>? details;
  final String? userMessage;
  final String? incidentId;
  final bool requiresAction;

  AppLog({
    required this.id,
    required this.timestamp,
    required this.message,
    this.type,
    this.details,
    this.userMessage,
    this.incidentId,
    this.requiresAction = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'message': message,
        'type': type,
        'details': details,
        'userMessage': userMessage,
        'incidentId': incidentId,
        'requiresAction': requiresAction,
      };

  factory AppLog.fromJson(Map<String, dynamic> json) => AppLog(
        id: json['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        message: json['message']?.toString() ?? 'Lỗi không xác định',
        type: json['type']?.toString(),
        details: json['details'] is Map
            ? Map<String, dynamic>.from(json['details'] as Map)
            : null,
        userMessage: json['userMessage']?.toString(),
        incidentId: json['incidentId']?.toString(),
        requiresAction: json['requiresAction'] == true,
      );
}

class AppLogger extends ChangeNotifier {
  static final AppLogger instance = AppLogger._();
  AppLogger._();

  final List<AppLog> _logs = [];
  static const _prefsKey = 'hicar_app_diagnostic_logs';
  static const _dismissedIncidentsKey = 'hicar_dismissed_incident_ids';
  static const _maxPersistedLogs = 120;
  final Set<String> _dismissedIncidentIds = <String>{};
  AppLog? _activeIncident;
  Future<void> _persistQueue = Future<void>.value();

  List<AppLog> get logs => List.unmodifiable(_logs.reversed);
  AppLog? get activeIncident => _activeIncident;

  static const errorTypes = {
    'native_error',
    'sync_error',
    'playback_error',
    'native_playback_error',
    'network_error',
    'download_error',
    'storage_error',
    'incident_error',
    'permission_error',
    'route_error',
    'overlay_error',
    'native_warning',
  };

  Future<void> init() async {
    try {
      _activeIncident = null;
      _logs.clear();
      final prefs = await SharedPreferences.getInstance();
      _dismissedIncidentIds
        ..clear()
        ..addAll(
            prefs.getStringList(_dismissedIncidentsKey) ?? const <String>[]);
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _logs
        ..clear()
        ..addAll(decoded.whereType<Map>().map(
              (item) => AppLog.fromJson(Map<String, dynamic>.from(item)),
            ));
      if (_logs.length > _maxPersistedLogs) {
        _logs.removeRange(0, _logs.length - _maxPersistedLogs);
      }
      for (final log in _logs.reversed) {
        if (log.requiresAction &&
            log.incidentId != null &&
            !_dismissedIncidentIds.contains(log.incidentId)) {
          _activeIncident = log;
          break;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('AppLogger.init lỗi: $e');
    }
  }

  void log(
    String message, {
    String? type,
    Map<String, dynamic>? details,
    String? userMessage,
    String? incidentId,
    bool requiresAction = false,
  }) {
    final newLog = AppLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      message: _redactText(message),
      type: type,
      details: _safeDetails(details),
      userMessage: userMessage,
      incidentId: incidentId ??
          (requiresAction
              ? 'app-${DateTime.now().microsecondsSinceEpoch}'
              : null),
      requiresAction: requiresAction,
    );
    _logs.add(newLog);
    if (_logs.length > _maxPersistedLogs) {
      _logs.removeAt(0);
    }
    if (requiresAction && !_dismissedIncidentIds.contains(newLog.incidentId))
      _activeIncident = newLog;
    debugPrint('📝 [LOG]: ${newLog.message}');
    _persist();
    notifyListeners();
  }

  void dismissIncident() {
    final incidentId = _activeIncident?.incidentId;
    if (incidentId != null) {
      _dismissedIncidentIds.add(incidentId);
      _persistDismissedIncidents();
    }
    _activeIncident = null;
    notifyListeners();
  }

  void markIncidentResolved(String? incidentId) {
    if (incidentId != null) {
      _dismissedIncidentIds.add(incidentId);
      _persistDismissedIncidents();
    }
    if (incidentId == null || _activeIncident?.incidentId == incidentId) {
      _activeIncident = null;
      notifyListeners();
    }
  }

  void resolvePlaybackJob(String jobId) {
    for (final log in _logs) {
      if (log.message.contains('job=$jobId ') && log.incidentId != null) {
        markIncidentResolved(log.incidentId);
      }
    }
  }

  void removeLog(String logId) {
    _logs.removeWhere((l) => l.id == logId);
    if (_activeIncident?.id == logId) _activeIncident = null;
    _persist();
    notifyListeners();
  }

  void clear() {
    _logs.clear();
    _activeIncident = null;
    _persist();
    notifyListeners();
  }

  List<AppLog> get errorLogs =>
      logs.where((l) => errorTypes.contains(l.type ?? '')).toList();

  String _mapErrorType(AppLog log) {
    final type = log.type?.toLowerCase() ?? '';
    final msg = log.message.toLowerCase();

    if (type.contains('network') ||
        type.contains('sync') ||
        type.contains('download')) {
      return 'sync';
    }
    if (type.contains('playback') || type.contains('audio')) {
      return 'audio';
    }
    if (type.contains('bluetooth') || msg.contains('bluetooth')) {
      return 'bluetooth';
    }
    if (type.contains('permission')) {
      return 'permission';
    }
    return 'other';
  }

  Future<String> _resolveSyncStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString('last_sync_time');
      if (lastSync != null && lastSync.isNotEmpty) return 'synced';
    } catch (_) {}
    return 'unknown';
  }

  Future<void> _persist() {
    final snapshot = jsonEncode(_logs.map((item) => item.toJson()).toList());
    _persistQueue = _persistQueue.then((_) => _writeSnapshot(snapshot));
    return _persistQueue;
  }

  Future<void> flush() => _persistQueue;

  Future<void> _writeSnapshot(String snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        snapshot,
      );
    } catch (e) {
      debugPrint('AppLogger.persist lỗi: $e');
    }
  }

  Future<void> _persistDismissedIncidents() {
    final ids = _dismissedIncidentIds.toList();
    _persistQueue = _persistQueue.then((_) => _writeDismissedIncidents(ids));
    return _persistQueue;
  }

  Future<void> _writeDismissedIncidents(List<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _dismissedIncidentsKey,
        ids.length > 200 ? ids.sublist(ids.length - 200) : ids,
      );
    } catch (e) {
      debugPrint('AppLogger.persist dismissed incidents lỗi: $e');
    }
  }

  String _buildDescription({
    required AppLog log,
    String? userNote,
    String? diagnosticLog,
  }) {
    final parts = <String>[];
    if (userNote != null && userNote.trim().isNotEmpty) {
      parts.add(_redactText(userNote.trim()));
    }
    parts.add(_redactText(log.message));
    parts.add(
        'incident=${log.incidentId} timestamp=${log.timestamp.toIso8601String()} timezone=${DateTime.now().timeZoneName}');
    parts.add(jsonEncode(_safeDetails(log.details)));
    if (diagnosticLog != null && diagnosticLog.trim().isNotEmpty) {
      parts
          .add('\n--- HiCar adb log ---\n${_redactText(diagnosticLog.trim())}');
    }
    return parts.join('\n\n');
  }

  /// Sends error report to server (API: POST /api/logs/error).
  Future<void> sendReport(
    AppLog log, {
    String? userNote,
    String? diagnosticLog,
  }) async {
    final deviceContext = await DeviceUtils.getDeviceContext();
    final syncStatus = await _resolveSyncStatus();
    final description = _buildDescription(
      log: log,
      userNote: userNote,
      diagnosticLog: diagnosticLog,
    );

    await ApiService.instance.logError({
      'error_type': _mapErrorType(log),
      'description': description,
      'device_id': deviceContext['device_id'],
      'device_name': deviceContext['device_name'],
      'device_model': deviceContext['device_model'],
      'os_version': deviceContext['os_version'],
      'app_version': deviceContext['app_version'],
      'sync_status': syncStatus,
      'incident_id': log.incidentId,
      'details': _safeDetails({
        ...?log.details,
        if (deviceContext['metadata_errors'] != null)
          'metadata_errors': deviceContext['metadata_errors'],
      }),
    });

    removeLog(log.id);
  }

  Map<String, dynamic> _safeDetails(Map<String, dynamic>? details) {
    if (details == null) return {};
    final result = <String, dynamic>{};
    for (final entry in details.entries) {
      final key = entry.key.toLowerCase();
      if (key.contains('token') ||
          key.contains('password') ||
          key.contains('authorization')) {
        result[entry.key] = '[redacted]';
      } else {
        result[entry.key] = _safeValue(entry.value);
      }
    }
    return result;
  }

  dynamic _safeValue(dynamic value) {
    if (value is String) return _redactText(value);
    if (value is Map) return _safeDetails(Map<String, dynamic>.from(value));
    if (value is Iterable) return value.map(_safeValue).toList();
    return value;
  }

  String _redactText(String value) {
    var redacted = value.replaceAllMapped(
        RegExp(r'(bearer\s+)[^\s,]+', caseSensitive: false),
        (match) => '${match[1]}[redacted]');
    redacted = redacted.replaceAllMapped(
        RegExp(
          r'(token|access_token|api_key|password|authorization)(\s*[:=]\s*|%3d)[^\s&;,]+',
          caseSensitive: false,
        ),
        (match) => '${match[1]}=[redacted]');
    redacted = redacted.replaceAll(
      RegExp(r'\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b', caseSensitive: false),
      '[mac-redacted]',
    );
    return redacted;
  }
}
