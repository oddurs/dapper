# Layout and text metrics

The stream that makes `render : Chart -> String` true rather than aspirational. Prior art
(`docs/prior-art.md`, "The hard problems nobody solved elegantly") calls text measurement
load-bearing and still broken in the state of the art. This plan takes matplotlib's position —
bundle the metrics, pin them, choose determinism over fidelity — and declares the error budget.

## Decisions

**1. The layout cycle is bounded at exactly two passes, and only ticks are computed twice.**
Order inside `build`: scale-transform → stat → train domains → **layout pass A** → **layout pass
B** → map data → `Scene`. Pass A ranges each scale against a *seed* plot rect (canvas minus seed
insets computed from the label font's ascent/descent, tick length, and `advance("0000")` — no data
inspection), generates ticks, formats them, measures them, and reserves the real insets. Pass B
re-ranges against the final plot rect and re-ticks. Then stop. Data marks are mapped **once**,
through the pass-B scales, so the cost of two passes is O(ticks), not O(n) — this is the entire
reason a second pass is affordable where Vega's `autosize: "fit"` is a warning. Band scales are
exactly correct after one pass (their tick set is the domain, invariant under range); only
continuous axes can shift, and the residual is handled by decision 6.

**2. `Metrics` is an opaque value, not a record of functions.** The rendering brief sketches
`Metrics(advance:, ascent:, descent:)` as a public record; that is a breaking-change trap the
moment we need line gap, cap height or a kerning hook. Opaque from day one with named
constructors, per the "adding a public record field is breaking" constraint. `metrics.embedded()`
is the default on **both** targets. Identical numbers on BEAM and JS means one birdie suite covers
both and the two render paths cannot drift — the point of prior-art item 3.

**3. The bundled font is Arimo (sans) and Cousine (mono), both SIL OFL 1.1.** Not DejaVu.
matplotlib bundles DejaVu because it *rasterises* with the font it ships, so fidelity is
guaranteed by construction. dapper never rasterises — the viewer's browser picks the font — so the
best available analogue is metric-compatibility with the font the viewer most likely *has*. Arimo
is metric-compatible with Arial, which shares advance widths with Helvetica and Liberation Sans;
Cousine matches Courier New. We emit `font-family="Arimo, Liberation Sans, Arial, Helvetica,
sans-serif"` explicitly and never inherit ambient CSS for measured text. So on the overwhelming
majority of clients our measurements are not merely self-consistent, they are *right*.

**4. The advance table is generated Gleam source: one `case` per (family, weight).** Not a `Dict`
built at init (Gleam has no const dicts and lazy globals are awkward), not a packed string decoded
at startup. A ~400-arm `case cp { 32 -> 569 ... }` compiles to a jump table on BEAM and a `switch`
on JS, allocates nothing, and is a pure total function on both targets. Coverage: U+0020–U+00FF
plus Latin Extended-A, General Punctuation (U+2010–U+2026), and a curated symbol set (−, ×, ÷, °,
µ, ‰, currency, arrows). Mono is monospaced so its table is a single constant plus a coverage set.
Three tables total — sans regular, sans bold (titles and legend headings), mono regular — roughly
1000 lines and ~30 KB of generated source. Generator: `scripts/gen_metrics.py` over fonttools
`hmtx`/`cmap`, emitting `src/dapper/metrics/tables.gleam` with a `// GENERATED — do not edit`
banner and a `const table_digest: String`; a test asserts the digest so a hand-edit or a stale
regeneration fails CI. Font `.ttf` files live in `fonts/` at repo root — in git for
reproducibility, outside `src`/`priv` so they never ship in the Hex tarball — with SHA-256 pinned
in the generator alongside the OFL text.

