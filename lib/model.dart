/// Configuração dos botões do pedal e o que cada um faz na GT-1.
library;

const int patchCount = 198; // 0–98 = U01–U99, 99–197 = P01–P99

/// Converte um número vindo do JSON (int ou double) para int.
int _asInt(Object? v) => v is int ? v : (v is double ? v.toInt() : 0);

String pad2(int n) => n.toString().padLeft(2, '0');

String patchLabel(int? n) {
  if (n == null || n < 0) return '—';
  return n < 99 ? 'U${pad2(n + 1)}' : 'P${pad2(n - 98)}';
}

enum ActionKind { patch, next, prev, ab, toggle, none }

const actionLabels = <ActionKind, String>{
  ActionKind.patch: 'Ir para o patch',
  ActionKind.next: 'Próximo patch',
  ActionKind.prev: 'Patch anterior',
  ActionKind.ab: 'Alternar entre 2 patches',
  ActionKind.toggle: 'Liga/desliga efeito',
  ActionKind.none: 'Nada',
};

/// Uma mensagem vinda do pedal.
class PedalMsg {
  final String type; // cc, pc, note
  final int ch;
  final int num;
  final int val;
  const PedalMsg(this.type, this.ch, this.num, this.val);

  static PedalMsg? parse(List<int> d) {
    if (d.isEmpty) return null;
    final st = d[0] & 0xF0, ch = d[0] & 0x0F;
    int at(int i) => i < d.length ? d[i] : 0;
    switch (st) {
      case 0xB0:
        return PedalMsg('cc', ch, at(1), at(2));
      case 0xC0:
        return PedalMsg('pc', ch, at(1), 127);
      case 0x90:
        return PedalMsg('note', ch, at(1), at(2));
      case 0x80:
        return PedalMsg('note', ch, at(1), 0);
    }
    return null;
  }

  @override
  String toString() => '${Trigger(type, ch, num).describe()}  valor $val';
}

/// O sinal do pedal que dispara um botão.
class Trigger {
  final String type;
  final int ch;
  final int num;
  const Trigger(this.type, this.ch, this.num);

  bool matches(PedalMsg m) => m.type == type && m.ch == ch && m.num == num;

  String describe() {
    final c = 'canal ${ch + 1}';
    switch (type) {
      case 'cc':
        return 'CC $num · $c';
      case 'pc':
        return 'PC $num · $c';
      case 'note':
        return 'Nota $num · $c';
    }
    return '?';
  }

  Map<String, dynamic> toJson() => {'type': type, 'ch': ch, 'num': num};

  static Trigger? fromJson(dynamic j) {
    if (j is! Map) return null;
    return Trigger('${j['type']}', _asInt(j['ch']), _asInt(j['num']));
  }
}

class ButtonMap {
  String name;
  Trigger? trigger;
  bool ignoreZero;
  ActionKind kind;
  int patch;
  int patchB;
  int? addr; // endereço (inteiro) do liga/desliga do efeito
  String fxName;

  ButtonMap({
    required this.name,
    this.trigger,
    this.ignoreZero = true,
    this.kind = ActionKind.patch,
    this.patch = 0,
    this.patchB = 1,
    this.addr,
    this.fxName = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'trigger': trigger?.toJson(),
        'ignoreZero': ignoreZero,
        'kind': kind.name,
        'patch': patch,
        'patchB': patchB,
        'addr': addr,
        'fxName': fxName,
      };

  static ButtonMap fromJson(Map<dynamic, dynamic> j) => ButtonMap(
        name: '${j['name'] ?? '?'}',
        trigger: Trigger.fromJson(j['trigger']),
        ignoreZero: j['ignoreZero'] != false,
        kind: ActionKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => ActionKind.none),
        patch: (j['patch'] as num?)?.toInt() ?? 0,
        patchB: (j['patchB'] as num?)?.toInt() ?? 1,
        addr: (j['addr'] as num?)?.toInt(),
        fxName: '${j['fxName'] ?? ''}',
      );

  String describeAction() {
    switch (kind) {
      case ActionKind.patch:
        return 'Ir para ${patchLabel(patch)}';
      case ActionKind.ab:
        return '${patchLabel(patch)} ↔ ${patchLabel(patchB)}';
      case ActionKind.toggle:
        return addr == null ? 'Liga/desliga (não aprendido)' : 'Liga/desliga ${fxName.isEmpty ? 'efeito' : fxName}';
      default:
        return actionLabels[kind]!;
    }
  }

  String shortLabel() {
    switch (kind) {
      case ActionKind.patch:
        return patchLabel(patch);
      case ActionKind.ab:
        return '${patchLabel(patch)}↔${patchLabel(patchB)}';
      case ActionKind.next:
        return 'Próximo';
      case ActionKind.prev:
        return 'Anterior';
      case ActionKind.toggle:
        return fxName.isEmpty ? 'Efeito' : fxName;
      case ActionKind.none:
        return '—';
    }
  }
}

class AppConfig {
  List<ButtonMap> rows;
  int rangeFrom;
  int rangeTo;
  bool keepScreenOn;

  AppConfig({required this.rows, this.rangeFrom = 0, this.rangeTo = 98, this.keepScreenOn = true});

  factory AppConfig.defaults() => AppConfig(rows: [
        ButtonMap(name: 'A', kind: ActionKind.patch, patch: 0),
        ButtonMap(name: 'B', kind: ActionKind.patch, patch: 1),
        ButtonMap(name: 'C', kind: ActionKind.prev),
        ButtonMap(name: 'D', kind: ActionKind.next),
      ]);

  Map<String, dynamic> toJson() => {
        'rows': rows.map((r) => r.toJson()).toList(),
        'rangeFrom': rangeFrom,
        'rangeTo': rangeTo,
        'keepScreenOn': keepScreenOn,
      };

  static AppConfig fromJson(Map<dynamic, dynamic> j) {
    final rows = (j['rows'] as List?)?.whereType<Map>().map(ButtonMap.fromJson).toList();
    if (rows == null) throw const FormatException('Configuração sem botões');
    return AppConfig(
      rows: rows,
      rangeFrom: (j['rangeFrom'] as num?)?.toInt() ?? 0,
      rangeTo: (j['rangeTo'] as num?)?.toInt() ?? 98,
      keepScreenOn: j['keepScreenOn'] != false,
    );
  }
}
