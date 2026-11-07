import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gt1.dart';
import 'model.dart';
import 'native.dart';
import 'state.dart';
import 'theme.dart';

// =====================================================================================
// Estrutura principal: Palco · Botões · Monitor
// =====================================================================================

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});
  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  StreamSubscription<String>? _msgSub;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    _msgSub = s.messages.stream.listen((m) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(children: [
          AppMark(size: 30),
          SizedBox(width: 12),
          Text('Pedal Ponte'),
        ]),
        actions: [
          AnimatedBuilder(
            animation: s,
            builder: (context, _) => PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) => _menu(context, v),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(value: 'screen', checked: s.config.keepScreenOn, child: const Text('Manter tela ligada')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.copy_all), title: Text('Copiar configuração'))),
                const PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.content_paste), title: Text('Colar configuração'))),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'about', child: ListTile(leading: Icon(Icons.info_outline), title: Text('Sobre'))),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: tab, children: [
          StagePage(state: s),
          ButtonsPage(state: s),
          MonitorPage(state: s),
        ]),
      ),
      floatingActionButton: tab == 1
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.blue,
              foregroundColor: Colors.white,
              onPressed: () {
                final n = s.config.rows.length;
                s.config.rows.add(ButtonMap(name: String.fromCharCode(65 + (n % 26))));
                s.save();
                openRowEditor(context, s, n);
              },
              icon: const Icon(Icons.add),
              label: const Text('Adicionar botão'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'Palco'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Botões'),
          NavigationDestination(icon: Icon(Icons.terminal), label: 'Monitor'),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context, String v) async {
    switch (v) {
      case 'screen':
        await s.setKeepScreenOn(!s.config.keepScreenOn);
      case 'export':
        await Clipboard.setData(ClipboardData(text: s.exportConfig()));
        s.toast('Configuração copiada. Cole num bloco de notas para guardar.');
      case 'import':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final ok = s.importConfig(data?.text ?? '');
        s.toast(ok ? 'Configuração aplicada.' : 'O texto copiado não é uma configuração válida.');
      case 'about':
        if (!context.mounted) return;
        showAboutDialog(
          context: context,
          applicationName: 'Pedal Ponte',
          applicationVersion: '1.1.2',
          applicationIcon: const AppMark(size: 44),
          children: const [
            Text('Liga pedais MIDI (como o M-Vave Chocolate Plus) à BOSS GT-1, usando o celular como ponte.\n\n'
                'App independente, sem ligação com a Roland/BOSS ou a M-Vave. BOSS e GT-1 são marcas dos seus donos.'),
          ],
        );
    }
  }
}

/// Marca do app: quadrado azul com o símbolo de ponte.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blueBright, AppColors.blue, AppColors.blueDeep],
        ),
      ),
      child: Icon(Icons.swap_horiz_rounded, color: Colors.white, size: size * 0.66),
    );
  }
}

// =====================================================================================
// Palco
// =====================================================================================

class StagePage extends StatelessWidget {
  const StagePage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 700;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(children: [
              Expanded(child: _GtTile(state: state)),
              const SizedBox(width: 12),
              Expanded(child: _PedalTile(state: state)),
            ]),
            const SizedBox(height: 14),
            PatchDisplay(state: state),
            SectionLabel('Pedal',
                trailing: Text('toque para testar', style: TextStyle(color: AppColors.muted.withValues(alpha: 0.8), fontSize: 12))),
            if (state.config.rows.isEmpty)
              const _EmptyHint(icon: Icons.tune, text: 'Nenhum botão configurado. Vá em "Botões" para adicionar.')
            else
              ValueListenableBuilder<int?>(
                valueListenable: state.flash,
                builder: (context, hit, _) => GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: wide ? 4 : 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.08,
                  children: [
                    for (var i = 0; i < state.config.rows.length; i++)
                      FootswitchTile(state: state, index: i, hit: hit == i),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.connected,
    required this.busy,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool connected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: connected ? AppColors.blue.withValues(alpha: 0.55) : AppColors.line),
      ),
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? AppColors.blue.withValues(alpha: 0.18) : AppColors.surface2,
              ),
              child: Icon(icon, size: 22, color: connected ? AppColors.blueBright : AppColors.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: connected ? AppColors.blueBright : AppColors.muted)),
              ]),
            ),
            if (busy)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Led(on: connected),
          ]),
        ),
      ),
    );
  }
}

