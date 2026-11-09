import 'dart:async';

import 'package:dlna/dlna.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/cast_service.dart';
import '../../ui/glass.dart';
import '../../ui/tint.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/media.dart';
import '../../ui/widgets/sheet.dart';
import '../settings/widgets/settings_ui.dart';

/// "Play S1 E3" → "Play S1 E3 on Living Room TV" while a TV is chosen.
String playOn(String label, DlnaDevice? tv) =>
    tv == null ? label : '$label on ${tv.friendlyName}';

const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';
final _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

/// The IPv4 address in what the user typed, or null. Arabic and Persian
/// digits count, and so do the decimal separators other keyboards offer
/// ("٫", ",") in place of ".".
String? parseTvAddress(String input) {
  final out = StringBuffer();
  for (final ch in input.trim().split('')) {
    final a = _arabicDigits.indexOf(ch), p = _persianDigits.indexOf(ch);
    out.write(
      a >= 0
          ? '$a'
          : p >= 0
          ? '$p'
          : ch == '٫' || ch == ','
          ? '.'
          : ch,
    );
  }
  final text = out.toString();
  final m = _ipv4.firstMatch(text);
  if (m == null) return null;
  for (var g = 1; g <= 4; g++) {
    if (int.parse(m.group(g)!) > 255) return null;
  }
  return text;
}

/// Starts looking for TVs. Tests swap it for one that opens no sockets.
final castSearchProvider = Provider<Future<void> Function()>(
  (ref) => ref.read(castServiceProvider).search,
);

/// Rebuilds with the chosen TV (null = this phone).
class CastTargetBuilder extends ConsumerWidget {
  const CastTargetBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, DlnaDevice? target) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cast = ref.watch(castServiceProvider);
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) => builder(context, cast.target),
    );
  }
}

/// The cast entry on Home and title pages: a glass cast icon, or the chosen
/// TV as a capsule with a Go dot. Both open [showCastPicker].
class CastButton extends StatelessWidget {
  const CastButton({super.key});

