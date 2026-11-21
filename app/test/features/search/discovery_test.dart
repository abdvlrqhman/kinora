import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/features/home/home_layout.dart';
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

  test('Trakt\'s lists browse like a source, with genres and filters', () {
    final source = traktListsSource(
      movieGenres: const ['Science Fiction'],
      showGenres: const ['Anime'],
    );
    final movies = source.manifest.catalogs.where((c) => c.type == 'movie');
    expect(movies.map((c) => c.id), [
      'trending',
      'popular',
      'anticipated',
      'boxoffice',
    ]);
    expect(genresOf(movies.first).options, ['Science Fiction']);
    expect(genresOf(movies.last).options, isEmpty); // box office
    expect(traktSlug('Science Fiction'), 'science-fiction');
    expect(filterLabel('years=2010-2019&ratings=80-100'), '2010s, 8+');
    expect(filterLabel(''), isNull);
  });

  test('a pinned Trakt list keeps its filter', () {
    const key = (
      addon: 'trakt:lists',
      type: 'series',
      catalog: 'popular',
      genre: 'Anime',
      filter: 'years=2020-2029',
    );
    expect(pinnedKey(pinnedRowId(key)), key);
  });
}
