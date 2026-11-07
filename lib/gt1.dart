/// Protocolo da BOSS GT-1 (SysEx Roland, modelo 00 00 00 30).
///
///   F0 41 <dev> 00 00 00 30 <11=RQ1 | 12=DT1> <endereço x4> <dados | tamanho x4> <checksum> F7
///
/// - Patch atual: 00 01 00 00, 2 bytes (alto, baixo): 0–98 = U01–U99, 99–197 = P01–P99
/// - Som em edição (edit buffer): 60 00 xx xx
/// - Modo editor: 7F 00 00 01 = 01 (liga) / 00 (desliga)
library;

import 'dart:async';

const List<int> gtModel = [0x00, 0x00, 0x00, 0x30];
const int rq1Cmd = 0x11;
const int dt1Cmd = 0x12;
const List<int> addrPatch = [0x00, 0x01, 0x00, 0x00];
const List<int> addrEditorLevel = [0x7F, 0x00, 0x00, 0x00];
const List<int> addrEditorMode = [0x7F, 0x00, 0x00, 0x01];
const List<List<int>> editBlocks = [
  [0x60, 0x00, 0x00, 0x00],
  [0x60, 0x00, 0x08, 0x00],
  [0x60, 0x00, 0x10, 0x00],
];
const int editBlockSize = 1024;

