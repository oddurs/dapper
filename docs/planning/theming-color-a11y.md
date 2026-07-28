# Theming, colour, and accessibility

One stream because they are one dependency chain: accessibility needs human-readable labels and
guaranteed contrast; contrast is a property of the theme; the theme is where colour lives; and
colour is only safe if its *intent* (categorical / sequential / diverging) is carried in the type.

## Decisions

**1. Every channel constructor takes a mandatory `label: String`.** Accessor functions deleted
field names (positioning 0001, win #1) — and with them the only human-readable name in the spec. A
closure has no name to introspect. Axis titles, legend entries, the generated `<desc>` and the data
table all need one, so the label is collected once, at the only place it can be, and is not
optional. This is the interlock: the prior art's item 11 ("accessibility, possible only because the
chart type is known") is really *because the chart type* **and the field names** *are known*. Without
this decision the a11y story is `"Bar chart with 4 bars"` and nothing more.

**2. Categorical / sequential / diverging are three distinct opaque types, not three variants of
one.** Variants of a single `Scheme` do not prevent misuse — a `Seq(...)` value typechecks anywhere a
`Scheme` is accepted. To make "a sequential scheme cannot fill a nominal channel" a compile error
under Gleam's constraints (no HKTs, no classes, no phantom-pipeline tricks — `plotters`' trait-bound
hell is the warning), the only mechanism is separate nominal types plus smart constructors. A public
`Scheme { Cat | Seq | Div }` wrapper still exists, used *only* where all three must be stored
uniformly (legend rendering, the `Scene`). This is arity-as-compatibility applied to colour, exactly
as decision 0001 applies it to marks.

**3. Diverging channels require a mandatory `around: Float` midpoint.** The classic diverging lie is
a neutral that does not sit at the meaningful zero. Gleam's lack of default arguments makes stating
it unavoidable; `validate` warns when the midpoint is outside the trained domain.

**4. Default categorical palette is Okabe–Ito, reordered.** Okabe & Ito's Color Universal Design set
(2008) is the most widely validated CVD-safe qualitative palette in print and remains the reference
that ColorBrewer's qualitative sets are checked against. dapper ships it in a deliberately different
order, because most charts have two or three series and the first three entries do all the work:

| # | light | dark (candidate) | name |
|---|---|---|---|
| 1 | `#0072B2` | `#3E9BE0` | blue |
| 2 | `#E69F00` | `#E8A73A` | orange |
| 3 | `#009E73` | `#2FBE92` | bluish green |
| 4 | `#CC79A7` | `#D992BA` | reddish purple |
| 5 | `#56B4E9` | `#7FC8F0` | sky blue |
| 6 | `#D55E00` | `#E8743A` | vermillion |
| 7 | `#F0E442` | `#F0E442` | yellow |
| 8 | `#000000` | `#FFFFFF` | black/white |

