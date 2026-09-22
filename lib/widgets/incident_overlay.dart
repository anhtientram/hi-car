import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/logger.dart';
import '../native/service_channel.dart';
import '../data/services/api_client.dart';
import '../core/utils/ui_utils.dart';

/// Hiển thị incident quan trọng ngay cả khi lỗi đến từ native service trước khi
/// người dùng mở màn hình Settings. Log vẫn được lưu để popup có thể đóng và gửi sau.
class IncidentOverlay extends StatefulWidget {
  final Widget child;

  const IncidentOverlay({super.key, required this.child});

  @override
  State<IncidentOverlay> createState() => _IncidentOverlayState();
}

class _IncidentOverlayState extends State<IncidentOverlay> {
  String? _sendingIncidentId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLogger.instance,
      builder: (context, _) {
        final incident = AppLogger.instance.activeIncident;
        return Stack(
          children: [
            widget.child,
            if (incident != null)
              Positioned.fill(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.48),
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _IncidentCard(
                        incident: incident,
                        isSending: _sendingIncidentId == incident.id,
                        onClose: AppLogger.instance.dismissIncident,
                        onRetry: () => _retryIncident(incident),
                        onSend: () => _sendIncident(incident),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _sendIncident(AppLog incident) async {
    setState(() => _sendingIncidentId = incident.id);
    try {
      final diagnostic = await ServiceChannel.instance.getDiagnosticLogErrors();
      await AppLogger.instance.sendReport(
        incident,
        diagnosticLog: diagnostic,
      );
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Đã gửi báo cáo lỗi.')),
      );
    } catch (e) {
      AppLogger.instance.log(
        'Gửi báo cáo incident thất bại: $e',
        type: 'network_error',
        details: {'incidentId': incident.incidentId, 'error': e.toString()},
      );
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
            content:
                Text('Chưa gửi được báo cáo: ${ApiClient.formatError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _sendingIncidentId = null);
    }
  }

  Future<void> _retryIncident(AppLog incident) async {
    AppLogger.instance.dismissIncident();
    final ok = await ServiceChannel.instance.retryGreeting(
      audioPath: incident.details?['path']?.toString(),
    );
    if (!mounted) return;
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Đã tạo lượt thử lại; ứng dụng sẽ tiếp tục chờ route xe.'
            : 'Chưa tạo được lượt thử lại.'),
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  final AppLog incident;
  final bool isSending;
  final VoidCallback onClose;
  final VoidCallback onRetry;
  final VoidCallback onSend;

  const _IncidentCard({
    required this.incident,
    required this.isSending,
    required this.onClose,
    required this.onRetry,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final details = incident.details ?? const <String, dynamic>{};
    final mode = details['mode'] ?? details['connection_mode'];
    final device =
        details['device'] ?? details['device_name'] ?? details['device_model'];
    final os = details['os'] ?? details['os_version'];
    final connection = details['connection'] ?? _connectionLabel(mode);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.7)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ứng dụng gặp vấn đề',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Đóng',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            incident.userMessage ?? incident.message,
            style: const TextStyle(fontSize: 14),
          ),
          if (mode != null ||
              device != null ||
              os != null ||
              connection != null) ...[
            const SizedBox(height: 10),
            Text(
              [
                if (mode != null) 'Mode: $mode',
                if (connection != null) 'Kết nối: $connection',
                if (device != null) 'Thiết bị: $device',
                if (os != null) 'OS: $os',
                if (incident.incidentId != null) 'Mã: ${incident.incidentId}',
              ].join('\n'),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: isSending ? null : onClose,
                child: const Text('Đóng'),
              ),
              OutlinedButton.icon(
                onPressed: isSending ? null : onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Thử lại'),
              ),
              FilledButton.icon(
                onPressed: isSending ? null : onSend,
                icon: isSending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(isSending ? 'Đang gửi...' : 'Gửi báo lỗi'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _connectionLabel(Object? mode) {
    switch (mode?.toString()) {
      case 'phone_bluetooth':
        return 'Bluetooth / A2DP';
      case 'phone_android_auto':
        return 'Android Auto';
      case 'android_screen_mode':
        return 'Màn hình Android';
      case 'android_box_mode':
        return 'Android Box';
      case 'ios_carplay':
        return 'CarPlay / Bluetooth';
      default:
        return null;
    }
  }
}
