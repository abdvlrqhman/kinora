import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/features/search/discovery.dart';
import 'package:stremio/stremio.dart';

void main() {
  MetaPreview m(String id) => MetaPreview(id: id, type: 'movie', name: id);

  test('a page adds only titles not seen yet', () {
    final first = mergePage(const [], [m('a'), m('b'), m('a')]);
    expect(first.items.map((x) => x.id), ['a', 'b']);
    expect(first.more, isTrue);
    final second = mergePage(first.items, [m('b'), m('c')]);
    expect(second.items.map((x) => x.id), ['a', 'b', 'c']);
    expect(second.more, isTrue);
  });

  test('paging stops at an empty page or one with nothing new', () {
    expect(mergePage([m('a')], const []).more, isFalse);
    expect(mergePage([m('a')], [m('a')]).more, isFalse);
  });

  test('a catalog lists its genres and whether one is required', () {
    const c = ManifestCatalog(
      type: 'movie',
      id: 'top',
      extra: [
        CatalogExtra(name: 'genre', isRequired: true, options: ['Drama']),
      ],
    );
    expect(genresOf(c).options, ['Drama']);
    expect(genresOf(c).required, isTrue);
    final none = genresOf(const ManifestCatalog(type: 'movie', id: 'x'));
    expect(none.options, isEmpty);
    expect(none.required, isFalse);
  });
}