**5. Missing glyphs fall back by class; complex scripts fail loudly.** Unknown codepoint → the
generator-computed median advance for its class (digit / lowercase / uppercase / punctuation /
other), selected by cheap range checks. CJK, Hangul, Kana and fullwidth ranges → 1.0 em, which is
correct for essentially every CJK font. Combining marks (U+0300–U+036F) and zero-width → 0.
Astral/emoji → 1.2 em. Arabic, Hebrew, Devanagari, Thai and friends need *shaping*, which
per-codepoint summation cannot approximate: `metrics.coverage` classifies such a string as
`Unshaped` and `layout.diagnose` emits a diagnostic. Wrong-but-silent is the failure mode Vega has
(`#2940`, the per-character estimate that visibly breaks axis layout); wrong-and-loud is the one we
choose.

**6. Error budget, stated up front.** Numeric labels (digits, `.`, `,`, `-`, `%`, `e`) carry no
kerning pairs in Arial-metric fonts: measurement is **exact**. Mixed-case Latin labels can differ
by up to ~1.5% of string width (bounded by kern pairs × ~80/1000 em, unkerned). Budget: **≤2% for
Latin, exact for numeric**. Every reserved inset therefore adds `4% + 2px` of pad, which also
absorbs the pass-B tick shift from decision 1. If the client lacks Arial/Helvetica/Liberation/Arimo
entirely — some Linux, some locked-down Android — advances can differ by ~10%; the consequence is
crowded or airy labels, never reflowed geometry, because the geometry is baked. That degradation
is the price of `Chart -> String` and belongs in the README, not in a bug report at v0.3.

**7. Canvas `measureText` is opt-in, JS-only, and documented as snapshot-breaking.**
`dapper/metrics/canvas.measure_text() -> Result(Metrics, CanvasUnavailable)` — a `Result` because
there may be no DOM. It is never a default and never auto-detected. Separately: dapper **never
measures per datum**. Measurement is O(distinct tick labels + legend entries + titles) — tens of
calls, not the ~40,000 `getStringSize` calls that dominate Recharts' render time. That is why we
need no memoisation, and why memoisation (which would require mutable state) stays out.

**8. Rotation is a closed three-value enum and is never automatic.** `LabelAngle { Horizontal |
Angled45 | Vertical }`. Arbitrary float angles multiply the anchor/baseline/overhang cases without
covering a real need, and *auto*-rotation makes layout non-monotone — rotating trades width
reservation for height reservation, which is precisely the fixpoint we refused in decision 1. If
labels collide, we drop them (decision 9); we do not silently rotate them. Rotated bottom-axis
labels overhang horizontally by up to `w·cos45 − step/2`; that overhang is folded into the
*pass-A* left/right seed insets — the single place a bottom-axis measurement is allowed to
influence a side inset, and the honest cost of not running a third pass.

**9. Take Vega's `labelOverlap` verbatim: `Show | Parity | Greedy`.** Default `Parity` on
continuous axes, `Greedy` on band axes — parity's halving is too coarse when categories are few
and unevenly wide. Both run over measured boxes projected onto the axis direction with a 2px
minimum gap, both are total, parity is repeat-drop-every-other-until-clear, greedy is a single
in-order scan keeping a label if it clears the last kept. First and last labels are never dropped.

**10. The pane grid is the renderer's top level from day one; v0.1 always builds 1×1.** Axis space
is reserved **per grid edge**, not per pane (`AxisPlacement { OuterEdges | EveryPane }`, fixed to
`OuterEdges` in v0.1, where the two are identical). That single choice is what stops faceting from
being a rewrite — Polaris's lesson, and the one item in this stream whose cost is near zero now and
enormous later.

**11. Margins: `Auto | AtLeast(Insets) | Fixed(Insets)`, default `Auto`.** `Fixed` is the escape
hatch that makes geometry independent of the metrics table entirely — the right answer for a user
shipping their own webfont, and for anyone who wants byte-stable SSR output across a dapper upgrade
that regenerates the tables.

**12. Titles are single-line; explicit `\n` splits into `<tspan>`s at 1.2 em.** No automatic
wrapping. Wrapping needs candidate-line measurement inside the layout cycle, which is where the
two-pass bound would break. A title wider than the canvas is centred and allowed to bleed
symmetrically rather than clipped, and `layout.diagnose` says so. Legends in v0.1 are a single
right-hand column whose width is the widest measured entry plus swatch and gap.

## Concrete shapes