  @override
  Widget build(BuildContext context) => CastTargetBuilder(
    builder: (context, tv) {
      void open() => unawaited(showCastPicker(context));
      if (tv == null) {
        return GlassIconButton(
          icon: Icons.cast_rounded,
          label: 'Cast to a TV',
          onPressed: open,
        );
      }
      return Semantics(
        button: true,
        label: 'Playing on ${tv.friendlyName}. Change',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            open();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Glass(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cast_connected_rounded,
                    size: 20,
                    color: KColors.lamp,
                  ),
                  const SizedBox(width: KSpace.x2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      tv.friendlyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KType.label.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: KSpace.x2),
                  const SizedBox.square(
                    dimension: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: KColors.go,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Chooses where videos play before pressing Play: this phone or a TV.
/// Versions are then ranked for that screen and start on it.
Future<void> showCastPicker(BuildContext context) =>
    showGlassSheet<void>(context, builder: (_) => const CastPickerSheet());

class CastPickerSheet extends ConsumerWidget {
  const CastPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cast = ref.watch(castServiceProvider);
    void choose(DlnaDevice? d) {
      cast.selectTarget(d);
      Navigator.of(context).pop();
    }

    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpace.margin,
              KSpace.x2,
              KSpace.margin,
              KSpace.x1,
            ),
            child: Semantics(
              header: true,
              child: Text('Cast to a TV', style: KType.h2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
            child: Text(
              'Kinora picks versions the TV can play and starts them there.',
              style: KType.label.copyWith(color: KColors.haze),
            ),
          ),
          const SizedBox(height: KSpace.x2),
          Flexible(
            child: CastDeviceList(
              shrinkWrap: true,
              selected: cast.target?.udn,
              onPick: choose,
              leading: [
                CastDeviceRow(
                  name: 'This phone',
                  label: 'Play on this phone',
                  selected: cast.target == null,
                  onTap: () => choose(null),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A note under a TV: why it can't play this version, or what to expect.
typedef CastNote = ({String text, bool problem});

/// TVs on this Wi-Fi (searching on open), then a field for a TV's address
/// when discovery can't see it, and Search again. Shared by the cast picker
/// and the player's cast panel.
class CastDeviceList extends ConsumerStatefulWidget {
  const CastDeviceList({
    super.key,
    required this.onPick,
    this.leading = const [],
    this.trailing = const [],
    this.notes,
    this.selected,
    this.shrinkWrap = false,
    this.physics,
  });

  final ValueChanged<DlnaDevice> onPick;

  /// Rows above the TVs (e.g. "This phone").
  final List<Widget> leading;

  /// Rows after the TVs (e.g. "Choose a version the TV can play").
  final List<Widget> trailing;
  final List<CastNote> Function(DlnaDevice device)? notes;

  /// UDN of the chosen TV, marked with a check.
  final String? selected;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  ConsumerState<CastDeviceList> createState() => _CastDeviceListState();
}

class _CastDeviceListState extends ConsumerState<CastDeviceList> {
  final _address = TextEditingController();
  String? _addressError;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(castSearchProvider)());
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _add() {
    final host = parseTvAddress(_address.text);
    setState(
      () => _addressError = host == null
          ? 'That isn’t an address. It looks like 192.168.1.20.'
          : null,
    );
    if (host != null)
      unawaited(ref.read(castServiceProvider).addByAddress(host));
  }

  @override
  Widget build(BuildContext context) {
    final cast = ref.watch(castServiceProvider);
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) => ListView(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.physics,
        padding: const EdgeInsets.only(bottom: KSpace.x4),
        children: [
          ...widget.leading,
          for (final d in cast.devices)
            CastDeviceRow(
              name: d.friendlyName,
              detail: d.modelName,
              label: 'Cast to ${d.friendlyName}',
              notes: widget.notes?.call(d) ?? const [],
              selected: d.udn == widget.selected,
              onTap: () => widget.onPick(d),
            ),
          if (cast.searching)
            _Line(
              'Looking for TVs on this Wi-Fi…',
              live: true,
              style: KType.label.copyWith(color: KColors.haze),
            )
          else if (cast.message != null)
            _Line(cast.message!, live: true, style: KType.body),
          ...widget.trailing,
          const SizedBox(height: KSpace.x2),
          _Line(
            'TV not listed? Enter its address. The TV shows it in '
            'Settings › Network.',
            style: KType.label.copyWith(color: KColors.haze),
          ),
          GlassField(
            controller: _address,
            label: 'TV address',
            hint: '192.168.1.20',
            fieldKey: const ValueKey('tv-address'),
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            onSubmitted: (_) => _add(),
          ),
          if (_addressError != null)
            _Line(
              _addressError!,
              live: true,
              style: KType.label.copyWith(color: KColors.cut),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpace.margin,
              KSpace.x1,
              KSpace.margin,
              0,
            ),
            child: GlassGroup(
              child: Wrap(
                spacing: KSpace.x3,
                runSpacing: KSpace.x3,
                children: [
                  GlassButton(
                    label: 'Add TV',
                    icon: Icons.add_rounded,
                    onPressed: _add,
                  ),
                  GlassButton(
                    label: 'Search again',
                    icon: Icons.refresh_rounded,
                    onPressed: cast.searching
                        ? null
                        : () => unawaited(ref.read(castSearchProvider)()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {required this.style, this.live = false});

  final String text;
  final TextStyle style;
  final bool live;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: KSpace.margin,
      vertical: KSpace.x2,
    ),
    child: Semantics(
      liveRegion: live,
      child: Text(text, style: style),
    ),
  );
}

/// One place to play: name, model and notes, a check when chosen. No
/// leading icon: the name says what it is.
class CastDeviceRow extends StatelessWidget {
  const CastDeviceRow({
    super.key,
    required this.name,
    required this.label,
    required this.onTap,
    this.detail,
    this.notes = const [],
    this.selected = false,
  });

  final String name;

  /// What a tap does, for screen readers ("Cast to Living Room TV").
  final String label;
  final String? detail;
  final List<CastNote> notes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    label: [
      label,
      if (selected) 'Chosen',
      ?detail,
      for (final n in notes) n.text,
    ].join('. '),
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KSpace.margin,
          vertical: KSpace.x3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: KType.title),
                  if (detail != null)
                    Text(
                      detail!,
                      style: KType.label.copyWith(color: KColors.haze),
                    ),
                  for (final n in notes)
                    Text(
                      n.text,
                      style: KType.label.copyWith(
                        color: n.problem ? KColors.marquee : KColors.haze,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox.square(
              dimension: 24,
              child: selected
                  ? Icon(Icons.check_rounded, color: KinoraTint.of(context))
                  : null,
            ),
          ],
        ),
      ),
    ),
  );
}
