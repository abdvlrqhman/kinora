# Kinora design system

Subject: a personal cinema. Audience: one person and their household, watching
on a phone and casting to a living-room TV, often in the dark. Primary job: get
from "what should I watch" to the best release playing, in one tap, and trust
that choice.

## Concept: light through glass

A projector throws a film's light through glass onto a dark room. In Kinora
the artwork is always the light source: backdrops fill the screen, glass
controls float over them and take their color from the title on screen. The
interface has no color of its own beyond warm projector white; each film tints
it. That is the one bold thing. Everything else stays quiet.

## Tokens

| Name | Value | Role |
|---|---|---|
| Blackout | `#000000` | Base. A dark theater, true black for OLED and the player. Not a tinted near-black. |
| Seat | `#17141B` | The rare opaque surface (sheets with no artwork behind, skeletons). |
| Lamp | `#F5EEE4` | Primary text and icons: warm projector white, not pure white. |
| Haze | `#B3ABB5` | Secondary text. |
| Reel | `#77707A` | Tertiary text, disabled. |
| Marquee | `#B48CFF` | The one accent: lit buttons, glass tint, toggles, icon and intro. Violet marquee light. |
| Caution | `#FFC15E` | Warnings and things that need attention (few seeds, waiting for Wi-Fi, can't play on the TV). Never the brand color, so a warning can't read as selected. |
| Go | `#7EE2B8` | Ready / downloaded / best match. |
| Cut | `#FF6B6B` | Errors and destructive actions. |

Type
- Titles: **Big Shoulders Display** (condensed marquee lettering, OFL). Set
  large and tight: hero 46/44 w800, h1 32/34 w700, h2 24/28 w700. Used for
  film titles, section titles and big numbers only.
- Everything else: **Figtree** (OFL). title 17/22 w600, body 15/22 w400,
  label 13/18 w500, small 12/16 w500. Tabular figures for sizes, speeds,
  times. Sentence case everywhere; no all-caps labels, no eyebrows.

Space and shape
- 4-pt grid; page margin 20; row gap 28; item gap 12.
- Radii by hierarchy, not one radius for all: posters 12, episode stills 10,
  sheets 28, controls are full capsules.
- No borders or drop-shadow cards. Glass has its own rim light; content
  sits directly on Blackout or on artwork.

Layout (phone, portrait)
```
Home                         Title                       Player
┌──────────────────────┐     ┌──────────────────────┐   ┌──────────────────────┐
│ backdrop (full bleed) │     │ backdrop + logo       │   │ ‹ title       cast  ⋯│ glass capsules
│                       │     │ 2024  2h 10m  8.1     │   │                      │
│ TITLE IN MARQUEE TYPE │     │ [▶ Play S1 E3       ] │   │        video         │
│ [▶ Play] [+ My list]  │     │  1080p WEB, 214 seeds,│   │                      │
├──────────────────────┤     │  Arabic subtitles     │   │ ━━━━━━━●──────────── │ buffered bar
│ Continue watching     │     │ Season 1  2  3        │   │ ⏮  ⏯  ⏭   Aa  ♪   ⛶ │
│ ▭ ▭ ▭ ▭ →             │     │ ▭ E1 still  title    │   └──────────────────────┘
│ Popular               │     │ ▭ E2 still  title    │
│ ▯ ▯ ▯ ▯ →             │     │                      │
│  (glass tab bar)      │     └──────────────────────┘
└──────────────────────┘
```
Text is left-aligned to the 20-pt margin. Facts are separated by space and
weight, not middle dots.

## Principles

1. The film is the interface. Artwork is always behind the glass, and the
   accent comes from it.
2. One tap to play, and say why. Every Play button names the release it will
   use in plain words.
3. Glass only where you touch. Controls float as glass; content is never
   boxed into cards.
4. Quiet chrome, loud content. Badges only when they inform (Downloaded, 4K,
   your subtitle language). No decorative gradients beyond legibility scrims.
5. Motion answers actions. One orchestrated moment: the poster grows into the
   player while the status pill counts up ("Finding peers", "Buffering 34%").
   Everything else is short and functional; reduced motion is respected.

## Review against generic defaults

- Near-black with one accent: chosen on purpose (the owner asked for violet
  over per-film colors). Base is real black; the violet is the only accent,
  amber marks warnings, and the artwork itself carries each film's color.
- Card kit with one radius and grey shadows: avoided. No cards; radii follow
  hierarchy.
- All-caps eyebrows, dot-joined meta, mono labels, arrow-suffixed buttons:
  none of them.
- Serif display on cream: not used; condensed marquee type comes from cinema
  signage, the subject's own vernacular.

## Voice

Plain verbs, sentence case, from the viewer's side: "Play", "Download",
"Choose another version", "Subtitles", "Cast to Living Room TV". Errors say
what happened and what to do ("No one is sharing this version right now. Try
another version."). Empty screens invite the next step ("Add a source to see
movies and shows.").
