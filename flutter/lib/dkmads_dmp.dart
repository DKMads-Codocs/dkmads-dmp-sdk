library dkmads_dmp

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

export 'demographics.dart';

class DMPConsent {
  final bool? gdprApplies;
  final String? tcfString;
  final String? usPrivacy;
  final Map<String, bool>? purposes;
  const DMPConsent({this.gdprApplies, this.tcfString, this.usPrivacy, this.purposes});
}

class DMPInitConfig {
  final String appKey;
  final String? workspaceId;
  final String? propertyId;
  final String apiHost;
  final int flushIntervalMs;
  final int batchSize;
  final bool collectDeviceIds;
  final bool requestATT;
  const DMPInitConfig({
    required this.appKey,
    this.workspaceId,
    this.propertyId,
    this.apiHost = 'https://ingest.dmp.dkmads.com',
    this.flushIntervalMs = 10000,
    this.batchSize = 20,
    this.collectDeviceIds = true,
    this.requestATT = true,
  });
}

class DMPSharedIdentity {
  final String devicePid;
  final String? userPid;
  const DMPSharedIdentity({required this.devicePid, this.userPid});
}

class DMP {
  static const _channel = MethodChannel('com.dkmads.dmp/sdk');
  static DMPInitConfig? _config;
  static String? _workspaceId;
  static String? _propertyId;
  static final List<Map<String, dynamic>> _queue = [];
  static final Map<String, dynamic> _traits = {};
  static final Map<String, dynamic> _context = {};
  static String? _userId;
  static bool _optedOut = false;
  static DMPConsent? _consent;
  static String _attStatus = 'not_determined';
  static bool _latEnabled = false;
  static Timer? _flushTimer;
  static SharedPreferences? _prefs;

  static bool _canCollect() {
    if (_optedOut) return false;
    if (_consent?.usPrivacy != null && _consent!.usPrivacy!.length >= 3 && _consent!.usPrivacy![2] == 'Y') {
      return false;
    }
    if (_consent?.gdprApplies == true) {
      return _consent?.purposes?['1'] == true;
    }
    return true;
  }

  static Future<void> init(DMPInitConfig config) async {
    _config = config;
    _workspaceId = config.workspaceId;
    _propertyId = config.propertyId;
    _prefs = await SharedPreferences.getInstance();
    _optedOut = _prefs?.getBool('dkmads_dmp_opted_out') ?? false;

    if (_workspaceId == null || _propertyId == null) await _resolveBridge();

    if (config.requestATT) {
      try {
        _attStatus = await _channel.invokeMethod<String>('requestATT') ?? 'not_determined';
      } catch (_) {
        _attStatus = 'not_determined';
      }
    }

    try {
      _latEnabled = await _channel.invokeMethod<bool>('isLatEnabled') ?? false;
    } catch (_) {
      _latEnabled = false;
    }

    await _syncOptOutFromServer();

    _flushTimer = Timer.periodic(Duration(milliseconds: config.flushIntervalMs), (_) => flush());
    track('sdk_initialized', {'platform': 'flutter', 'attStatus': _attStatus});
  }

  static void identify(String userId, [Map<String, dynamic>? traits]) {
    if (!_canCollect()) return;
    _userId = userId;
    if (traits != null) _traits.addAll(traits);
    _enqueue('identify', {'userId': userId});
  }

  static void track(String event, [Map<String, dynamic>? properties]) {
    if (!_canCollect()) return;
    _enqueue(event, properties);
  }

  static void setTrait(String key, dynamic value) {
    if (!_canCollect()) return;
    _traits[key] = value;
  }

  static void setTraits(Map<String, dynamic> traits) {
    if (!_canCollect()) return;
    _traits.addAll(traits);
  }

  static void setContext(Map<String, dynamic> context) {
    if (!_canCollect()) return;
    _context.addAll(context);
  }

  static Future<void> setConsent(DMPConsent consent) async {
    _consent = consent;
    await http.post(
      Uri.parse('${_config!.apiHost}/v1/ingest/consent'),
      headers: {'Content-Type': 'application/json', 'X-DMP-App-Key': _config!.appKey},
      body: jsonEncode({
        'gdprApplies': consent.gdprApplies,
        'tcfString': consent.tcfString,
        'usPrivacy': consent.usPrivacy,
        'purposes': consent.purposes,
        'devicePid': _getDevicePid(),
        'attStatus': _attStatus,
        'latEnabled': _latEnabled,
      }),
    );
  }

  static Future<void> optOut() async {
    _optedOut = true;
    await _prefs?.setBool('dkmads_dmp_opted_out', true);
    await _syncOptOutToServer();
    reset();
  }

  static void reset() { _userId = null; _traits.clear(); _context.clear(); _queue.clear(); }

  /// Stable device id for SSP `linkDmpIdentity` — same value sent on DMP ingest.
  static String getDevicePid() => _getDevicePid();

  static String? getUserPid() => _userId;

