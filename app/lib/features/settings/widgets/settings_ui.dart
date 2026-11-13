import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell.dart';
import '../../../app/desktop.dart';
import '../../../ui/glass.dart';
import '../../../ui/layout.dart';
import '../../../ui/tint.dart';
import '../../../ui/tokens.dart';
import '../../../ui/widgets/media.dart';
import '../../../ui/widgets/sheet.dart';

/// Whether motion should be skipped.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A settings page: back button, marquee title, optional intro, then plain
/// rows straight on Blackout (no cards).
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    required this.children,
    this.intro,
    this.back = true,
  });

  final String title;
  final String? intro;
  final List<Widget> children;
  final bool back;

  void _back(BuildContext context) =>
      context.canPop() ? context.pop() : context.go('/settings');

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + KSpace.x2,
        bottom: AppShell.bottomInset(context),
        right: KLayout.rest(context),
      ),
      children: [
        if (back && isDesktop)
          // A computer: a small back chevron beside the title (Esc and the
          // mouse's back button work too).
          Padding(
            // Top at 52 and left on the page's edge, as on a title page.
            padding: const EdgeInsets.fromLTRB(
              KSpace.margin,
              KSpace.x1,
              KSpace.margin,
              0,
            ),
            child: Row(
              children: [
                GlassGroup(
                  child: GlassIconButton(
                    icon: Icons.chevron_left_rounded,
                    label: 'Back',
                    size: 40,
                    onPressed: () => _back(context),
                  ),
                ),
                const SizedBox(width: KSpace.x3),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: KType.h1),
                  ),
                ),
              ],
            ),
          )
        else ...[
          if (back)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: KSpace.margin),
                child: GlassGroup(
                  child: GlassIconButton(
                    icon: Icons.chevron_left_rounded,
                    label: 'Back',
                    onPressed: () => _back(context),
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              KSpace.margin,
              back ? KSpace.x3 : KSpace.x4,
              KSpace.margin,
              0,
            ),
            child: Semantics(header: true, child: Text(title, style: KType.h1)),
          ),
        ],
        if (intro != null) Note(intro!, top: KSpace.x2),
        const SizedBox(height: KSpace.x2),
        ...children,
      ],
    ),
  );
}

/// A group title inside a page.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      KSpace.section,
      KSpace.margin,
      KSpace.x1,
    ),
    child: Semantics(header: true, child: Text(text, style: KType.h2)),
  );
}

/// A paragraph of secondary text at the page margin.
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.top = 0, this.color = KColors.haze});

  final String text;
  final double top;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(KSpace.margin, top, KSpace.margin, KSpace.x2),
    // About 65 characters a line at most (a wide window).
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Text(text, style: KType.body.copyWith(color: color)),
      ),
    ),
  );
}

/// Label with an optional explanation underneath.
class _Labels extends StatelessWidget {
  const _Labels({required this.label, this.detail, this.color});

  final String label;
  final String? detail;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: KType.title.copyWith(color: color)),
      if (detail != null && detail!.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(detail!, style: KType.label.copyWith(color: KColors.haze)),
      ],
    ],
  );
}

const _rowPadding = EdgeInsets.symmetric(
  horizontal: KSpace.margin,
  vertical: KSpace.x3,
);

/// A row that opens a sub-page; its current value sits under the label so
/// long values and large text never collide.
class NavRow extends StatelessWidget {
  const NavRow({
    super.key,
    required this.label,
    required this.onTap,
    this.value,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    label: value == null ? label : '$label, $value',
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: _rowPadding,
        child: Row(
          children: [
            Expanded(
              child: _Labels(label: label, detail: value),
            ),
            const SizedBox(width: KSpace.x2),
            const Icon(Icons.chevron_right_rounded, color: KColors.reel),
          ],
        ),
      ),
    ),
  );
}

