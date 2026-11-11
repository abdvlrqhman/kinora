import 'package:flutter_test/flutter_test.dart';
import 'package:kinora/features/player/player_controller.dart';

void main() {
  // Feeds raw readings (0..99) and returns what the screen shows.
  List<String> shown(List<int> raws) {
    var peak = 0;
    var finishing = false;
    return [
      for (final raw in raws)
        (() {
          final s = PlayerController.startupReady(
            raw,
            peak,
            finishing: finishing,
          );
          peak = s.shown;
          finishing = s.finishing;
          return finishing ? 'almost' : '${s.shown}';
        })(),
    ];
  }

  test(
    'start, then the index at the end, then the resume point: no restart',
    () {
      expect(shown([10, 60, 99, 5, 40, 95, 0, 50, 99]), [
        '10',
        '60',
        '99',
        'almost',
        'almost',
        '99',
        'almost',
        'almost',
        '99',
      ]);
    },
  );

  test('a jump before it got near done just holds the number', () {
    expect(shown([20, 70, 10, 50, 85, 99]), [
      '20',
      '70',
      '70',
      '70',
      '85',
      '99',
    ]);
  });
}
