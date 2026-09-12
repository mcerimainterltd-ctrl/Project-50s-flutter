import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum StorageHealthStatus {
  healthy,
  low,
  veryLow,
  critical,
}

final storageHealthServiceProvider =
    ChangeNotifierProvider<StorageHealthService>((ref) {
  return StorageHealthService();
});

class StorageHealthService extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.xamepage.app/android_bridge');

  static const int _oneGb = 1024 * 1024 * 1024;

  StorageHealthStatus _status = StorageHealthStatus.healthy;
  int _availableBytes = 0;
  int _totalBytes = 0;
  bool _hasChecked = false;

  StorageHealthStatus get status => _status;
  int get availableBytes => _availableBytes;
  int get totalBytes => _totalBytes;
  bool get hasChecked => _hasChecked;

  bool get showBanner =>
      _hasChecked && _status != StorageHealthStatus.healthy;

  bool get isCritical =>
      _hasChecked && _status == StorageHealthStatus.critical;

  String get availableText {
    if (_availableBytes <= 0) return 'unknown';

    final gb = _availableBytes / _oneGb;
    if (gb >= 1) {
      return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
    }

    final mb = _availableBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  String get bannerMessage {
    switch (_status) {
      case StorageHealthStatus.low:
        return 'Storage is running low. Your device has only $availableText available. Free some storage to keep XamePage working properly.';
      case StorageHealthStatus.veryLow:
        return 'Very low storage. Your device has only $availableText available. Free storage soon to prevent problems with downloads and media.';
      case StorageHealthStatus.critical:
        return 'Critical storage. Your device has only $availableText available. Free storage to prevent problems with downloads, media, updates, and app operation.';
      case StorageHealthStatus.healthy:
        return '';
    }
  }

  Future<void> checkNow() async {
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getStorageInfo');

      if (result == null) return;

      final available = (result['availableBytes'] as num?)?.toInt() ?? 0;
      final total = (result['totalBytes'] as num?)?.toInt() ?? 0;

      if (available <= 0 || total <= 0) return;

      final percent = (available / total) * 100;

      final StorageHealthStatus nextStatus;
      if (available < _oneGb || percent < 2) {
        nextStatus = StorageHealthStatus.critical;
      } else if (percent < 5) {
        nextStatus = StorageHealthStatus.veryLow;
      } else if (percent < 15) {
        nextStatus = StorageHealthStatus.low;
      } else {
        nextStatus = StorageHealthStatus.healthy;
      }

      final changed = !_hasChecked ||
          _status != nextStatus ||
          _availableBytes != available ||
          _totalBytes != total;

      _availableBytes = available;
      _totalBytes = total;
      _status = nextStatus;
      _hasChecked = true;

      if (changed) notifyListeners();
    } on PlatformException catch (e) {
      debugPrint('XamePage: Storage check failed: ${e.message}');
    } catch (e) {
      debugPrint('XamePage: Storage check failed: $e');
    }
  }
}
