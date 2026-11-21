import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:stremio/stremio.dart';

import '../../app/router.dart';
import '../../app/shell.dart';
import '../../services/trakt.dart';
import '../../ui/glass.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/page_header.dart';
import '../../ui/widgets/sheet.dart';
import '../../ui/widgets/states.dart';
import '../search/search_screen.dart' show PosterGrid;
import '../settings/widgets/settings_ui.dart';
import '../title/title_actions.dart' show ActionTile;

/// Your own Trakt lists.
final myListsProvider = FutureProvider.autoDispose<List<TraktList>>(
  (ref) => ref.read(traktSyncProvider).myLists(),
);

/// The titles on one of your lists.
final listItemsProvider = FutureProvider.autoDispose
    .family<List<MetaPreview>, int>(
      (ref, id) => ref.read(traktSyncProvider).listItems(id),
    );

/// Who can see a list, in plain words.
const privacyChoices = [
  ('private', 'Only you'),
  ('link', 'Anyone with the link'),
  ('friends', 'Your Trakt friends'),
  ('public', 'Everyone'),
];

String privacyLabel(String p) =>
    privacyChoices.where((c) => c.$1 == p).firstOrNull?.$2 ?? 'Only you';

String titlesLabel(int n) => n == 1 ? '1 title' : '$n titles';