class _GtTile extends StatelessWidget {
  const _GtTile({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return _StatusTile(
      icon: Icons.usb_rounded,
      title: 'GT-1',
      subtitle: state.gtBusy ? 'Conectando…' : (state.gtConnected ? 'Conectada' : 'Conectar'),
      connected: state.gtConnected,
      busy: state.gtBusy,
      onTap: () {
        if (!state.gtConnected) {
          state.connectGt();
        } else {
          _confirmDisconnect(context, 'GT-1', 'Ligada pelo cabo USB.', state.disconnectGt);
        }
      },
    );
  }
}

class _PedalTile extends StatelessWidget {
  const _PedalTile({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final name = state.pedalStatus.startsWith('Pedal: ') ? state.pedalStatus.substring(7) : 'Conectado';
    return _StatusTile(
      icon: Icons.bluetooth_rounded,
      title: 'Pedal',
      subtitle: state.pedalConnected ? name : 'Procurar',
      connected: state.pedalConnected,
      busy: false,
      onTap: () {
        if (!state.pedalConnected) {
          openPedalPicker(context, state);
        } else {
          _confirmDisconnect(context, 'Pedal', name, state.disconnectPedal);
        }
      },
    );
  }
}

Future<void> _confirmDisconnect(BuildContext context, String what, String detail, Future<void> Function() action) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Led(on: true, size: 12),
            const SizedBox(width: 12),
            Text('$what conectado', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.bad),
            icon: const Icon(Icons.link_off),
            label: const Text('Desconectar'),
            onPressed: () {
              Navigator.of(ctx).pop();
              action();
            },
          ),
        ]),
      ),
    ),
  );
}

String patchKind(int? n) {
  if (n == null) return 'Conecte a GT-1 para ver o patch';
  return n < 99 ? 'Banco do usuário · ${pad2(n + 1)}' : 'Preset de fábrica · ${pad2(n - 98)}';
}

/// Visor grande do patch atual, com ▲ ▼ para trocar na mão.
class PatchDisplay extends StatelessWidget {
  const PatchDisplay({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final n = state.gtConnected ? state.gt.currentPatch : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A1C40), Color(0xFF070B14)],
        ),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.12), blurRadius: 30, spreadRadius: -6)],
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('PATCH ATUAL',
                style: TextStyle(fontSize: 11.5, letterSpacing: 2, fontWeight: FontWeight.w700, color: AppColors.blueBright)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                n == null ? '— —' : patchLabel(n),
                style: TextStyle(
                  fontSize: 76,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: n == null ? AppColors.muted.withValues(alpha: 0.5) : Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: n == null ? null : [Shadow(color: AppColors.blue.withValues(alpha: 0.8), blurRadius: 24)],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(patchKind(n), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ]),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          _RoundButton(icon: Icons.keyboard_arrow_up_rounded, onTap: () => state.stepPatch(1)),
          const SizedBox(height: 10),
          _RoundButton(icon: Icons.keyboard_arrow_down_rounded, onTap: () => state.stepPatch(-1)),
        ]),
      ]),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 28)),
      ),
    );
  }
}

/// Um botão do pedal, desenhado como um pedal de chão.
class FootswitchTile extends StatelessWidget {
  const FootswitchTile({super.key, required this.state, required this.index, required this.hit});
  final AppState state;
  final int index;
  final bool hit;

