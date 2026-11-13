# Kinora design system

Subject: a personal cinema. Audience: one person and their household,
watching on a phone, a computer, and casting to a living-room TV, often in
the dark. Primary job: get from "what should I watch" to the best version
playing, in one tap, and trust that choice.

## Principles

- **True black ground.** `#000000` wherever content sits. Panels are barely
  lifted neutral blacks, never grey.
- **One accent, three signals.** Lime is interaction and progress. Coral
  means *new* (badges, counts, dots) and nothing else. Teal means *saved on
  this device*. Red means *failed*. Amber means *needs attention*.
- **The main action is lit, not filled.** It wears lime as a soft tint and
  a 1.5 px edge, text in pale lime. Solid lime is for marks: progress lines,
  switches that are on, the sparkle.
- **Numbers are mono.** Episode numbers, times, sizes and state lines
  (`S1 E3 · 30M LEFT`) are Geist Mono in caps, so status scans and aligns.
- **Display type is rare.** Unbounded is for titles, section titles and rank
  numerals only.
- **The sparkle means "you are here".** The four-point sparkle marks the
  current sidebar item and nothing else.
- **Rows, not feeds.** Discovery content scrolls sideways in rows; lists you
  manage (episodes, downloads, settings) scroll down.

## Colour (`lib/ui/tokens.dart`)

| Token | Value | Role |
|---|---|---|
| `blackout` | `#000000` | The ground |
| `sidebar` / `panel` / `raised` | `#0A0A09` / `#0E0E0C` / `#181815` | Sidebar; cards and panels; hovered rows, floating cards |
| `divider` / `edge` / `fieldEdge` / `strongEdge` | `#161614` / `#1A1A17` / `#22221E` / `#2A2A25` | Hairlines; panel edges; fields and chips; buttons in bars |
| `title` / `lamp` / `body` | `#F6F6F2` / `#EFEFEA` / `#CACAC4` | Titles; primary text; body text |
| `haze` / `muted` / `reel` | `#A8A8A1` / `#8B8B84` / `#80807A` | Secondary; meta and eyebrows; faint (5.2:1 on black) |
| `marquee` | `#BEF264` | The accent: progress, selection, the main action's edge |
| `limeLink` / `onLime` | `#D9F99D` / `#ECFCCB` | Episode numbers and state lines; text on the lime tint |
| `coral` / `coralText` | `#FF4D6D` / `#FF7390` | NEW badges, counts; "S1 E4 IS OUT" |
| `go` | `#5EEAD4` | Saved on this device, ready, best match |
| `caution` | `#FFC15E` | Few seeds, waiting for Wi-Fi, can't play on the TV |
| `cut` | `#FB6E6E` | Errors, destructive actions |

Every text colour reads at WCAG AA or better on black and on panels.

## Type

Bundled variable fonts (offline), weight on the `wght` axis:

| Style | Face | Size (computer / phone) | Use |
|---|---|---|---|
| `hero` | Unbounded 700 | 30 / 24 | A title over artwork |
| `h1` | Unbounded 600 | 22 / 20 | A page's title (phone; the window bar names pages on a computer) |
| `h2` | Unbounded 600 | 17 / 15 | Row and section titles |
| `title` | Readex Pro 500 | 14 | Card titles, buttons |
| `body` | Readex Pro 400 | 14 | Synopsis, notes |
| `label` / `small` | Readex Pro | 13 / 12 | Row labels; secondary text |
| `eyebrow` | Readex Pro 600 caps | 11, +1.5 tracking | Panel and section labels |
| `meta` / `badge` / `numeric` | Geist Mono | 11 / 10 / 12 | State lines; badges on art; sizes and times |

Readex Pro covers Arabic, so names and subtitles in either language read
alike.

## Layout

- **Phone (< 900 px):** a 56 px title row under the status bar; a floating
  pill tab bar (62 high, 16 from the sides, 18 above the bottom), the chosen
  tab showing its name on the lime lens.
- **Computer (≥ 900 px, Windows from 960 × 640):** a 248 px sidebar (the
  wordmark, Home, Discovery, Downloads with a live count, what's
  downloading, your Trakt account, Settings) and a 52 px frosted window bar
  (back, where you are, search with Ctrl+K, Cast, the window's buttons).
  Pages start 24 px under the bar.
- **Edges and gaps:** a 20 px page edge everywhere; 16 px between cards on a
  computer, 12 on a phone; 32 / 24 px between sections.
- **Radii:** 6 badges, 10 buttons and fields, 12 artwork, 14 panels, 20
  sheets and the tab bar.
- Reading text stays under about 65 characters a line (600 px); lists of
  rows under 760 px.

## Components

- **Cards:** 16:9 for Keep watching and New episodes (the progress along the
  foot), 2:3 posters, outlined rank numerals behind Trending's posters. On
  hover: a lime outline, a dark scrim and a round play button.
- **Panels:** a `panel` card with an `edge`, holding settings rows (divided
  by hairlines), facts, storage, episodes and downloads.
- **Chips:** a field at rest, lime tint and edge when chosen; one row that
  scrolls sideways.
- **Dialogs:** on a computer, sheets open as centred dialogs (560 px, a
  close button, Esc or a click outside closes them) and the frame dims with
  the page.

## Motion

Motion answers an action: 140 ms for hover and press, 240 ms for state,
420 ms for paging rows and the hero. Nothing moves on its own; the hero
waits to be swiped. Reduced motion turns scaling and animated scrolling off.

## Access

Every control is a labelled button for screen readers; section titles read
in normal case though they show in caps. On a computer every control has a
hand cursor, a hover state, Tab focus with a lime ring, and Enter or Space;
Esc, Alt+← and the mouse's back button go back.