/// Settings › Trakt › Your lists.
class ListsScreen extends ConsumerWidget {
  const ListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(myListsProvider);
    Future<void> make() async {
      final made = await editList(context);
      if (made != null) ref.invalidate(myListsProvider);
    }

    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: () => ref.refresh(myListsProvider.future),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: PageHeader(
                title: 'Your lists',
                actions: [
                  GlassButton(
                    label: 'New list',
                    icon: Icons.add_rounded,
                    compact: true,
                    onPressed: () => unawaited(make()),
                  ),
                ],
              ),
            ),
            switch (lists) {
              AsyncValue(value: final l?) when l.isEmpty => SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.playlist_add_rounded,
                  title: 'No lists yet',
                  message:
                      'Make one for a mood, a marathon, or what to show a '
                      'friend. It’s kept on Trakt, so other apps see it too.',
                  actionLabel: 'New list',
                  onAction: () => unawaited(make()),
                ),
              ),
              AsyncValue(value: final l?) => SliverToBoxAdapter(
                child: RowPanel(
                  rows: [
                    for (final list in l)
                      NavRow(
                        icon: list.privacy == 'private'
                            ? Icons.lock_outline_rounded
                            : Icons.public_rounded,
                        label: list.name,
                        value:
                            '${titlesLabel(list.count)}, '
                            '${privacyLabel(list.privacy)}',
                        onTap: () => unawaited(
                          context.push(
                            '/lists/${list.id}'
                            '?name=${Uri.encodeQueryComponent(list.name)}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              AsyncError(:final error) => SliverToBoxAdapter(
                child: ErrorState(
                  message: friendlyError(error),
                  onRetry: () => ref.invalidate(myListsProvider),
                ),
              ),
              _ => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            },
            SliverToBoxAdapter(
              child: SizedBox(
                height: AppShell.bottomInset(context) + KSpace.section,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of your lists: its titles, and renaming or deleting it.
class ListScreen extends ConsumerWidget {
  const ListScreen({super.key, required this.id, required this.name});

  final int id;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref
        .watch(myListsProvider)
        .value
        ?.where((l) => l.id == id)
        .firstOrNull;
    final items = ref.watch(listItemsProvider(id));
    final title = list?.name ?? name;
    final trakt = ref.read(traktSyncProvider);

    Future<void> edit() async {
      if (list == null) return;
      if (await editList(context, list: list) != null) {
        ref.invalidate(myListsProvider);
      }
    }

    Future<void> delete() async {
      final count = items.value?.length ?? list?.count ?? 0;
      final ok = await confirmAction(
        context,
        title: 'Delete “$title”?',
        message:
            'Trakt deletes the list${count == 0 ? '' : ' and its ${titlesLabel(count)}'}. '
            'The titles themselves stay where they are.',
        action: 'Delete list',
      );
      if (!ok || !context.mounted) return;
      try {
        await trakt.deleteList(id);
        ref.invalidate(myListsProvider);
        if (!context.mounted) return;
        context.pop();
        showNote(context, 'Deleted “$title”');
      } on Object catch (e) {
        if (context.mounted) showNote(context, friendlyError(e));
      }
    }

    Future<void> remove(MetaPreview m) async {
      try {
        await trakt.removeFromList(id, m);
        ref
          ..invalidate(listItemsProvider(id))
          ..invalidate(myListsProvider);
        if (!context.mounted) return;
        showNote(
          context,
          'Removed ${m.name}',
          undo: () async {
            await trakt.addToList(id, m);
            ref
              ..invalidate(listItemsProvider(id))
              ..invalidate(myListsProvider);
          },
        );
      } on Object catch (e) {
        if (context.mounted) showNote(context, friendlyError(e));
      }
    }

    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: () => ref.refresh(listItemsProvider(id).future),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: PageHeader(
                title: title,
                actions: [
                  GlassButton(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    compact: true,
                    onPressed: list == null ? null : () => unawaited(edit()),
                  ),
                  GlassButton(
                    label: 'Delete',
                    icon: Icons.delete_outline_rounded,
                    compact: true,
                    onPressed: () => unawaited(delete()),
                  ),
                ],
              ),
            ),
            if (list != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KSpace.margin,
                    0,
                    KSpace.margin,
                    KSpace.x3,
                  ),
                  child: Text(
                    '${privacyLabel(list.privacy)} can see it. Hold a title '
                    'to take it off.',
                    style: KType.small.copyWith(color: KColors.haze),
                  ),
                ),
              ),
            switch (items) {
              AsyncValue(value: final l?) when l.isEmpty =>
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.playlist_add_rounded,
                    title: 'Nothing on it yet',
                    message:
                        'On a movie or show’s page, choose Lists to add it '
                        'here.',
                  ),
                ),
              AsyncValue(value: final l?) => PosterGrid(
                items: l,
                onOpen: (m) => openTitle(context, type: m.type, id: m.id),
                onRemove: (m) => unawaited(remove(m)),
                removeLabel: 'Take off this list',
                bottom: AppShell.bottomInset(context) + KSpace.section,
              ),
              AsyncError(:final error) => SliverToBoxAdapter(
                child: ErrorState(
                  message: friendlyError(error),
                  onRetry: () => ref.invalidate(listItemsProvider(id)),
                ),
              ),
              _ => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// Makes a list, or renames [list] and changes who sees it. The list
/// as saved; null when cancelled.
Future<TraktList?> editList(BuildContext context, {TraktList? list}) =>
    showGlassSheet<TraktList>(
      context,
      builder: (sheet) => _ListSheet(list: list),
    );

class _ListSheet extends ConsumerStatefulWidget {
  const _ListSheet({this.list});

  final TraktList? list;

  @override
  ConsumerState<_ListSheet> createState() => _ListSheetState();
}

class _ListSheetState extends ConsumerState<_ListSheet> {
  late final _name = TextEditingController(text: widget.list?.name ?? '');
  late var _privacy = widget.list?.privacy ?? 'private';
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the list a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final trakt = ref.read(traktSyncProvider);
    try {
      final old = widget.list;
      final saved = old == null
          ? await trakt.createList(name, privacy: _privacy)
          : (id: old.id, name: name, privacy: _privacy, count: old.count);
      if (old != null) {
        await trakt.updateList(old.id, name: name, privacy: _privacy);
      }
      if (mounted) Navigator.pop(context, saved);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
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
          child: Semantics(
            header: true,
            child: Text(
              widget.list == null ? 'New list' : 'Edit list',
              style: KType.h2,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
          child: GlassField(
            controller: _name,
            label: 'Name',
            hint: 'Weekend anime',
            maxLength: 100,
            onSubmitted: (_) => unawaited(_save()),
          ),
        ),
        const SizedBox(height: KSpace.x3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.margin),
          child: Text(
            'Who can see it',
            style: KType.label.copyWith(color: KColors.haze),
          ),
        ),
        for (final (value, label) in privacyChoices)
          SheetAction(
            icon: value == 'private'
                ? Icons.lock_outline_rounded
                : Icons.public_rounded,
            label: label,
            selected: value == _privacy,
            onTap: () => setState(() => _privacy = value),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpace.margin,
              KSpace.x2,
              KSpace.margin,
              0,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: KType.small.copyWith(color: KColors.cut),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(KSpace.margin),
          child: GlassButton(
            label: _saving
                ? 'Saving…'
                : widget.list == null
                ? 'Make list'
                : 'Save',
            prominent: true,
            onPressed: _saving ? null : () => unawaited(_save()),
          ),
        ),
      ],
    ),
  );
}

/// The title page's Lists tile (signed in to Trakt): which of your lists
/// it's on, and a tap to add or take it off.
class ListsAction extends ConsumerWidget {
  const ListsAction({super.key, required this.meta});

  final MetaPreview meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ActionTile(
    icon: Icons.playlist_add_rounded,
    label: 'Lists',
    semanticLabel: 'Add ${meta.name} to one of your Trakt lists',
    onPressed: () => unawaited(
      showGlassSheet<void>(context, builder: (_) => _AddToLists(meta: meta)),
    ),
  );
}

class _AddToLists extends ConsumerStatefulWidget {
  const _AddToLists({required this.meta});

  final MetaPreview meta;

  @override
  ConsumerState<_AddToLists> createState() => _AddToListsState();
}

class _AddToListsState extends ConsumerState<_AddToLists> {
  List<TraktList>? _lists;
  Set<int> _on = {};
  final _busy = <int>{};
  String? _error;

  TraktSync get _trakt => ref.read(traktSyncProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final lists = await _trakt.myLists();
      final on = await _trakt.listsWith(widget.meta.id, lists);
      if (mounted) {
        setState(() {
          _lists = lists;
          _on = on;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _toggle(TraktList l) async {
    final add = !_on.contains(l.id);
    setState(() {
      _busy.add(l.id);
      add ? _on.add(l.id) : _on.remove(l.id);
      _error = null;
    });
    try {
      add
          ? await _trakt.addToList(l.id, widget.meta)
          : await _trakt.removeFromList(l.id, widget.meta);
      ref
        ..invalidate(myListsProvider)
        ..invalidate(listItemsProvider(l.id));
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          add ? _on.remove(l.id) : _on.add(l.id);
          _error = friendlyError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy.remove(l.id));
    }
  }

  Future<void> _make() async {
    final made = await editList(context);
    if (made == null || !mounted) return;
    setState(() => _lists = [...?_lists, made]);
    await _toggle(made);
  }

  @override
  Widget build(BuildContext context) {
    final lists = _lists;
    return SingleChildScrollView(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(widget.meta.name, style: KType.h2),
                ),
                Text(
                  'On your Trakt lists',
                  style: KType.label.copyWith(color: KColors.haze),
                ),
              ],
            ),
          ),
          if (lists == null && _error == null)
            const Padding(
              padding: EdgeInsets.all(KSpace.x4),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          for (final l in lists ?? const <TraktList>[])
            SheetAction(
              icon: _on.contains(l.id)
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              label: l.name,
              selected: _on.contains(l.id),
              onTap: () {
                if (!_busy.contains(l.id)) unawaited(_toggle(l));
              },
            ),
          if (lists != null || _error != null)
            SheetAction(
              icon: Icons.add_rounded,
              label: 'New list',
              onTap: () => unawaited(_make()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KSpace.margin,
                KSpace.x2,
                KSpace.margin,
                0,
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: KType.small.copyWith(color: KColors.cut),
                ),
              ),
            ),
          const SizedBox(height: KSpace.x3),
        ],
      ),
    );
  }
}