  @override
  Widget build(BuildContext context) {
    final r = state.config.rows[index];
    final effectOn = r.kind == ActionKind.toggle && r.addr != null && state.effectState(r.addr!) == 1;
    final ledOn = hit || effectOn;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        state.runAction(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: hit ? const [Color(0xFF1B3F86), Color(0xFF0E1E40)] : const [AppColors.surface2, AppColors.surface],
          ),
          border: Border.all(color: hit ? AppColors.blueBright : AppColors.line, width: hit ? 2 : 1),
          boxShadow: hit ? [BoxShadow(color: AppColors.blue.withValues(alpha: 0.45), blurRadius: 22)] : const [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Led(on: ledOn, size: 11),
            const Spacer(),
            Icon(r.trigger == null ? Icons.link_off_rounded : Icons.link_rounded,
                size: 16, color: r.trigger == null ? AppColors.warn : AppColors.muted),
          ]),
          const Spacer(),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1)),
                const SizedBox(height: 6),
                Text(r.shortLabel(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ]),
            ),
            const SizedBox(width: 6),
            _Knob(pressed: hit),
          ]),
        ]),
      ),
    );
  }
}

/// A "chave" metálica do pedal.
class _Knob extends StatelessWidget {
  const _Knob({required this.pressed});
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: pressed ? 0.88 : 1,
      duration: const Duration(milliseconds: 90),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.3, -0.4),
            colors: [Color(0xFF9AA3B5), Color(0xFF3A4150), Color(0xFF1A1E27)],
            stops: [0, 0.55, 1],
          ),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(children: [
        Icon(icon, size: 40, color: AppColors.line),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
      ]),
    );
  }
}

// =====================================================================================
// Botões
// =====================================================================================

IconData actionIcon(ActionKind k) {
  switch (k) {
    case ActionKind.patch:
      return Icons.bookmark_border_rounded;
    case ActionKind.next:
      return Icons.skip_next_rounded;
    case ActionKind.prev:
      return Icons.skip_previous_rounded;
    case ActionKind.ab:
      return Icons.swap_horiz_rounded;
    case ActionKind.toggle:
      return Icons.power_settings_new_rounded;
    case ActionKind.none:
      return Icons.block_rounded;
  }
}

class ButtonsPage extends StatelessWidget {
  const ButtonsPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          Card(
            color: AppColors.blueDeep.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: AppColors.blue.withValues(alpha: 0.35)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lightbulb_outline_rounded, color: AppColors.blueBright),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Toque em "Aprender" e pise no botão do pedal. Depois toque no cartão para escolher o que ele faz na GT-1.',
                      style: TextStyle(height: 1.4)),
                ),
              ]),
            ),
          ),
          const SectionLabel('Botões do pedal'),
          if (state.config.rows.isEmpty)
            const _EmptyHint(icon: Icons.touch_app_outlined, text: 'Nenhum botão ainda. Toque em "Adicionar botão".'),
          for (var i = 0; i < state.config.rows.length; i++)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: ButtonCard(state: state, index: i)),
        ],
      ),
    );
  }
}

class NameBadge extends StatelessWidget {
  const NameBadge({super.key, required this.name, this.size = 48});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blue, AppColors.blueDeep],
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : (name.length > 2 ? name.substring(0, 2) : name),
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }
}

class TriggerChip extends StatelessWidget {
  const TriggerChip({super.key, required this.trigger, this.learning = false});
  final Trigger? trigger;
  final bool learning;

  @override
  Widget build(BuildContext context) {
    final missing = trigger == null && !learning;
    final color = learning ? AppColors.blueBright : (missing ? AppColors.warn : AppColors.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: learning ? AppColors.blue.withValues(alpha: 0.15) : AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: learning ? AppColors.blue : AppColors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (learning) const Led(on: true, size: 7) else Icon(missing ? Icons.link_off_rounded : Icons.settings_input_component_rounded, size: 13, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            learning ? 'Pise no botão do pedal…' : (trigger?.describe() ?? 'Sinal do pedal não aprendido'),
            overflow: TextOverflow.ellipsis,
            style: monoStyle.copyWith(color: learning ? AppColors.text : color, fontSize: 12),
          ),
        ),
      ]),
    );
  }
}

class ButtonCard extends StatelessWidget {
  const ButtonCard({super.key, required this.state, required this.index});
  final AppState state;
  final int index;

