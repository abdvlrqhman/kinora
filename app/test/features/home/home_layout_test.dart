import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/features/home/home_layout.dart';

void main() {
  const available = [
    'continue',
    'my-list',
    'cat:a|movie|top',
    'cat:a|series|top',
  ];

  test('nothing set: the default order', () {
    expect(homeLayout(available: available), available);
  });

  test('the viewer\'s order and hidden rows', () {
    expect(
      homeLayout(
        available: available,
        order: ['cat:a|series|top', 'continue', 'my-list', 'cat:a|movie|top'],
        hidden: {'my-list'},
      ),
      ['cat:a|series|top', 'continue', 'cat:a|movie|top'],
    );
  });

  test('a new source\'s rows join after the row they follow by default', () {
    expect(
      homeLayout(
        available: [...available, 'cat:b|movie|new'],
        order: ['cat:a|series|top', 'continue', 'my-list', 'cat:a|movie|top'],
      ),
      [
        'cat:a|series|top',
        'continue',
        'my-list',
        'cat:a|movie|top',
        'cat:b|movie|new',
      ],
    );
    expect(
      homeLayout(available: ['for-you', ...available], order: ['my-list']),
      ['for-you', 'continue', 'my-list', 'cat:a|movie|top', 'cat:a|series|top'],
    );
  });

  test('a removed source\'s rows drop out, hidden or not', () {
    expect(
      homeLayout(
        available: ['continue', 'my-list'],
        order: ['cat:gone|movie|top', 'my-list', 'continue'],
        hidden: {'cat:gone|movie|top'},
      ),
      ['my-list', 'continue'],
    );
  });

  test('a pinned row\'s id keeps its catalog and genre', () {
    const key = (
      addon: 'https://v3-cinemeta.strem.io',
      type: 'series',
      catalog: 'top',
      genre: 'Animation',
    );
    expect(pinnedKey(pinnedRowId(key)), key);
    expect(
      pinnedKey(
        pinnedRowId((addon: 'a', type: 'movie', catalog: 'top', genre: null)),
      )?.genre,
      isNull,
    );
    expect(pinnedKey('cat:a|movie|top'), isNull);
  });
}