  static DMPSharedIdentity getSharedIdentity() =>
      DMPSharedIdentity(devicePid: _getDevicePid(), userPid: _userId);

  static Future<void> flush() async {
    if (_queue.isEmpty || _config == null || !_canCollect()) return;
    final events = _queue.take(_config!.batchSize).toList();
    _queue.removeRange(0, events.length);
    await http.post(
      Uri.parse('${_config!.apiHost}/v1/ingest/batch'),
      headers: {'Content-Type': 'application/json', 'X-DMP-App-Key': _config!.appKey},
      body: jsonEncode({'workspaceId': _workspaceId, 'propertyId': _propertyId, 'sdkVersion': '0.1.0', 'events': events}),
    );
  }

  static Future<void> _resolveBridge() async {
    final res = await http.get(Uri.parse('${_config!.apiHost}/v1/bridge/resolve?app_key=${_config!.appKey}'));
    final data = jsonDecode(res.body);
    _workspaceId = data['workspaceId'];
    _propertyId = data['propertyId'];
  }

  static Future<void> _syncOptOutFromServer() async {
    final res = await http.get(
      Uri.parse('${_config!.apiHost}/v1/opt-out/status?device_pid=${Uri.encodeComponent(_getDevicePid())}'),
      headers: {'X-DMP-App-Key': _config!.appKey},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data['optedOut'] == true) {
        _optedOut = true;
        await _prefs?.setBool('dkmads_dmp_opted_out', true);
      }
    }
  }

  static Future<void> _syncOptOutToServer() async {
    await http.post(
      Uri.parse('${_config!.apiHost}/v1/ingest/opt-out'),
      headers: {'Content-Type': 'application/json', 'X-DMP-App-Key': _config!.appKey},
      body: jsonEncode({'devicePid': _getDevicePid()}),
    );
  }

  static String? _devicePid;

  static String _getDevicePid() {
    if (_devicePid != null) return _devicePid!;
    final stored = _prefs?.getString('dkmads_dmp_device_pid');
    if (stored != null) {
      _devicePid = stored;
      return stored;
    }
    _devicePid = 'dkmads_${_randomUuid()}';
    _prefs?.setString('dkmads_dmp_device_pid', _devicePid!);
    return _devicePid!;
  }

  static String _randomUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
  }

  static Future<void> _enqueue(String event, Map<String, dynamic>? properties) async {
    if (!_canCollect()) return;
    final ids = <Map<String, String>>[
      {'type': 'device_pid', 'value': _getDevicePid()},
    ];

    if (_config?.collectDeviceIds == true) {
      try {
        final advertisingId = await _channel.invokeMethod<String>('getAdvertisingId');
        if (advertisingId != null && advertisingId.isNotEmpty) {
          final idType = Platform.isIOS ? 'idfa' : 'gaid';
          ids.add({'type': idType, 'value': advertisingId});
        }
      } catch (_) {}
    }

    if (_userId != null) {
      ids.add({'type': 'publisher_user_id', 'value': _userId!});
      ids.add({'type': 'user_pid', 'value': _userId!});
    }
    ids.addAll(_matchIdentifiersFromTraits(_traits));
    final eventContext = <String, dynamic>{
      'platform': 'flutter',
      'attStatus': _attStatus,
      'latEnabled': _latEnabled,
      ..._context,
    };
    _queue.add({
      'eventName': event,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'identifiers': ids,
      'traits': Map.of(_traits),
      'properties': properties ?? {},
      'context': eventContext,
    });
    if (_queue.length >= (_config?.batchSize ?? 20)) await flush();
  }

  static String _sha256Hex(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static List<Map<String, String>> _matchIdentifiersFromTraits(Map<String, dynamic> traits) {
    final out = <Map<String, String>>[];
    for (final key in ['email', 'trait.email']) {
      final raw = traits[key]?.toString() ?? '';
      if (raw.isNotEmpty) {
        final normalized = raw.trim().toLowerCase();
        final value = normalized.length == 64 ? normalized : _sha256Hex(normalized);
        out.add({'type': 'email_sha256', 'value': value});
      }
    }
    for (final key in ['phone', 'trait.phone']) {
      final raw = traits[key]?.toString() ?? '';
      if (raw.isNotEmpty) {
        final digits = raw.replaceAll(RegExp(r'\D'), '');
        final normalized = raw.trim().startsWith('+') ? '+$digits' : digits;
        final value = normalized.length == 64 ? normalized : _sha256Hex(normalized);
        out.add({'type': 'phone_sha256', 'value': value});
      }
    }
    for (final key in ['googleSubId', 'google_sub_hash']) {
      final raw = traits[key]?.toString() ?? '';
      if (raw.isNotEmpty) {
        final trimmed = raw.trim();
        final value = trimmed.length == 64 ? trimmed.toLowerCase() : _sha256Hex(trimmed);
        out.add({'type': 'google_sub_hash', 'value': value});
      }
    }
    return out;
  }
}