```gleam
// dapper/geom
pub type Size   { Size(width: Float, height: Float) }
pub type Rect   { Rect(x0: Float, y0: Float, x1: Float, y1: Float) }   // never (x,y,w,h)
pub type Insets { Insets(top: Float, right: Float, bottom: Float, left: Float) }

// dapper/metrics
pub opaque type Metrics

pub type FontFamily { Sans | Mono }        // may gain variants in a minor bump
pub type FontWeight { Regular | Bold }
pub type Font    { Font(family: FontFamily, weight: FontWeight, size_px: Float) }
pub type TextBox { TextBox(width: Float, ascent: Float, descent: Float) }

pub type Coverage {
  Exact
  Approximated(codepoints: List(Int))      // class fallback was used
  Unshaped(sample: String)                 // complex script; measurement is not meaningful
}

pub fn embedded() -> Metrics
pub fn custom(
  advance: fn(String, Font) -> Float,
  vertical: fn(Font) -> #(Float, Float),   // #(ascent, descent), both positive
) -> Metrics

pub fn measure(m: Metrics, text: String, font: Font) -> TextBox
pub fn coverage(m: Metrics, text: String) -> Coverage
pub fn font_stack(family: FontFamily) -> String

// dapper/metrics/tables  — GENERATED
pub const table_digest: String
pub fn sans_regular(codepoint: Int) -> Int   // advance in 1/1000 em
pub fn sans_bold(codepoint: Int) -> Int
pub const mono_advance: Int

// dapper/metrics/canvas  — JavaScript target only
pub type CanvasUnavailable {
  NoDocument
  NoContext2d
}
pub fn measure_text() -> Result(Metrics, CanvasUnavailable)

// dapper/layout
pub opaque type Frame

pub type PaneKey {
  PaneKey(row: Int, col: Int)
}

pub type LabelOverlap {
  Show
  Parity
  Greedy
}

pub type LabelAngle {
  Horizontal
  Angled45
  Vertical
}

pub type MarginPolicy {
  Auto
  AtLeast(Insets)
  Fixed(Insets)
}

pub type AxisPlacement {
  OuterEdges
  EveryPane
}

pub type Edge {
  Top
  Right
  Bottom
  Left
}

pub type AxisSpace {
  AxisSpace(labels: Float, ticks: Float, gap: Float, title: Float, overhang: Float)
}

pub fn layout(chart: Chart(row), metrics: Metrics) -> Frame   // Chart carries its own Size
pub fn canvas(frame: Frame) -> Rect
pub fn panes(frame: Frame) -> List(PaneKey)
pub fn plot_rect(frame: Frame, pane: PaneKey) -> Rect
pub fn axis_space(frame: Frame, edge: Edge) -> AxisSpace
pub fn kept_labels(frame: Frame, edge: Edge) -> List(#(Float, String))  // post-overlap

pub fn diagnose(chart: Chart(row), metrics: Metrics) -> List(Diagnostic)
```

`validate(Chart) -> List(Diagnostic)` keeps its accepted signature and cannot see metrics or size;
layout-dependent diagnostics (`TitleOverflowsCanvas`, `AllLabelsDropped`, `UnshapedLabelText`,
`PlotAreaDegenerate`) come from `layout.diagnose`, which takes the metrics it needs. Public entry
points: `dapper.render(chart) -> String` (embedded metrics, preserving the headline signature
exactly) and `dapper.render_with_metrics(chart, metrics) -> String`.

## Task breakdown