int addrToInt(List<int> a) => ((a[0] * 128 + a[1]) * 128 + a[2]) * 128 + a[3];
List<int> intToAddr(int n) => [(n >> 21) & 127, (n >> 14) & 127, (n >> 7) & 127, n & 127];
int rolandChecksum(List<int> b) => (128 - (b.fold<int>(0, (s, x) => s + x) % 128)) % 128;
String hex(Iterable<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

class _Req {
  final int start, end;
  final Map<int, int> got = {};
  final Completer<Map<int, int>> done = Completer();
  Timer? timer, idle;
  _Req(this.start, this.end);

  void finish() {
    timer?.cancel();
    idle?.cancel();
    if (!done.isCompleted) done.complete(got);
  }
}

typedef SendFn = Future<void> Function(List<int> bytes);
typedef LogFn = void Function(String kind, String text);

class Gt1 {
  Gt1({required this.send, this.log});

  final SendFn send;
  final LogFn? log;

  int deviceId = 0x10;
  bool ready = false;
  int? currentPatch;

  /// Chamado quando a GT-1 muda de patch por conta própria (ou ecoa uma troca).
  void Function(int patch)? onPatch;

  /// Chamado quando a GT-1 manda sozinha um valor de 1 byte no som em edição.
  void Function(int addr, int value)? onLiveByte;

  final List<_Req> _pending = [];
  Completer<int?>? _identity;

  List<int> build(int cmd, List<int> addr, List<int> payload) {
    final body = [...addr, ...payload];
    return [0xF0, 0x41, deviceId, ...gtModel, cmd, ...body, rolandChecksum(body), 0xF7];
  }

  Future<void> _send(List<int> bytes, {bool quiet = false}) async {
    if (!quiet) log?.call('out', '→ GT-1  ${hex(bytes)}');
    await send(bytes);
  }

  Future<void> dt1(List<int> addr, List<int> data, {bool quiet = false}) =>
      _send(build(dt1Cmd, addr, data), quiet: quiet);

  Future<Map<int, int>> rq1(List<int> addr, int size,
      {Duration timeout = const Duration(milliseconds: 2500), bool quiet = false}) {
    final s = addrToInt(addr);
    final r = _Req(s, s + size);
    r.timer = Timer(timeout, () {
      _pending.remove(r);
      r.idle?.cancel();
      if (r.done.isCompleted) return;
      if (r.got.isNotEmpty) {
        r.done.complete(r.got);
      } else {
        r.done.completeError(TimeoutException('A GT-1 não respondeu'));
      }
    });
    _pending.add(r);
    _send(build(rq1Cmd, addr, intToAddr(size)), quiet: quiet).catchError((Object e) {
      _pending.remove(r);
      r.timer?.cancel();
      if (!r.done.isCompleted) r.done.completeError(e);
    });
    return r.done.future;
  }

  Future<int?> identity({Duration timeout = const Duration(milliseconds: 1500)}) async {
    final c = Completer<int?>();
    _identity = c;
    final t = Timer(timeout, () {
      if (!c.isCompleted) c.complete(null);
    });
    try {
      await _send([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]);
      return await c.future;
    } finally {
      t.cancel();
      _identity = null;
    }
  }

  /// Mesma sequência do BOSS TONE STUDIO: identidade, modo editor, patch atual.
  Future<void> handshake() async {
    ready = false;
    final id = await identity();
    if (id != null) {
      deviceId = id;
      log?.call('info', 'GT-1 respondeu. Device ID = ${hex([id])}');
    } else {
      log?.call('info', 'Sem resposta de identidade; usando Device ID ${hex([deviceId])}');
    }
    try {
      await rq1(addrEditorLevel, 1, timeout: const Duration(milliseconds: 1500));
    } catch (_) {}
    await dt1(addrEditorMode, [1]);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final m = await rq1(addrPatch, 2);
    final s = addrToInt(addrPatch);
    currentPatch = (m[s] ?? 0) * 128 + (m[s + 1] ?? 0);
    ready = true;
  }

  Future<void> goodbye() async {
    if (!ready) return;
    ready = false;
    try {
      await dt1(addrEditorMode, [0], quiet: true);
    } catch (_) {}
  }

  void reset() {
    ready = false;
    for (final r in [..._pending]) {
      r.timer?.cancel();
      r.idle?.cancel();
      if (!r.done.isCompleted) r.done.completeError(StateError('GT-1 desconectada'));
    }
    _pending.clear();
  }

  /// Toda mensagem completa que chega da GT-1 passa por aqui.
  void onMessage(List<int> d) {
    if (d.isEmpty || d[0] == 0xFE || d[0] == 0xF8) return;
    // resposta de identidade: F0 7E <dev> 06 02 41 ...
    if (d.length > 5 && d[0] == 0xF0 && d[1] == 0x7E && d[3] == 0x06 && d[4] == 0x02) {
      if (d[5] == 0x41 && _identity != null && !_identity!.isCompleted) _identity!.complete(d[2]);
      return;
    }
    if (d.length < 14 || d[0] != 0xF0 || d[1] != 0x41 || d[7] != dt1Cmd) return;
    for (var i = 0; i < 4; i++) {
      if (d[3 + i] != gtModel[i]) return;
    }
    final addr = d.sublist(8, 12);
    final payload = d.sublist(12, d.length - 2);
    final start = addrToInt(addr);

    var consumed = false;
    for (final r in [..._pending]) {
      if (start < r.end && start + payload.length > r.start) {
        consumed = true;
        for (var i = 0; i < payload.length; i++) {
          final k = start + i;
          if (k >= r.start && k < r.end) r.got[k] = payload[i];
        }
        if (r.got.length >= r.end - r.start) {
          _pending.remove(r);
          r.finish();
        } else {
          r.idle?.cancel();
          r.idle = Timer(const Duration(milliseconds: 350), () {
            _pending.remove(r);
            r.finish();
          });
        }
      }
    }
    if (consumed) return;

    if (start == addrToInt(addrPatch) && payload.length >= 2) {
      final n = payload[0] * 128 + payload[1];
      if (n != currentPatch) {
        currentPatch = n;
        onPatch?.call(n);
      }
      return;
    }
    if (addr[0] == 0x60 && payload.length == 1) onLiveByte?.call(start, payload[0]);
  }

  Future<void> selectPatch(int n) async {
    if (n < 0) n = 0;
    if (n > 197) n = 197;
    await dt1(addrPatch, [n >> 7, n & 127]);
    currentPatch = n;
  }

  /// Lê o estado atual do efeito e manda o contrário. Devolve o novo valor (0/1).
  Future<int> toggle(int addrInt, {int? fallback}) async {
    final addr = intToAddr(addrInt);
    int? cur;
    try {
      final m = await rq1(addr, 1, timeout: const Duration(milliseconds: 600), quiet: true);
      cur = m[addrInt];
    } catch (_) {}
    cur ??= fallback ?? 1;
    final nv = cur == 0 ? 1 : 0;
    await dt1(addr, [nv]);
    return nv;
  }

  Future<Map<int, int>> readEditBuffer() async {
    final all = <int, int>{};
    for (final b in editBlocks) {
      final m = await rq1(b, editBlockSize, timeout: const Duration(milliseconds: 4000), quiet: true);
      all.addAll(m);
    }
    return all;
  }
}

class OnOffChange {
  final int addr, before, after;
  const OnOffChange(this.addr, this.before, this.after);
}

/// Compara duas leituras do som em edição e devolve os endereços que viraram 0↔1.
List<OnOffChange> findOnOffChanges(Map<int, int> before, Map<int, int> after) {
  final out = <OnOffChange>[];
  after.forEach((k, v) {
    final b = before[k];
    if (b == null || b == v) return;
    if ((b == 0 || b == 1) && (v == 0 || v == 1)) out.add(OnOffChange(k, b, v));
  });
  out.sort((a, b) => a.addr.compareTo(b.addr));
  return out;
}
