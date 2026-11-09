import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/downloads/downloads_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/player/player_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/title/title_screen.dart';
import '../services/play_request.dart';
import '../ui/tokens.dart';
import '../ui/widgets/media.dart';
import 'providers.dart';
import 'shell.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// App routes. Title and player pages cover the tab bar.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    redirect: (context, state) {
      final onboarded = ref.read(settingsProvider).onboarded;
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!onboarded && !atOnboarding) return '/onboarding';
      if (onboarded && atOnboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/downloads',
                builder: (_, _) => const DownloadsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
                routes: settingsRoutes,
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/title/:type/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => TitleScreen(
          type: state.pathParameters['type']!,
          id: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/player',
        parentNavigatorKey: _rootKey,
        // The artwork you tapped grows into the player (see artHeroTag);
        // with reduced motion it's an instant cut.
        pageBuilder: (context, state) {
          final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
          return CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: reduce ? Duration.zero : KMotion.slow,
            reverseTransitionDuration: reduce ? Duration.zero : KMotion.base,
            child: PlayerScreen(request: state.extra! as PlayRequest),
            transitionsBuilder: (_, animation, _, child) => FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: KMotion.emphasized,
              ),
              child: child,
            ),
          );
        },
      ),
    ],
  );
  ref.listen(
    settingsProvider.select((s) => s.onboarded),
    (_, _) => router.refresh(),
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Opens a title page.
void openTitle(
  BuildContext context, {
  required String type,
  required String id,
}) => context.push('/title/$type/${Uri.encodeComponent(id)}');

/// Starts playback.
void openPlayer(BuildContext context, PlayRequest request) {
  launchingArt.value = request.videoId;
  context.push('/player', extra: request);
}