  @override
  Widget build(BuildContext context) {
    final r = state.config.rows[index];
    final learning = state.learningRow == index;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: learning ? AppColors.blue : AppColors.line, width: learning ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: () => openRowEditor(context, state, index),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            NameBadge(name: r.name),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(actionIcon(r.kind), size: 17, color: AppColors.blueBright),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(r.describeAction(),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ]),
                const SizedBox(height: 8),
                TriggerChip(trigger: r.trigger, learning: learning),
              ]),
            ),
            const SizedBox(width: 10),
            learning
                ? TextButton(onPressed: () => state.startLearning(null), child: const Text('Cancelar'))
                : OutlinedButton(onPressed: () => state.startLearning(index), child: const Text('Aprender')),
          ]),
        ),
      ),
    );
  }
}

Future<void> openRowEditor(BuildContext context, AppState state, int index) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RowEditor(state: state, index: index),
  );
}

class RowEditor extends StatefulWidget {
  const RowEditor({super.key, required this.state, required this.index});
  final AppState state;
  final int index;

  @override
  State<RowEditor> createState() => _RowEditorState();
}

class _RowEditorState extends State<RowEditor> {
  late final TextEditingController nameCtl;
  late final TextEditingController fxCtl;

  AppState get s => widget.state;
  bool get valid => widget.index < s.config.rows.length;
  ButtonMap get r => s.config.rows[widget.index];

  @override
  void initState() {
    super.initState();
    nameCtl = TextEditingController(text: valid ? r.name : '');
    fxCtl = TextEditingController(text: valid ? r.fxName : '');
  }

  @override
  void dispose() {
    nameCtl.dispose();
    fxCtl.dispose();
    super.dispose();
  }

  void _changed() {
    s.save();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        if (!valid) return const SizedBox.shrink();
        final learning = s.learningRow == widget.index;
        final mq = MediaQuery.of(context);
        // Espaço para o teclado e para a barra de navegação do Android (tela de borda a borda).
        final bottomSpace = mq.viewInsets.bottom + mq.padding.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomSpace),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
           Flexible(
            child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // ---- cabeçalho
              Row(children: [
                NameBadge(name: r.name, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: nameCtl,
                    maxLength: 12,
                    decoration: const InputDecoration(labelText: 'Nome do botão', counterText: ''),
                    onChanged: (v) {
                      r.name = v.isEmpty ? '?' : v;
                      _changed();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Remover botão',
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.bad),
                  onPressed: () {
                    s.learningRow = null;
                    s.config.rows.removeAt(widget.index);
                    Navigator.of(context).pop();
                    s.save();
                  },
                ),
              ]),

              // ---- sinal do pedal
              const SectionLabel('Sinal do pedal'),
              Row(children: [
                Expanded(child: TriggerChip(trigger: r.trigger, learning: learning)),
                const SizedBox(width: 10),
                learning
                    ? TextButton(onPressed: () => s.startLearning(null), child: const Text('Cancelar'))
                    : OutlinedButton.icon(
                        icon: const Icon(Icons.sensors_rounded, size: 18),
                        label: const Text('Aprender'),
                        onPressed: () => s.startLearning(widget.index),
                      ),
              ]),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ignorar quando solta o botão'),
                subtitle: const Text('Desligue se o pedal estiver no modo liga/desliga (toggle).',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                value: r.ignoreZero,
                onChanged: (v) {
                  r.ignoreZero = v;
                  _changed();
                },
              ),

              // ---- ação
              const SectionLabel('O que faz na GT-1'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in ActionKind.values)
                  ChoiceChip(
                    avatar: Icon(actionIcon(k), size: 18, color: r.kind == k ? Colors.white : AppColors.muted),
                    label: Text(actionLabels[k]!),
                    selected: r.kind == k,
                    showCheckmark: false,
                    onSelected: (_) {
                      r.kind = k;
                      _changed();
                    },
                  ),
              ]),
              const SizedBox(height: 16),
              _actionSettings(context),
              const SizedBox(height: 8),
            ]),
            ),
           ),

           // ---- rodapé fixo
           Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Testar'),
                    onPressed: () => s.runAction(widget.index),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Concluir')),
                ),
              ]),
           ),
          ]),
        );
      },
    );
  }

  Widget _actionSettings(BuildContext context) {
    switch (r.kind) {
      case ActionKind.patch:
        return PatchField(label: 'Patch', value: r.patch, onChanged: (v) {
          r.patch = v;
          _changed();
        });
      case ActionKind.ab:
        return Row(children: [
          Expanded(child: PatchField(label: 'Primeiro', value: r.patch, onChanged: (v) {
            r.patch = v;
            _changed();
          })),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.swap_horiz_rounded, color: AppColors.muted)),
          Expanded(child: PatchField(label: 'Segundo', value: r.patchB, onChanged: (v) {
            r.patchB = v;
            _changed();
          })),
        ]);
      case ActionKind.next:
      case ActionKind.prev:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: PatchField(label: 'De', value: s.config.rangeFrom, onChanged: (v) {
              s.config.rangeFrom = v;
              _changed();
            })),
            const SizedBox(width: 12),
            Expanded(child: PatchField(label: 'Até', value: s.config.rangeTo, onChanged: (v) {
              s.config.rangeTo = v;
              _changed();
            })),
          ]),
          const SizedBox(height: 8),
          const Text('Ao passar do último, volta para o primeiro. A faixa vale para todos os botões de avançar e voltar.',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ]);
      case ActionKind.toggle:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: fxCtl,
            maxLength: 16,
            decoration: const InputDecoration(labelText: 'Nome do efeito (ex.: Delay)', counterText: ''),
            onChanged: (v) {
              r.fxName = v;
              _changed();
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(children: [
              Icon(r.addr == null ? Icons.help_outline_rounded : Icons.check_circle_rounded,
                  color: r.addr == null ? AppColors.warn : AppColors.blueBright),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  r.addr == null ? 'Ainda não sei qual efeito controlar.' : 'Efeito aprendido · ${hex(intToAddr(r.addr!))}',
                  style: r.addr == null ? null : monoStyle,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: Text(r.addr == null ? 'Aprender efeito' : 'Aprender de novo'),
            onPressed: () async {
              await showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => FxLearnDialog(state: s, row: widget.index),
              );
              if (valid) fxCtl.text = r.fxName;
            },
          ),
        ]);
      case ActionKind.none:
        return const Text('Este botão não faz nada na GT-1.', style: TextStyle(color: AppColors.muted));
    }
  }
}

