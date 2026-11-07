import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gt1.dart';
import 'model.dart';
import 'native.dart';

class LogLine {
  final DateTime t;
  final String kind; // in, out, info, err
  final String text;
  LogLine(this.kind, this.text) : t = DateTime.now();
}

class BleItem {
  final String address;
  final String name;
  BleItem(this.address, this.name);
}

class AppState extends ChangeNotifier {
  AppConfig config = AppConfig.defaults();
  late final Gt1 gt = Gt1(send: _sendGt, log: _log);

  bool gtConnected = false;
  bool gtBusy = false;
  String gtStatus = 'GT-1 desconectada';
  bool pedalConnected = false;
  String pedalStatus = 'Pedal desconectado';

  int? learningRow;
  final List<BleItem> bleFound = [];
  final List<LogLine> logs = [];
  final ValueNotifier<int?> flash = ValueNotifier(null);
  final StreamController<List<int>> liveBytes = StreamController.broadcast(); // [endereço, valor]
  final StreamController<String> messages = StreamController.broadcast();

  final Map<int, int> _toggleCache = {};
  final Map<int, bool> _abState = {};
  StreamSubscription<dynamic>? _sub;

  Future<void> init() async {
    await _load();
    gt.onPatch = (n) {
      _toggleCache.clear();
      _log('in', 'GT-1 mudou para ${patchLabel(n)}');
      notifyListeners();
    };
    gt.onLiveByte = (a, v) => liveBytes.add([a, v]);
    _sub = Native.events.listen(_onEvent, onError: (Object e) => _log('err', '$e'));
    await Native.keepScreenOn(config.keepScreenOn);
    _log('info', 'Pronto. Ligue a GT-1 pelo cabo USB OTG e toque em Conectar.');
    unawaited(connectGt(quiet: true));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void toast(String msg) => messages.add(msg);

  void _log(String kind, String text) {
    logs.add(LogLine(kind, text));
    if (logs.length > 400) logs.removeRange(0, logs.length - 400);
    notifyListeners();
  }

  Future<void> _sendGt(List<int> bytes) async {
    final ok = await Native.usbSend(Uint8List.fromList(bytes));
    if (!ok) throw Exception('Falha ao enviar para a GT-1 pelo USB');
  }

  // ---------------------------------------------------------------- persistência
  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('config');
      if (s != null) config = AppConfig.fromJson(jsonDecode(s) as Map<dynamic, dynamic>);
    } catch (_) {
      config = AppConfig.defaults();
    }
    notifyListeners();
  }

  Future<void> save() async {
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('config', jsonEncode(config.toJson()));
    } catch (_) {}
  }

  String exportConfig() => const JsonEncoder.withIndent('  ').convert(config.toJson());

  bool importConfig(String text) {
    try {
      config = AppConfig.fromJson(jsonDecode(text) as Map<dynamic, dynamic>);
      save();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setKeepScreenOn(bool on) async {
    config.keepScreenOn = on;
    await Native.keepScreenOn(on);
    await save();
  }

  // ---------------------------------------------------------------- eventos do Android
  void _onEvent(Map<dynamic, dynamic> e) {
    switch (e['type']) {
      case 'gt':
        gt.onMessage(List<int>.from(e['data'] as List));
        break;
      case 'pedal':
        _onPedal(List<int>.from(e['data'] as List));
        break;
      case 'ble':
        final addr = '${e['address']}';
        if (!bleFound.any((b) => b.address == addr)) {
          bleFound.add(BleItem(addr, '${e['name']}'));
          notifyListeners();
        }
        break;
      case 'usbAttached':
        if (!gtConnected) unawaited(connectGt(quiet: true));
        break;
      case 'status':
        final msg = '${e['message'] ?? ''}';
        if (e['what'] == 'usb') {
          gt.reset();
          gtConnected = false;
          gtStatus = 'GT-1 desconectada';
          _log('err', msg);
        } else if (e['what'] == 'pedal') {
          if (e['state'] == 'disconnected') {
            pedalConnected = false;
            pedalStatus = 'Pedal desconectado';
          }
          _log('err', msg);
          if (msg.isNotEmpty) toast(msg);
        }
        notifyListeners();
        break;
    }
  }

  // ---------------------------------------------------------------- GT-1
  Future<void> connectGt({bool quiet = false}) async {
    if (gtBusy) return;
    gtBusy = true;
    notifyListeners();
    try {
      final list = await Native.usbList();
      final dev = list.firstWhere((d) => d['roland'] == true, orElse: () => {});
      if (dev.isEmpty) {
        gtStatus = 'GT-1 não encontrada no USB';
        if (!quiet) {
          toast('Não achei a GT-1. Confira o cabo OTG e se a GT-1 está ligada.');
          if (list.isNotEmpty) _log('info', 'USB visto: ${list.map((d) => d['name']).join(', ')}');
        }
        return;
      }
      gtStatus = 'Conectando…';
      notifyListeners();
      final r = await Native.usbOpen('${dev['deviceName']}');
      if (r['ok'] != true) {
        gtStatus = 'GT-1: erro no USB';
        _log('err', '${r['error']}');
        if (!quiet) toast('${r['error']}');
        return;
      }
      _log('info', 'USB aberto: ${r['name']} (${r['detail']})');
      gt.reset();
      await gt.handshake();
      gtConnected = true;
      _toggleCache.clear();
      gtStatus = 'GT-1 conectada';
      _log('info', 'GT-1 pronta. Patch atual: ${patchLabel(gt.currentPatch)}');
    } on PlatformException catch (e) {
      gtStatus = 'GT-1 desconectada';
      _log('err', e.message ?? e.code);
      if (!quiet) toast(e.message ?? e.code);
    } catch (e) {
      gtConnected = false;
      gtStatus = 'GT-1 sem resposta';
      _log('err', '$e');
      if (!quiet) toast('A GT-1 não respondeu. Desligue e ligue o cabo e tente de novo.');
    } finally {
      gtBusy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectGt() async {
    await gt.goodbye();
    gt.reset();
    await Native.usbClose();
    gtConnected = false;
    gtStatus = 'GT-1 desconectada';
    notifyListeners();
  }

  // ---------------------------------------------------------------- Pedal
  Future<bool> ensureBluetoothPermission() async {
    final sdk = await Native.sdkInt();
    if (sdk >= 31) {
      final r = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
      return r.values.every((s) => s.isGranted);
    }
    return (await Permission.locationWhenInUse.request()).isGranted;
  }

  Future<String?> startBleScan() async {
    bleFound.clear();
    notifyListeners();
    try {
      await Native.bleScanStart();
      return null;
    } on PlatformException catch (e) {
      return e.message;
    }
  }

  Future<void> stopBleScan() async {
    try {
      await Native.bleScanStop();
    } catch (_) {}
  }

  Future<bool> connectPedal({String? bleAddress, int? midiId}) async {
    pedalStatus = 'Conectando ao pedal…';
    notifyListeners();
    try {
      final r = bleAddress != null ? await Native.pedalOpenBle(bleAddress) : await Native.pedalOpenMidi(midiId!);
      pedalConnected = true;
      pedalStatus = 'Pedal: ${r['name'] ?? 'conectado'}';
      _log('info', 'Pedal conectado: ${r['name']}');
      return true;
    } on PlatformException catch (e) {
      pedalConnected = false;
      pedalStatus = 'Pedal desconectado';
      _log('err', e.message ?? e.code);
      toast(e.message ?? 'Não consegui conectar ao pedal');
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<void> disconnectPedal() async {
    await Native.pedalClose();
    pedalConnected = false;
    pedalStatus = 'Pedal desconectado';
    notifyListeners();
  }

  void startLearning(int? row) {
    learningRow = row;
    notifyListeners();
  }

  void _onPedal(List<int> d) {
    final m = PedalMsg.parse(d);
    if (m == null) {
      _log('in', 'Pedal  ${hex(d)}');
      return;
    }
    _log('in', 'Pedal  $m');

    final lr = learningRow;
    if (lr != null && lr < config.rows.length) {
      if (m.val == 0 && m.type != 'pc') return; // espera o "pisar", não o "soltar"
      final row = config.rows[lr];
      row.trigger = Trigger(m.type, m.ch, m.num);
      learningRow = null;
      _log('info', 'Botão ${row.name} aprendido: ${row.trigger!.describe()}');
      flashRow(lr);
      save();
      return;
    }

    for (var i = 0; i < config.rows.length; i++) {
      final row = config.rows[i];
      final t = row.trigger;
      if (t == null || !t.matches(m)) continue;
      if (row.ignoreZero && m.val == 0 && m.type != 'pc') continue;
      runAction(i);
    }
  }

  void flashRow(int i) {
    flash.value = i;
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (flash.value == i) flash.value = null;
    });
  }

  // ---------------------------------------------------------------- ações
  Future<void> runAction(int i) async {
    if (i >= config.rows.length) return;
    final row = config.rows[i];
    flashRow(i);
    if (row.kind == ActionKind.none) return;
    if (!gtConnected) {
      _log('err', 'GT-1 não conectada; botão ${row.name} ignorado.');
      return;
    }
    final from = config.rangeFrom < config.rangeTo ? config.rangeFrom : config.rangeTo;
    final to = config.rangeFrom < config.rangeTo ? config.rangeTo : config.rangeFrom;
    final cur = gt.currentPatch ?? from;
    try {
      switch (row.kind) {
        case ActionKind.patch:
          await _goto(row.patch);
        case ActionKind.next:
          {
            var n = cur + 1;
            if (n > to || n < from) n = from;
            await _goto(n);
          }
        case ActionKind.prev:
          {
            var n = cur - 1;
            if (n < from || n > to) n = to;
            await _goto(n);
          }
        case ActionKind.ab:
          {
            final useB = !(_abState[i] ?? false);
            _abState[i] = useB;
            await _goto(useB ? row.patchB : row.patch);
          }
        case ActionKind.toggle:
          {
            final a = row.addr;
            if (a == null) {
              toast('Botão ${row.name}: toque em "Aprender efeito" primeiro.');
              return;
            }
            final v = await gt.toggle(a, fallback: _toggleCache[a]);
            _toggleCache[a] = v;
            _log('info', '${row.fxName.isEmpty ? 'Efeito' : row.fxName} ${v == 1 ? 'LIGADO' : 'DESLIGADO'}');
          }
        case ActionKind.none:
          break;
      }
    } catch (e) {
      _log('err', '$e');
    }
    notifyListeners();
  }

  /// Estado conhecido de um efeito: 1 ligado, 0 desligado, null desconhecido.
  int? effectState(int addr) => _toggleCache[addr];

  /// Botões ◀ ▶ da tela Palco (percorre todos os patches).
  Future<void> stepPatch(int delta) async {
    if (!gtConnected) {
      toast('Conecte a GT-1 primeiro.');
      return;
    }
    var n = (gt.currentPatch ?? 0) + delta;
    if (n < 0) n = patchCount - 1;
    if (n >= patchCount) n = 0;
    await gotoPatch(n);
  }

  Future<void> gotoPatch(int n) async {
    if (!gtConnected) {
      toast('Conecte a GT-1 primeiro.');
      return;
    }
    try {
      await _goto(n);
    } catch (e) {
      _log('err', '$e');
    }
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  Future<void> _goto(int n) async {
    await gt.selectPatch(n);
    _toggleCache.clear();
  }

  /// Usado pelo "Aprender efeito".
  void setLearnedEffect(int row, int addr, int value) {
    final r = config.rows[row];
    r.kind = ActionKind.toggle;
    r.addr = addr;
    if (r.fxName.isEmpty) r.fxName = 'Efeito ${hex(intToAddr(addr).sublist(2))}';
    _toggleCache[addr] = value;
    _log('info', 'Botão ${r.name} controla o endereço ${hex(intToAddr(addr))}');
    save();
  }
}