Blue-versus-orange is the one hue axis fully preserved under protanopia and deuteranopia, so it
leads. Yellow is demoted to seventh because `#F0E442` is L\*≈89 and near-invisible as a thin stroke
on white; black is last because it collides with axis and text ink. The dark column lifts lightness
in Oklab while holding hue and chroma, except for entry 7 (already light) and 8 (inverted). Also
shipped: `scheme.tol_bright()` (Tol's 7-colour bright set — `#4477AA #EE6677 #228833 #CCBB44
#66CCEE #AA3377 #BBBBBB`), which is a better fit for dark backgrounds out of the box.

**5. Default sequential is viridis; default diverging is ColorBrewer PuOr.** Viridis (Smith & van
der Walt) is monotonic in lightness and CVD-safe by construction, so it degrades to a legible
greyscale ramp — the property no hand-picked ramp has. Nine stops: `#440154 #472D7B #3B528B #2C728E
#21918C #27AD81 #5EC962 #AADC32 #FDE725`. Also ship `cividis()` (Nuñez, Anderton & Renslow 2018 —
optimised specifically for deuteranomaly) and `blues()` (ColorBrewer 9-class). Diverging defaults to
PuOr rather than the conventional RdBu because ColorBrewer's own colourblind filter passes PuOr and
red-versus-blue loses lightness symmetry under protanopia: `#B35806 #E08214 #FDB863 #FEE0B6 #F7F7F7
#D8DAEB #B2ABD2 #8073AC #542788`. `blue_red()` is available for those who want it.

**6. CVD-safety is asserted by a test, not by a comment.** A test-only module implements the
Viénot/Brettel/Mollon (1999) LMS simulation for protanopia, deuteranopia and tritanopia, plus WCAG
relative-luminance contrast. Every shipped categorical scheme must keep a minimum pairwise ΔE across
all three simulations for its first *n* entries; every style × scheme × mode combination must clear
4.5:1 for text and 3:1 for marks (WCAG 1.4.11 non-text contrast). This is the only thing that
converts "CVD-safe by default" from a claim into a property, and it is cheap: ~120 lines of pure
matrix maths in a language with no floats-to-string ambiguity in the hot path.

**7. `Color = Literal | CssVar(name, fallback)`, with the fallback mandatory.** shadcn's
`ChartConfig` is the best-aged idea in the React lineage, and the reason it works is that a CSS
variable is a *late binding*. On the BEAM there is no stylesheet to bind against, so a var without a
literal fallback is unrenderable — make that state unrepresentable rather than diagnosable. A
`Duo(light, dark)` pairs them.

**8. CSS variables survive SSR through a scoped `<style>` block, never through presentation
attributes.** This is a hard browser fact and it dictates the renderer: `fill="var(--x)"` as a
presentation attribute does **not** resolve — `var()` is only substituted inside CSS declarations.
So the emission rule is:

- `FixedPaint(Literal(hex))` → presentation attribute (`fill="#0072B2"`). Cheapest, survives
  SVG-as-`<img>`, email clients, and any CSS-stripping pipeline.
- Anything involving a var or a dark override → a generated class plus a rule in one `<style>`
  inside `<defs>`, **every selector prefixed with `#<chart-id>`** so an inline `<svg>` cannot leak
  styles into the host document (an inline SVG's `<style>` is document-global — this is a real
  footgun, not a hypothetical).
- The light literal is emitted as a presentation attribute *as well*. Presentation attributes lose
  to any author rule on specificity, so the dark rule still wins, and a stripped `<style>` still
  renders a correct light chart. The fallback is free.

`ColorMode` makes the trade explicit: `Fixed(Light | Dark)` resolves every `Duo` and every `CssVar`
to a literal at build time and emits no `<style>` at all (use this for PNG conversion, email, and
anything embedded as an image); `Adaptive` emits the class-plus-`@media (prefers-color-scheme: dark)`
form. One `Chart`, both themes, no recompile.

**9. `Theme(style, context, mode)`, applied at `build`, not at render.** seaborn's style-versus-
context split is the one thing nobody else models (prior art, converged-on item 9). `Style` is
appearance: background, text, axis, grid ink as `Duo`s, the three default schemes, font family, grid
policy. `Context` is size-for-medium: base font px, a scale factor, stroke width, minimum mark size
— `report()` (server-rendered, read at a fixed width, generous), `dashboard()` (dense, small),
`slide()`. Context must be resolved **before** layout, because font size feeds the metrics → margin
→ re-range cycle; a theme applied to a rendered string would be a lie. There is no theme merge, no
global mutation, no partial override: `build(chart, theme, metrics, size)` takes it as a mandatory
argument.

**10. Accessibility: L1 always, L2 opt-in, L3/L4 never.** Lundgard & Satyanarayan's four-level model
found blind readers rate L3 (perceptual trends) most useful and L4 (domain context) least — and L3
is precisely what a library cannot derive without lying. So: `role="img"`, `<title>`, `<desc>` and
`aria-labelledby` on every root, always. The L1 sentence is generated from mark type, channel labels,
scale types and axis extents — available from the spec alone. L2 (n, min, max, extremum category) is
opt-in and computed *only* from the trained scale domains the layout already produced; it states
facts, never trends. Authors can override both slots. The generated text is English-only in v0.1.

**11. A data table is a sibling of the SVG, generated from the built scene.** `render` keeps its
signature — `Chart -> String` returning bare SVG is the primary claim and stays untouched.
`render_figure` wraps it in `<figure>` with a `<details><table>` fallback. The table is built from
the *erased* channels (`List(Float)` / `List(String)`) after the build step, not from `Chart`,
because layers may hold different `row` types — the erasure boundary decided in prior art open
question 7 is what makes a uniform table possible at all.

## Concrete shapes

```gleam
// dapper/color — public, frozen: third-party renderers must pattern-match these.
pub type Color {
  Literal(hex: String)
  CssVar(name: String, fallback: String)   // fallback is not optional
}

pub type Duo { Duo(light: Color, dark: Color) }

pub fn mono(c: Color) -> Duo
pub fn relative_luminance(hex: String) -> Float
pub fn contrast_ratio(a: String, b: String) -> Float
pub fn mix(from: String, to: String, t: Float) -> String   // piecewise-linear in Oklab
pub fn to_hex(r: Float, g: Float, b: Float) -> String       // own rounding; never float.to_string
```

```gleam
// dapper/scheme — three distinct opaque types. This is the type-level intent guarantee.
pub opaque type Categorical
pub opaque type Sequential
pub opaque type Diverging

pub type Interp { Quantize(bins: Int) Smooth }

pub fn okabe_ito() -> Categorical
pub fn tol_bright() -> Categorical
pub fn explicit(by_label: Dict(String, Duo), fallback: Categorical) -> Categorical  // shadcn's ChartConfig, typed
pub fn viridis() -> Sequential
pub fn cividis() -> Sequential
pub fn blues() -> Sequential
pub fn pu_or() -> Diverging
pub fn blue_red() -> Diverging
pub fn interpolation(Sequential, Interp) -> Sequential

pub fn cat_at(Categorical, index: Int) -> Duo          // wraps, never fails
pub fn seq_at(Sequential, t: Float) -> Duo             // t clamped to 0.0..1.0
pub fn div_at(Diverging, t: Float) -> Duo              // t in -1.0..1.0

pub type Scheme { Cat(Categorical) Seq(Sequential) Div(Diverging) }  // erased, legend/Scene only
```

```gleam
// dapper/encode — the colour channel. Note the mandatory label and midpoint.
pub opaque type ColorChannel(row)

pub fn nominal(label: String, of: fn(row) -> String, using: Categorical) -> ColorChannel(row)
pub fn quantitative(label: String, of: fn(row) -> Float, using: Sequential) -> ColorChannel(row)
pub fn divergent(label: String, of: fn(row) -> Float, around: Float, using: Diverging) -> ColorChannel(row)
pub fn constant(Duo) -> ColorChannel(row)
```

```gleam
// dapper/theme
pub opaque type Style
pub opaque type Context
pub opaque type Theme

pub type GridLines { NoGrid HorizontalGrid VerticalGrid BothGrid }
pub type Appearance { Light Dark }
pub type ColorMode { Fixed(Appearance) Adaptive }

pub fn plain() -> Style
pub fn minimal() -> Style                                  // no grid, no chart border
pub fn with_categorical(Style, Categorical) -> Style
pub fn with_ink(Style, text: Duo, axis: Duo, grid: Duo, background: Duo) -> Style

pub fn report() -> Context      // 13px base, scale 1.0, 1.5px strokes
pub fn dashboard() -> Context   // 11px base, scale 0.85, 1.0px strokes
pub fn slide() -> Context       // 18px base, scale 1.4, 2.5px strokes
pub fn scaled(Context, by: Float) -> Context

pub fn new(style: Style, context: Context, mode: ColorMode) -> Theme
pub fn default() -> Theme       // plain() + report() + Adaptive
```

```gleam
// dapper/scene — the public seam. Paint is frozen; keep it at three variants.
pub type Paint {
  NoPaint
  FixedPaint(Color)
  AdaptivePaint(role: String, light: Color, dark: Color)
}

pub type Rule { DarkFill(role: String, hex: String) DarkStroke(role: String, hex: String) }

pub type A11y {
  A11y(title: String, description: String, table: Table)
}
pub type Table { Table(columns: List(String), rows: List(List(String))) }

pub type Scene {
  Scene(id: String, width: Float, height: Float,
        rules: List(Rule), nodes: List(Node), a11y: A11y)
}
```

```gleam
// dapper — top level
pub fn build(chart: Chart(row, msg), theme: Theme, metrics: Metrics, size: Size) -> Scene
pub fn render(Scene) -> String                  // bare <svg>
pub fn render_figure(Scene) -> String           // <figure><svg/><details><table/></details></figure>

// dapper/a11y
pub fn describe(Scene) -> String                // L1 sentence, also usable outside SVG
pub fn with_statistics(Scene) -> Scene          // L2: n, min, max, extremum label — facts only
pub fn table_html(Table, id: String) -> String
```

Emitted shape, `Adaptive` mode:

```xml
<svg id="rev" role="img" aria-labelledby="rev-t rev-d" viewBox="0 0 640 360">
  <title id="rev-t">Revenue by quarter</title>
  <desc id="rev-d">Bar chart. Revenue (0 to 4.2 million USD, linear) by Quarter
    (4 categories, band). Coloured by Region, 3 categories.</desc>
  <defs><style>@media (prefers-color-scheme:dark){
    #rev .dp-c0{fill:#3E9BE0} #rev .dp-c1{fill:#E8A73A} #rev .dp-ax{stroke:#8A8A8A}
  }</style></defs>
  <g aria-hidden="true"> ... axes, grid ... </g>
  <rect class="dp-c0" fill="#0072B2" x="..." y="..." width="..." height="..."/>
</svg>
```

## Task breakdown

| # | Task | Size | Unblocks |
|---|---|---|---|
| T1 | `dapper/color`: `Color`, `Duo`, hex parse/format with own rounding, relative luminance, contrast ratio, sRGB↔Oklab, `mix`. | M | everything below |
| T2 | Palette data module: the tables above as literal `Duo` lists, light and dark. | S | T4 |
| T3 | Test-only CVD simulation (Viénot/Brettel) + contrast assertions over every scheme × style × mode. **Verify every hex in T2 before publishing them.** | M | the CVD-safe claim; T2 sign-off |
| T4 | `dapper/scheme`: three opaque types, smart constructors, `cat_at`/`seq_at`/`div_at`, `Quantize`/`Smooth`, `explicit`. | M | colour channels, legends |
| T5 | Mandatory `label` on all channel constructors + `ColorChannel(row)`. Coordinate with the encoding stream — this changes their signatures. | S | T8, T10, axis titles, legend |
| T6 | `dapper/theme`: `Style`, `Context`, `Theme`, `ColorMode`, defaults. Resolve into an internal `Resolved` record consumed by layout. | M | layout sizing, T7 |
| T7 | Paint resolution + scoped `<style>` emission in the SVG renderer; `Fixed` collapses to literals. | M | dark mode, CSS-var theming |
| T8 | L1 `describe` + `title`/`desc`/`role`/`aria-labelledby`/`aria-hidden` emission. | M | the a11y claim |
| T9 | L2 `with_statistics` from trained domains. | S | nothing (leaf) |
| T10 | `Table` from erased channels + `render_figure`. | M | nothing (leaf) |
| T11 | `validate` diagnostics for this stream (below). | S | nothing (leaf) |
| T12 | birdie snapshots: one chart × {Fixed Light, Fixed Dark, Adaptive} × {report, dashboard}. | S | regression safety |
| T13 | Docs page of swatches and CVD simulations, **rendered by dapper itself**. | S | credibility |

Diagnostics for T11: `TooManyCategories(label, n, scheme_size)`, `DivergingCenterOutsideDomain`,
`LowContrast(role, ratio, required)`, `ContrastUnknown(role)` (a `CssVar` was substituted, so the
ratio is unknowable), `ColorOnlyEncoding` (nominal colour with no redundant channel — v0.1 has none,
so this is advisory).

## Risks and unknowns

- **The hex values above are from memory of published palettes and must be verified against source
  before release.** T3 is where that happens, and the dark column is a *candidate* derived by Oklab
  lightness lift, not a published palette. Do not ship the docs page until the simulation harness
  agrees with it.
- **Inline `<svg><style>` is document-scoped.** Every rule must be `#id`-prefixed. A single unprefixed
  rule silently restyles the host page — the kind of bug users blame on the framework.
- **`Adaptive` does not work everywhere.** SVG referenced as `<img>` is a separate document: it gets
  no CSS custom properties from the host, so `CssVar` degrades to its fallback (correct, by
  construction), while `prefers-color-scheme` generally does apply. Email clients strip `<style>`
  entirely. The presentation-attribute fallback covers all of these; document the matrix.
- **Context scaling interacts with the two-pass layout bound.** A larger base font widens tick labels,
  which widens the margin, which re-ranges the scale, which may re-tick. The bound stays at two
  passes (prior art: `autosize: "fit"` is the warning), so a `slide()` context on a narrow width can
  produce a visibly tight axis. Accept and document.
- **`role="img"` collapses the subtree**, which is right for v0.1 and wrong the moment marks become
  focusable. The ARIA graphics module (`graphics-document`, `graphics-symbol`) is the forward path but
  screen-reader support is still poor; v0.1 stays with `role="img"` knowingly.
- **Oklab interpolation produces floats that must become integers.** Use dapper's own rounding, never
  `float.to_string` — this is the BEAM/JS divergence point, and it would break snapshots on exactly
  one target.
- **`Paint` and `Color` are public and frozen.** Adding a variant is breaking. Three variants each
  is the bet.

## What is explicitly NOT in v0.1

User-defined schemes (colour interpolators as functions); shape, dash and texture redundancy
channels; direct labelling; keyboard navigation of data points; sonification; ARIA live regions;
`graphics-*` roles; automatic contrast repair or auto-recolouring; theme merging or inheritance;
runtime detection of the viewer's colour scheme on the BEAM; L3/L4 description text in any form;
localisation of generated descriptions; per-mark opacity/gradient/pattern fills; legend interaction.

## Open questions needing a human call

1. **Chart id: caller-supplied or derived?** Recommendation: a mandatory argument to `build`. A
   derived hash is prettier but makes the output depend on chart contents, so any edit churns every
   snapshot and every downstream CSS selector. A random id destroys purity outright.
2. **Should `theme.default()` be `Adaptive`?** Recommendation: yes — the commonest SSR target is
   inline SVG inside an HTML page, where adaptive is strictly better and costs one `<style>` element.
   The counter-argument is that anyone converting to PNG gets a light-only chart with dead CSS.
3. **Does `explicit()` (per-series colour overrides keyed by label) belong in v0.1?** Recommendation:
   yes. It is the pressure valve that stops people wanting a props bag, and it stays inside the type
   discipline because it still produces a `Categorical`. The risk is that it becomes the default
   idiom and the CVD-safe palettes go unused.
4. **Do we guarantee contrast, or only report it?** Recommendation: guarantee it for the shipped
   styles via T3 and report it via `validate` for everything else. Auto-adjusting user colours is a
   trap.