/// Campo que mostra um patch e abre a grade de escolha.
class PatchField extends StatelessWidget {
  const PatchField({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final v = await showDialog<int>(context: context, builder: (_) => PatchPickerDialog(initial: value));
          if (v != null) onChanged(v);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(patchLabel(value), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ]),
            ),
            const Icon(Icons.unfold_more_rounded, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}

class PatchPickerDialog extends StatefulWidget {
  const PatchPickerDialog({super.key, required this.initial});
  final int initial;

  @override
  State<PatchPickerDialog> createState() => _PatchPickerDialogState();
}

class _PatchPickerDialogState extends State<PatchPickerDialog> {
  late bool user = widget.initial < 99;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Escolher patch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Usuário (U)')),
                ButtonSegment(value: false, label: Text('Preset (P)')),
              ],
              selected: {user},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => user = v.first),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: 99,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemBuilder: (context, i) {
                  final n = user ? i : i + 99;
                  final sel = n == widget.initial;
                  return Material(
                    color: sel ? AppColors.blue : AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: sel ? AppColors.blue : AppColors.line),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.of(context).pop(n),
                      child: Center(
                        child: Text(pad2(i + 1),
                            style: TextStyle(fontWeight: FontWeight.w700, color: sel ? Colors.white : AppColors.text)),
                      ),
                    ),
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ aprender efeito
class FxLearnDialog extends StatefulWidget {
  const FxLearnDialog({super.key, required this.state, required this.row});
  final AppState state;
  final int row;

  @override
  State<FxLearnDialog> createState() => _FxLearnDialogState();
}

enum _FxStage { reading, waiting, comparing, error }

