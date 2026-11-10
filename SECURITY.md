# Security

## Report a problem privately

Please don't open a public issue. Use **[Report a vulnerability](https://github.com/abdvlrqhman/kinora/security/advisories/new)**
on the repository's Security tab; only the maintainers see it.

Include what you found, how to reproduce it, and what it lets someone do.
You'll get an answer as soon as possible. The fix ships in a new release,
and you can be credited in its notes if you'd like.

## What counts

Kinora runs on your phone, with no server of its own. Examples worth
reporting:

- **Keys:** your subtitle or debrid keys leaving the Keychain or Keystore,
  showing up in logs, or ending up in copied diagnostics.
- **The streaming server:** the phone runs a small HTTP server that your TV
  plays from. Report any way to read files other than the video being
  played, or to reach the server when you're not casting.
- **Untrusted data:** a crash or code execution from a torrent, a subtitle
  file, an addon response or a TV's reply.
- **Updates:** anything that would make the update check install something
  other than an official release.

## Versions

Only the [latest release](https://github.com/abdvlrqhman/kinora/releases/latest)
gets fixes. Kinora updates itself, so please check the problem still happens
there.
