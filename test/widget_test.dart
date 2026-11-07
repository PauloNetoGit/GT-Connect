import 'package:flutter_test/flutter_test.dart';
import 'package:pontegt1/gt1.dart';
import 'package:pontegt1/model.dart';

void main() {
  test('troca para U99 gera o SysEx certo', () async {
    final sent = <List<int>>[];
    final gt = Gt1(send: (b) async => sent.add(b))..deviceId = 0x00;
    await gt.selectPatch(98);
    expect(hex(sent.single), 'F0 41 00 00 00 00 30 12 00 01 00 00 00 62 1D F7');
  });

  test('nomes dos patches', () {
    expect(patchLabel(0), 'U01');
    expect(patchLabel(98), 'U99');
    expect(patchLabel(99), 'P01');
    expect(patchLabel(197), 'P99');
  });

  test('acha o liga/desliga que mudou', () {
    final c = findOnOffChanges({10: 1, 11: 5, 12: 0}, {10: 0, 11: 6, 12: 0});
    expect(c.length, 1);
    expect(c.first.addr, 10);
  });

  test('pedal: CC e Program Change', () {
    final cc = PedalMsg.parse([0xB0, 20, 127])!;
    expect(cc.type, 'cc');
    expect(cc.num, 20);
    expect(PedalMsg.parse([0xC1, 3])!.ch, 1);
  });
}