class _FxLearnDialogState extends State<FxLearnDialog> {
  _FxStage stage = _FxStage.reading;
  String message = 'Lendo o som atual da GT-1…';
  Map<int, int>? before;
  StreamSubscription<List<int>>? live;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    live?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!widget.state.gtConnected) {
      setState(() {
        stage = _FxStage.error;
        message = 'Conecte a GT-1 primeiro.';
      });
      return;
    }
    try {
      before = await widget.state.gt.readEditBuffer();
      if (!mounted) return;
      live = widget.state.liveBytes.stream.listen((ev) {
        final addr = ev[0], value = ev[1];
        if (stage == _FxStage.waiting && (value == 0 || value == 1)) _finish(addr, value);
      });
      setState(() {
        stage = _FxStage.waiting;
        message = 'Na própria GT-1, ligue ou desligue o efeito que este botão vai controlar. Depois toque em "Pronto".';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        stage = _FxStage.error;
        message = 'Não consegui ler a GT-1: $e';
      });
    }
  }

  Future<void> _compare() async {
    setState(() {
      stage = _FxStage.comparing;
      message = 'Comparando…';
    });
    try {
      final after = await widget.state.gt.readEditBuffer();
      final changes = findOnOffChanges(before ?? {}, after);
      if (!mounted) return;
      if (changes.isEmpty) {
        setState(() {
          stage = _FxStage.waiting;
          message = 'Não vi nenhum efeito mudar. Ligue ou desligue só um efeito na GT-1 e toque em "Pronto" de novo.';
        });
        return;
      }
      _finish(changes.first.addr, changes.first.after);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        stage = _FxStage.error;
        message = 'Erro: $e';
      });
    }
  }

  void _finish(int addr, int value) {
    if (finished) return;
    finished = true;
    widget.state.setLearnedEffect(widget.row, addr, value);
    widget.state.toast('Efeito aprendido!');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final busy = stage == _FxStage.reading || stage == _FxStage.comparing;
    return AlertDialog(
      icon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.blue.withValues(alpha: 0.18)),
        child: busy
            ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2.5))
            : Icon(stage == _FxStage.error ? Icons.error_outline_rounded : Icons.auto_fix_high_rounded,
                color: stage == _FxStage.error ? AppColors.bad : AppColors.blueBright),
      ),
      title: const Text('Aprender efeito'),
      content: Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.45)),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: stage == _FxStage.waiting ? _compare : null, child: const Text('Pronto')),
      ],
    );
  }
}

// =====================================================================================
// Escolher pedal
// =====================================================================================

Future<void> openPedalPicker(BuildContext context, AppState state) async {
  final ok = await state.ensureBluetoothPermission();
  if (!context.mounted) return;
  if (!ok) state.toast('Sem a permissão de Bluetooth o app não encontra o pedal.');
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => PedalSheet(state: state, bluetoothAllowed: ok),
  );
  await state.stopBleScan();
}

class PedalSheet extends StatefulWidget {
  const PedalSheet({super.key, required this.state, required this.bluetoothAllowed});
  final AppState state;
  final bool bluetoothAllowed;

  @override
  State<PedalSheet> createState() => _PedalSheetState();
}