/// A plain tappable row (an action, not a setting).
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.color = KColors.lamp,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Pressable(
    label: detail == null ? label : '$label. $detail',
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: _rowPadding,
        child: Row(
          children: [
            Icon(icon, color: onTap == null ? KColors.reel : color, size: 22),
            const SizedBox(width: KSpace.x4),
            Expanded(
              child: _Labels(
                label: label,
                detail: detail,
                color: onTap == null ? KColors.reel : color,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// An on/off setting: the whole row toggles.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: _rowPadding,
          child: Row(
            children: [
              Expanded(
                child: _Labels(label: label, detail: detail),
              ),
              const SizedBox(width: KSpace.x3),
              // On: a Lamp thumb on this screen's accent.
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: KinoraTint.of(context),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One of several mutually exclusive choices (with a check when chosen).
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    checked: selected,
    inMutuallyExclusiveGroup: true,
    label: detail == null ? label : '$label. $detail',
    excludeSemantics: true,
    child: InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: _rowPadding,
          child: Row(
            children: [
              Expanded(
                child: _Labels(label: label, detail: detail),
              ),
              const SizedBox(width: KSpace.x3),
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
    ),
  );
}

/// A short row of glass capsules (3–4 options), one selected.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      KSpace.x1,
      KSpace.margin,
      KSpace.x3,
    ),
    child: GlassGroup(
      child: Wrap(
        spacing: KSpace.x2,
        runSpacing: KSpace.x2,
        children: [
          for (final (v, label) in options)
            _Segment(
              label: label,
              selected: v == value,
              onTap: () => onChanged(v),
            ),
        ],
      ),
    ),
  );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: selected,
    inMutuallyExclusiveGroup: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
        child: Glass(
          tintStrength: selected ? 0.42 : 0.04,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: KType.title.copyWith(
              color: selected ? KColors.lamp : KColors.haze,
            ),
          ),
        ),
      ),
    ),
  );
}

/// A capsule text field on glass, with an optional Paste button. The
/// visible [label] above it is also what screen readers announce.
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.paste = false,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType,
    this.inputFormatters,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final bool paste;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Key? fieldKey;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    onChanged?.call(text);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      KSpace.margin,
      KSpace.x2,
      KSpace.margin,
      KSpace.x2,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(label, style: KType.label.copyWith(color: KColors.haze)),
        ),
        const SizedBox(height: KSpace.x2),
        GlassGroup(
          child: Glass(
            tintStrength: 0.06,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Row(
                children: [
                  const SizedBox(width: KSpace.x4 + 2),
                  Expanded(
                    child: Semantics(
                      label: label,
                      child: TextField(
                        key: fieldKey,
                        controller: controller,
                        obscureText: obscure,
                        onSubmitted: onSubmitted,
                        onChanged: onChanged,
                        keyboardType: keyboardType,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(2048),
                          ...?inputFormatters,
                        ],
                        style: KType.body,
                        cursorColor: KinoraTint.of(context),
                        keyboardAppearance: Brightness.dark,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration.collapsed(
                          hintText: hint,
                          hintStyle: KType.body.copyWith(color: KColors.reel),
                        ),
                      ),
                    ),
                  ),
                  if (paste)
                    Semantics(
                      container: true,
                      button: true,
                      label: 'Paste',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _paste,
                        child: const SizedBox.square(
                          dimension: 52,
                          child: Icon(
                            Icons.content_paste_rounded,
                            color: KColors.haze,
                            size: 20,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: KSpace.x4),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Asks before something is deleted. Returns true when confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final ok = await showGlassSheet<bool>(
    context,
    builder: (sheet) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpace.margin,
              KSpace.x3,
              KSpace.margin,
              KSpace.x2,
            ),
            child: Semantics(header: true, child: Text(title, style: KType.h2)),
          ),
          Note(message),
          SheetAction(
            icon: Icons.delete_outline_rounded,
            label: action,
            color: KColors.cut,
            onTap: () => Navigator.pop(sheet, true),
          ),
          SheetAction(
            icon: Icons.close_rounded,
            label: 'Cancel',
            onTap: () => Navigator.pop(sheet, false),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Lets the user pick one of [options] in a sheet; null when dismissed.
Future<T?> pickOption<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T current,
}) => showGlassSheet<T>(
  context,
  builder: (sheet) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.margin,
            KSpace.x3,
            KSpace.margin,
            KSpace.x2,
          ),
          child: Semantics(header: true, child: Text(title, style: KType.h2)),
        ),
        for (final (v, label) in options)
          ChoiceRow(
            label: label,
            selected: v == current,
            onTap: () => Navigator.pop(sheet, v),
          ),
        const SizedBox(height: KSpace.x2),
      ],
    ),
  ),
);

/// A short confirmation, floating above the tab bar (or the onboarding
/// Continue button) so it never covers a control.
void showNote(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        margin: EdgeInsets.fromLTRB(
          KSpace.x4,
          0,
          KSpace.x4,
          AppShell.bottomInset(context) - MediaQuery.paddingOf(context).bottom,
        ),
      ),
    );
}
