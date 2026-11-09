import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:subtitles/subtitles.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final url = Uri.parse('https://api.example.test/x');

  ProviderHttp make(
    MockClient client, {
    List<Duration>? sleeps,
    Duration timeout = const Duration(seconds: 5),
    int maxConcurrent = 4,
    DateTime Function()? clock,
  }) => ProviderHttp(
    providerId: 'test',
    client: client,
    timeout: timeout,
    maxConcurrent: maxConcurrent,
    clock: clock,
    sleep: (d) async => sleeps?.add(d),
  );

  test('retries 5xx with exponential backoff, then succeeds', () async {
    var calls = 0;
    final sleeps = <Duration>[];
    final h = make(
      MockClient(
        (_) async =>
            ++calls < 3 ? http.Response('busy', 503) : http.Response('ok', 200),
      ),
      sleeps: sleeps,
    );
    final res = await h.send('GET', url);
    expect(res.body, 'ok');
    expect(calls, 3);
    expect(sleeps, [
      const Duration(milliseconds: 500),
      const Duration(seconds: 1),
    ]);
  });

  test('gives up after maxRetries with a typed error', () async {
    var calls = 0;
    final h = make(
      MockClient((_) async {
        calls++;
        return http.Response('{"error":"boom"}', 500);
      }),
      sleeps: [],
    );
    await expectLater(
      h.send('GET', url),
      throwsA(
        isA<SubtitleHttpException>()
            .having((e) => e.statusCode, 'status', 500)
            .having((e) => e.message, 'message', contains('boom')),
      ),
    );
    expect(calls, 3);
  });

  test('429 honours Retry-After seconds and ratelimit headers', () async {
    final sleeps = <Duration>[];
    var calls = 0;
    final h = make(
      MockClient(
        (_) async => switch (++calls) {
          1 => http.Response('', 429, headers: {'retry-after': '3'}),
          2 => http.Response(
            '',
            429,
            headers: {'x-ratelimit-reset-after': '0.98'},
          ),
          _ => http.Response('ok', 200),
        },
      ),
      sleeps: sleeps,
    );
    await h.send('GET', url);
    expect(sleeps, [
      const Duration(seconds: 3),
      const Duration(milliseconds: 980),
    ]);
  });

  test('429 with JSON retryAfter body (SubSource) and HTTP-date', () async {
    final now = DateTime.utc(2026, 11, 9, 12);
    final h = make(
      MockClient((_) async => http.Response('', 200)),
      clock: () => now,
    );
    expect(
      h.retryAfter(http.Response('{"error":"Too many","retryAfter":12}', 429)),
      const Duration(seconds: 12),
    );
    expect(
      h.retryAfter(
        http.Response(
          '',
          429,
          headers: {'retry-after': 'Mon, 09 Nov 2026 12:00:30 GMT'},
        ),
      ),
      const Duration(seconds: 30),
    );
    expect(h.retryAfter(http.Response('', 429)), isNull);
  });

  test('long Retry-After fails fast and blocks further calls', () async {
    var calls = 0;
    final h = make(
      MockClient((_) async {
        calls++;
        return http.Response('', 429, headers: {'retry-after': '3600'});
      }),
      sleeps: [],
    );
    await expectLater(
      h.send('GET', url),
      throwsA(
        isA<SubtitleRateLimitException>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(hours: 1),
        ),
      ),
    );
    await expectLater(
      h.send('GET', url),
      throwsA(isA<SubtitleRateLimitException>()),
    );
    expect(calls, 1);
  });

  test('401/403 are auth errors, not retried', () async {
    var calls = 0;
    final h = make(
      MockClient((_) async {
        calls++;
        return http.Response('{"message":"Invalid API key"}', 401);
      }),
      sleeps: [],
    );
    await expectLater(
      h.send('GET', url),
      throwsA(isA<SubtitleAuthException>()),
    );
    expect(calls, 1);
  });

  test('passStatuses returns the response for provider handling', () async {
    final h = make(
      MockClient((_) async => http.Response('{"remaining":-1}', 406)),
    );
    expect((await h.send('POST', url, passStatuses: {406})).statusCode, 406);
  });

  test('network errors are retried then reported', () async {
    var calls = 0;
    final h = make(
      MockClient((_) async {
        calls++;
        throw http.ClientException('connection refused');
      }),
      sleeps: [],
    );
    await expectLater(
      h.send('GET', url),
      throwsA(
        isA<SubtitleNetworkException>().having(
          (e) => e.isTimeout,
          'timeout',
          isFalse,
        ),
      ),
    );
    expect(calls, 3);
  });

  test('per-request timeout', () async {
    final h = ProviderHttp(
      providerId: 'test',
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 50),
      maxRetries: 0,
    );
    await expectLater(
      h.send('GET', url),
      throwsA(
        isA<SubtitleNetworkException>().having(
          (e) => e.isTimeout,
          'timeout',
          isTrue,
        ),
      ),
    );
  });

  test('cancellation aborts in-flight requests and backoff sleeps', () async {
    final token = CancelToken();
    final h = ProviderHttp(
      providerId: 'test',
      client: MockClient((_) => Completer<http.Response>().future),
    );
    final f = h.send('GET', url, cancel: token);
    token.cancel();
    await expectLater(f, throwsA(isA<SubtitleCancelledException>()));
    await expectLater(
      h.send('GET', url, cancel: token),
      throwsA(isA<SubtitleCancelledException>()),
    );

    final sleeping = ProviderHttp(
      providerId: 'test',
      client: MockClient((_) async => http.Response('', 503)),
      sleep: (_) => Completer<void>().future, // would sleep forever
    );
    final t2 = CancelToken();
    final f2 = sleeping.send('GET', url, cancel: t2);
    await Future<void>.delayed(Duration.zero);
    t2.cancel();
    await expectLater(f2, throwsA(isA<SubtitleCancelledException>()));
  });

  test('child tokens follow their parent', () {
    final parent = CancelToken();
    final child = CancelToken(parent: parent);
    expect(child.isCancelled, isFalse);
    parent.cancel();
    return child.whenCancelled; // completes
  });

  test('concurrency limit per provider', () async {
    var active = 0, peak = 0;
    final h = make(
      MockClient((_) async {
        peak = active + 1 > peak ? active + 1 : peak;
        active++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return http.Response('ok', 200);
      }),
      maxConcurrent: 2,
    );
    await Future.wait([for (var i = 0; i < 6; i++) h.send('GET', url)]);
    expect(peak, 2);
  });

  test('minInterval spaces request starts', () async {
    final sleeps = <Duration>[];
    var now = DateTime.utc(2026);
    final h = ProviderHttp(
      providerId: 'test',
      client: MockClient((_) async => http.Response('ok', 200)),
      minInterval: const Duration(milliseconds: 200),
      maxConcurrent: 1,
      clock: () => now,
      sleep: (d) async {
        sleeps.add(d);
        now = now.add(d);
      },
    );
    await h.send('GET', url);
    await h.send('GET', url);
    expect(sleeps, [const Duration(milliseconds: 200)]);
  });

  test('json() decodes or throws SubtitleResponseException', () async {
    final h = make(
      MockClient(
        (r) async => r.url.path == '/ok'
            ? jsonResponse({'a': 1})
            : http.Response('<html>', 200),
      ),
    );
    expect(await h.json('GET', url.replace(path: '/ok')), {'a': 1});
    await expectLater(
      h.json('GET', url),
      throwsA(isA<SubtitleResponseException>()),
    );
  });

  test('error snippets redact echoed keys', () async {
    final h = make(
      MockClient(
        (_) async => http.Response(
          '{"error":"bad","url":"/subtitle/1.zip?api_key=SECRET123&x=1"}',
          400,
        ),
      ),
    );
    await expectLater(
      h.send('GET', url),
      throwsA(
        isA<SubtitleHttpException>().having(
          (e) => e.message,
          'message',
          allOf(contains('api_key=***'), isNot(contains('SECRET123'))),
        ),
      ),
    );
  });

  test('errors have readable toString without secrets', () {
    const e = SubtitleAuthException('HTTP 401', providerId: 'subdl');
    expect(e.toString(), 'SubtitleAuthException(subdl: HTTP 401)');
  });
}