class _PedalSheetState extends State<PedalSheet> {
  List<Map<dynamic, dynamic>> midi = [];
  String? bleError;
  bool scanning = false;
  String? connecting;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final m = await Native.midiList();
      if (mounted) setState(() => midi = m.where((d) => d['transport'] == 'usb').toList());
    } catch (_) {}
    if (!widget.bluetoothAllowed || !mounted) return;
    setState(() {
      scanning = true;
      bleError = null;
    });
    final err = await widget.state.startBleScan();
    if (!mounted) return;
    setState(() {
      bleError = err;
      if (err != null) scanning = false;
    });
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => scanning = false);
    });
  }

  Future<void> _connect(String key, {String? ble, int? id}) async {
    setState(() => connecting = key);
    final ok = await widget.state.connectPedal(bleAddress: ble, midiId: id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => connecting = null);
    }
  }

  Widget _device(String key, IconData icon, String name, String detail, VoidCallback onTap) {
    final busy = connecting == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: CircleAvatar(
            backgroundColor: AppColors.blue.withValues(alpha: 0.18),
            child: Icon(icon, color: AppColors.blueBright, size: 20),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(detail, style: monoStyle.copyWith(color: AppColors.muted, fontSize: 11.5)),
          trailing: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chevron_right_rounded),
          onTap: connecting == null ? onTap : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final ble = widget.state.bleFound;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + MediaQuery.of(context).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(child: Text('Conectar pedal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
              IconButton(tooltip: 'Procurar de novo', onPressed: scanning ? null : _refresh, icon: const Icon(Icons.refresh_rounded)),
            ]),
            const SizedBox(height: 4),
            const Text('Ligue o Chocolate Plus e deixe-o perto do celular. Se ele já estiver conectado ao celular, aparece aqui como "Conectado ao celular" (no Chocolate Plus, o nome costuma ser FootCtrlPlus).',
                style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 14),
            if (scanning)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: ClipRRect(borderRadius: BorderRadius.all(Radius.circular(4)), child: LinearProgressIndicator(minHeight: 3)),
              ),
            if (bleError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.bad, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(bleError!, style: const TextStyle(color: AppColors.bad))),
                ]),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView(shrinkWrap: true, children: [
                for (final b in ble)
                  _device('ble:${b.address}', Icons.bluetooth_rounded, b.name, b.detail,
                      () => _connect('ble:${b.address}', ble: b.address)),
                for (final d in midi)
                  _device('usb:${d['id']}', Icons.usb_rounded, '${d['name']}', 'USB MIDI',
                      () => _connect('usb:${d['id']}', id: (d['id'] as num).toInt())),
                if (ble.isEmpty && midi.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(children: [
                      Icon(scanning ? Icons.bluetooth_searching_rounded : Icons.bluetooth_disabled_rounded,
                          size: 40, color: AppColors.line),
                      const SizedBox(height: 10),
                      Text(scanning ? 'Procurando pedais…' : 'Nenhum pedal encontrado.',
                          style: const TextStyle(color: AppColors.muted)),
                    ]),
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// =====================================================================================
// Monitor
// =====================================================================================

class MonitorPage extends StatelessWidget {
  const MonitorPage({super.key, required this.state});
  final AppState state;

  static String _time(DateTime t) => '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';

  static String _tagText(String k) => k == 'in' ? 'ENTRA' : k == 'out' ? 'SAI' : k == 'err' ? 'ERRO' : 'INFO';

  static Color _tagColor(String k) =>
      k == 'in' ? AppColors.blueBright : k == 'out' ? const Color(0xFFA78BFA) : k == 'err' ? AppColors.bad : AppColors.muted;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final items = state.logs.reversed.toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text('${items.length} mensagens',
                    style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Copiar tudo',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  final txt = state.logs.map((l) => '${_time(l.t)}  ${l.text}').join('\n');
                  Clipboard.setData(ClipboardData(text: txt));
                  state.toast('Monitor copiado.');
                },
              ),
              IconButton(tooltip: 'Limpar', icon: const Icon(Icons.delete_sweep_outlined), onPressed: state.clearLogs),
            ]),
          ),
          const Divider(),
          Expanded(
            child: items.isEmpty
                ? const _EmptyHint(icon: Icons.terminal, text: 'As mensagens do pedal e da GT-1 aparecem aqui.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final l = items[i];
                      final tagColor = _tagColor(l.kind);
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 64, child: Text(_time(l.t), style: monoStyle.copyWith(color: AppColors.muted, fontSize: 11.5))),
                        Container(
                          width: 44,
                          margin: const EdgeInsets.only(right: 10, top: 1),
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tagColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(_tagText(l.kind), style: TextStyle(color: tagColor, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                        ),
                        Expanded(child: Text(l.text, style: monoStyle.copyWith(fontSize: 11.5, color: AppColors.text))),
                      ]);
                    },
                  ),
          ),
        ]);
      },
    );
  }
}
