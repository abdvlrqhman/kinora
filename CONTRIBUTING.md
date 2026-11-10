# Contributing to Kinora

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Report a bug

Open a [bug report](https://github.com/abdvlrqhman/kinora/issues/new?template=bug_report.yml).
These details make it fixable:

- your Kinora version (**Settings › About**);
- your phone and its iOS or Android version;
- your TV's brand and model, if it's about casting;
- what you did, what you expected, and what happened instead;
- a screenshot or screen recording, if you can;
- **Settings › Diagnostics › Copy diagnostics**, pasted into the report. It
  leaves out your keys and addon links.

Don't post addon links, keys or the names of things you were watching.

## Suggest an idea

Open a [feature request](https://github.com/abdvlrqhman/kinora/issues/new?template=feature_request.yml).
Say what you were trying to do. The problem helps more than a solution.

## Change the code

1. Fork the repo and create a branch.
2. Make your change, keeping to the style of the code around it.
   - UI follows [DESIGN.md](DESIGN.md).
   - The decisions behind the architecture are in [PLAN.md](PLAN.md).
3. Check it:

   ```sh
   cd app
   flutter analyze
   flutter test
   # Pure-Dart packages (dlna, ranking, release_parser, stremio, subtitles, swarm):
   cd ../packages/dlna && dart test
   ```

   If you changed a screen, update its renders with
   `flutter test --update-goldens test/goldens`, then **look at every
   changed image** before committing.
4. Open a pull request. CI builds both apps and runs the end-to-end tests on
   an Android emulator and an iPhone simulator; it has to pass.

### Commit messages are the changelog

Release notes are made from commit messages, and Kinora shows them in its
update screen. So write the title for the people using the app:

- Good: `Player: subtitles stay in sync after seeking`
- Not: `fix seek handler race`

Commits that start with `E2E`, `CI:`, `Docs:`, `Goldens:` or `Engine test:`
are left out of the notes.

### Versions

A release bumps two places, which a test keeps equal:

- `version:` in [`app/pubspec.yaml`](app/pubspec.yaml);
- `kinoraVersion` in [`app/lib/app/providers.dart`](app/lib/app/providers.dart).

Tagging `vX.Y.Z` on `main` publishes it.

### Things we don't take

- Bundled content sources, stream addons or API keys. Kinora ships with none,
  on purpose.
- Accounts, analytics or tracking of any kind.
- Secrets in code, tests or logs. Use the app's settings, and `.env.local`
  (git-ignored) for local testing.

## License

By contributing, you agree that your work is released under the
[GPL-3.0](LICENSE), like the rest of Kinora.

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).
