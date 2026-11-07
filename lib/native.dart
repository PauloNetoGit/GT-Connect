import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Ponte para o código Android (MainActivity.kt).
class Native {
  static const _m = MethodChannel('pontegt1/native');
  static const _e = EventChannel('pontegt1/events');

  static Stream<Map<dynamic, dynamic>>? _events;

  /// Eventos vindos do Android: gt, pedal, ble, status, usbAttached.
  static Stream<Map<dynamic, dynamic>> get events =>
      _events ??= _e.receiveBroadcastStream().map((e) => e as Map<dynamic, dynamic>);

  static Future<int> sdkInt() async => (await _m.invokeMethod<int>('sdkInt')) ?? 0;

  static Future<void> keepScreenOn(bool on) => _m.invokeMethod('keepScreenOn', {'on': on});

  // ---- GT-1 (USB) ----
  static Future<List<Map<dynamic, dynamic>>> usbList() async {
    final r = await _m.invokeMethod<List<dynamic>>('usbList');
    return (r ?? []).cast<Map<dynamic, dynamic>>();
  }

  static Future<Map<dynamic, dynamic>> usbOpen(String deviceName) async {
    final r = await _m.invokeMethod<Map<dynamic, dynamic>>('usbOpen', {'deviceName': deviceName});
    return r ?? {'ok': false, 'error': 'Sem resposta'};
  }

  static Future<void> usbClose() => _m.invokeMethod('usbClose');

  static Future<bool> usbSend(Uint8List data) async =>
      (await _m.invokeMethod<bool>('usbSend', {'data': data})) ?? false;

  // ---- Pedal ----
  static Future<void> bleScanStart() => _m.invokeMethod('bleScanStart');
  static Future<void> bleScanStop() => _m.invokeMethod('bleScanStop');

  static Future<List<Map<dynamic, dynamic>>> midiList() async {
    final r = await _m.invokeMethod<List<dynamic>>('midiList');
    return (r ?? []).cast<Map<dynamic, dynamic>>();
  }

  static Future<Map<dynamic, dynamic>> pedalOpenBle(String address) async =>
      (await _m.invokeMethod<Map<dynamic, dynamic>>('pedalOpenBle', {'address': address})) ?? {};

  static Future<Map<dynamic, dynamic>> pedalOpenMidi(int id) async =>
      (await _m.invokeMethod<Map<dynamic, dynamic>>('pedalOpenMidi', {'id': id})) ?? {};

  static Future<void> pedalClose() => _m.invokeMethod('pedalClose');
}