| # | Task | Size | Unblocks |
|---|---|---|---|
| 1 | `dapper/geom` primitives + the shared coordinate formatter (2 dp, never exponent notation) | S | everything; both renderers must share one formatter |
| 2 | `scripts/gen_metrics.py` (fonttools → `tables.gleam`), font vendoring, digest test | M | all measurement |
| 3 | `dapper/metrics`: opaque type, `embedded`, `measure`, class fallbacks, `coverage` | S | layout |
| 4 | Cross-target parity test: same corpus measured under `--target erlang` and `--target javascript`, byte-identical | S | the whole purity claim; run in CI from here on |
| 5 | `Frame`, pane grid (1×1), `AxisSpace`, margin policies | M | axis rendering, faceting later |
| 6 | Two-pass cycle: seed insets → ticks → format → measure → reserve → re-range → re-tick | M | axes, autosize, everything visual |
| 7 | Overlap resolution: parity + greedy over measured boxes | S | readable dense axes |
| 8 | Rotation: three angles, bbox math, anchor/baseline table, overhang folding | S | categorical charts with long labels |
| 9 | `layout.diagnose` | S | honest failure |
| 10 | birdie snapshots on both targets, incl. a deliberate metrics-drift golden | M | regression safety |
| 11 | `dapper/metrics/canvas` opt-in FFI + docs warning | S | JS users with custom webfonts |

Tasks 1–4 are the critical path and should land before any renderer work. Task 11 is genuinely
last; shipping without it is fine.

## Risks and unknowns

- **Pass-B tick widening.** A continuous axis can re-tick from `1000` to `1250` after re-ranging,
  needing a wider inset than pass A reserved. Mitigated by the 4%+2px pad; residual is a label that
  overhangs the canvas edge by a few px. Accepted, not fixed. If it proves common, the fix is a
  *seed* that measures the widest label of both the pass-A and a one-step-denser tick set — still
  two passes.
- **Compile time and output size of 400-arm `case` expressions**, particularly on the Erlang
  target. Measure in task 2 before committing; the fallback is bucketing contiguous ranges.
- **Arimo/Arial metric compatibility is an assumption I have not verified glyph-by-glyph.** Task 2
  should assert it against Liberation Sans advances and fail if any covered codepoint disagrees.
- **`FontFamily` is a closed enum users may pattern-match on**, so adding `Serif` is technically
  breaking. Document "do not match exhaustively"; gate additions on minor bumps.
- **Rotated labels near the first/last tick** remain the ugliest output dapper will produce. It is
  a deliberate consequence of refusing a third pass, and it should be in a screenshot in the docs.
- **A user who sets a custom `font-family` in CSS silently invalidates every measurement.** The
  answer is `MarginPolicy.Fixed` plus a loud paragraph, not detection.

## What is explicitly NOT in v0.1

Kerning and kern-pair tables. Text shaping, bidi, and complex-script support. Automatic text
wrapping or line breaking. Label truncation/ellipsis (`labelLimit`) — dropping labels is honest,
truncating hides data. Automatic rotation, and arbitrary rotation angles. Text-to-path conversion
(it destroys selectability and screen-reader access). Font subsetting or `@font-face` embedding of
the bundled font. Iteration to a layout fixpoint, and autosize-to-content. Responsive re-layout on
resize. Canvas metrics as any kind of default. Per-pane (`EveryPane`) axis placement. Multi-column
or flowed legends. Serif family metrics.

## Open questions needing a human call

1. **Arimo/Arial as the metric target vs. a modern face.** Arial-metric-compatibility maximises
   the chance our measurements match what the viewer sees, but the default chart will look like
   2003 — and any user who swaps in Inter to fix that invalidates every measurement. Do we accept
   ugly-but-correct as the default, or bundle Inter metrics and accept that we are measuring a font
   most viewers do not have?
2. **Ship a bold table, or approximate bold as regular × a constant?** Bold is needed only for
   titles and legend headings. A second table costs ~10 KB of generated source; a constant factor
   is wrong by a few percent on a string nothing else depends on.
3. **Vendor the `.ttf` files in git, or have the generator fetch by pinned hash?** Vendoring is
   reproducible forever and adds ~1 MB to the repo (not the package); fetching risks URL rot.
4. **Should `MarginPolicy.Fixed` be the *documented recommendation* for server-rendered charts**,
   with `Auto` positioned as the interactive/exploratory default? That would make SSR output stable
   across dapper upgrades that regenerate the tables, at the cost of the nicest thing `Auto` does.
5. **Does `layout.diagnose` belong in the public API at v0.1**, or is one `validate` the cleaner
   story even though it structurally cannot see measurement?
