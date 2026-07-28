# Scene and rendering

The stream that makes the primary claim true. Everything here is downstream of one sentence:
`render : Chart -> String` is pure and total on the BEAM, and the same `Chart` is a Lustre
component. `Scene` is the seam; the two emitters are two plain functions over it.

## Decisions

**1. `Scene` is a shallow tree of absolutely-positioned primitives. No transform stack.**
Every coordinate in a `Scene` is final SVG user-space, y-down, origin at the top-left of the whole
canvas — not of the plot frame. `Group` exists only to carry a class, a clip and a11y flags; it
never translates its children. This is `diagrams`' `RTree` discipline ("all measurements resolved
to output units before any backend sees it") and matplotlib's artist layer. The payoff is that
hit-testing is a point-in-rect test with no matrix inversion, snapshots are readable, and the two
emitters cannot disagree about composition order because there is nothing to compose. The single
exception is `Label(rotate: Float)`, emitted as `rotate(a x y)` about the label's own anchor,
because rotated tick labels are unavoidable and a per-element rotation is not a stack.

**2. Rects are `(x0, y0, x1, y1)`.** Accepted at kickoff; the reasons worth writing down are that
SVG treats a negative `width` as an error and simply does not render the element, so `(x,y,w,h)`
forces sign gymnastics at every negative-value bar and every downward stack; interval endpoints are
what `Stat`/`Move` arithmetic actually composes over (a dodge is an interval split, a stack is an
interval sum); and a rect stored as its corner pair is a thing a coordinate transform can map,
whereas a rect stored as an origin-plus-extent has to be reconstructed first. Normalisation
(`min`/`max`) happens once, in the emitter.

**3. The primitive vocabulary is closed and public; the `Scene` container is opaque.** `Prim` and
`Node` are public sum types — that is the whole point of a public seam, and third parties writing a
PNG emitter need to match on them. Adding a `Prim` variant is therefore a semver-major event, so
the vocabulary ships complete on day one even where v0.1 marks do not use all of it: `Rect`,
`Line`, `Path`, `Symbol`, `Label`. `Scene` itself is opaque with a builder, because it *will* grow
fields (defs, a11y table, facet metadata) and in Gleam a public record field is a breaking change.
There is no `Raw(String)` variant. The escape hatch is `custom(fn(Frame) -> Scene)`, which returns
primitives, so raw markup is never needed and the escaping surface stays exactly one function wide.

**4. Style is fully resolved per mark. No cascade, no inheritance.** Every `Mark` carries a
complete `Style`. Verbosity is the price of the two emitters agreeing and of snapshots being local.
The emitter omits attributes equal to the SVG default; it does not hoist shared attributes onto
groups (that is a v0.2 size optimisation and a determinism hazard). Colour is
`Literal(String) | CssVar(name, fallback)` per shadcn's `ChartConfig`, the best-aged idea in the
React lineage. **A `CssVar` always emits with its literal fallback** — `fill="var(--chart-1,
#4e79a7)"` — so a server-rendered SVG dropped into an `<img>`, an email, or a resvg PNG still looks
right, while a page that defines the variable gets themed for free. This is the one place dapper
lets style resolution happen outside itself, and the fallback is what makes it safe.

**5. Every emitted mark carries a `Key`, and `Key` is opaque.** `(facet, series, datum_index)` for
data marks; a closed `Chrome(role, index)` for axes, grids, frames and legends. Opaque because a
content-derived datum key (`fn(row) -> String`) is the obvious v0.2 addition and must not break
pattern matches. `key_to_string` is one shared function: it produces the Lustre keyed-diff key and
the `data-k` attribute in the SVG string, and they are the same string by construction. That is
what buys keyed animation, hit-testing, and ECharts' SSR-then-hydrate split — the client can find
the server's bar #12 without re-rendering. Keys default to *on* in the string emitter; the bytes
are the price of hydration being possible at all.

**6. One attribute-list function, two serialisers.** The rendering brief names "two render paths
drift" as the failure mode of this design. The mechanism against it is structural, not a test:
`internal/attrs.for_prim(Prim, Style, Options) -> List(#(String, String))` produces already-
formatted name/value pairs, and both emitters consume it. The SVG emitter escapes and concatenates
into a `StringTree`; the Lustre emitter maps each pair through `attribute.attribute`, which escapes
itself. **Escaping therefore lives only in the SVG emitter** — putting it in `Scene` construction or
in `attrs` would double-escape on the Lustre path, which is the first bug this design would
otherwise ship.

**7. `Scene` has no `msg` type parameter.** Interaction attaches at the Lustre emitter via an
injected `fn(Key) -> List(Attribute(msg))`. Threading `msg` through `Scene` would infect the pure
BEAM path with a phantom type for no benefit and would make `Scene` unusable as a snapshot subject.
The user's `update` still owns all state (prior art: do not rebuild Recharts v3's store).

**8. dapper pins its own float formatter.** Arithmetic agrees (both targets are IEEE-754);
float-*to-string* does not, and it is where snapshots break first. Specification:
round to `decimals` (default 2) by scaling to an `Int` with ties away from zero
(`floor(x*10^d + 0.5)` for `x >= 0`, `ceil(x*10^d - 0.5)` otherwise — never banker's rounding,
which differs by target and by stdlib version); format integer and fractional parts through
`int.to_string`; strip trailing zeros and a bare trailing `.`; **if the scaled integer is 0, emit
`"0"`, never `"-0"`** (JS `(-0).toString()` is `"0"`, Erlang's is `"-0.0"`); **never emit exponent
notation** — at 2 decimals with coordinates clamped to ±1e9 plain decimal always suffices, which
sidesteps the fact that JS switches to exponential at 1e21 and below 1e-6 while Erlang's thresholds
differ; non-finite inputs map to `"0"` because a render path must be total, and `validate` is what
tells the user. Two decimals is sub-hundredth-of-a-pixel at any real chart size; D3 and Plot emit
full doubles and pay 30–40% more bytes for nothing.

**9. SVG correctness, decided rather than discovered.** Always emit `xmlns` and
`viewBox="0 0 w h"`. Also emit `width`/`height` by default (`Sizing(Fixed)`), because an SVG with
no intrinsic size renders at 300×150 inside `<img>` and collapses unpredictably in flex; `Sizing`
`Responsive` drops them and is documented as *scaled, not re-laid-out* — real responsiveness needs
re-measurement and a client round trip. `shape-rendering="crispEdges"` on the gridline and axis-rule
groups only; dapper does **not** snap coordinates to half-pixels, because snapping is DPI-dependent
and would break the property that geometry is exactly scale output. Path data is absolute commands
only (`M L C Z`), space-separated, no relative forms and no implicit-repeat elision — shorter output
is a false economy against diffable snapshots. `clipPath` ids are `{id_prefix}-clip-{n}` with `n` a
render-order counter and `id_prefix` a caller-settable `Options` field defaulting to `"dapper"`; no
randomness, no global counter, and two charts sharing a page must be given distinct prefixes (a
documented sharp edge, not a bug we can purely solve). `role="img"`, `<title>` and an L1 `<desc>` on
the root; `aria-hidden="true"` on decorative groups.

**10. No `Backend` record of functions.** Two targets, two functions. `diagrams`' `Backend b v n`
with existential `Prim` is elegant and produced famously unreadable type errors. Revisit only when a
third real target exists.

## Concrete shapes

```gleam
// dapper/scene.gleam
pub opaque type Scene {
  Scene(width: Float, height: Float, title: String, desc: String, root: List(Node))
}

pub fn scene(width: Float, height: Float, root: List(Node)) -> Scene
pub fn with_title(Scene, String) -> Scene
pub fn with_desc(Scene, String) -> Scene
pub fn size(Scene) -> #(Float, Float)
pub fn nodes(Scene) -> List(Node)

pub type Node {
  Group(class: String, clip: Clip, decorative: Bool, children: List(Node))
  Mark(key: Key, prim: Prim, style: Style)
}

pub type Clip {
  NoClip
  ClipRect(x0: Float, y0: Float, x1: Float, y1: Float)
}

pub type Prim {
  Rect(x0: Float, y0: Float, x1: Float, y1: Float, radius: Float)
  Line(x0: Float, y0: Float, x1: Float, y1: Float, crisp: Bool)
  Path(segments: List(Seg), closed: Bool)
  Symbol(cx: Float, cy: Float, area: Float, shape: Shape)
  Label(
    x: Float, y: Float, text: String, rotate: Float,
    anchor: Anchor, baseline: Baseline, font: Font,
  )
}

pub type Seg {
  MoveTo(x: Float, y: Float)
  LineTo(x: Float, y: Float)
  CubicTo(x1: Float, y1: Float, x2: Float, y2: Float, x: Float, y: Float)
}

pub type Shape { Circle  Square  Triangle  Diamond  Cross }
pub type Anchor { Start  Middle  End }
pub type Baseline { Alphabetic  Hanging  Central }

pub type Style {
  Style(fill: Paint, stroke: Paint, stroke_width: Float, opacity: Float, dash: List(Float))
}
pub type Paint { NoPaint  Solid(Colour) }
pub type Colour { Literal(String)  CssVar(name: String, fallback: String) }
```

```gleam
// dapper/scene/key.gleam
pub opaque type Key {
  Datum(facet: Int, series: Int, index: Int)
  Chrome(role: Role, index: Int)
}
pub type Role { AxisX  AxisY  Grid  Frame  Legend  Annotation }

pub fn datum(facet: Int, series: Int, index: Int) -> Key
pub fn chrome(role: Role, index: Int) -> Key
pub fn to_string(Key) -> String        // "f0s1d17" | "axis-x:3"
pub fn facet(Key) -> Result(Int, Nil)
```

```gleam
// dapper/format.gleam  — public: custom marks must use it
pub fn num(x: Float, decimals: Int) -> String
pub fn coord(x: Float) -> String       // num(x, 2), clamped to +/- 1.0e9
```

```gleam
// dapper/render.gleam
pub opaque type Options {
  Options(decimals: Int, sizing: Sizing, id_prefix: String, keys: Bool, a11y: A11y)
}
pub type Sizing { Fixed  Responsive }
pub type A11y { Minimal  Described }

pub fn options() -> Options
pub fn with_decimals(Options, Int) -> Options
pub fn with_sizing(Options, Sizing) -> Options
pub fn with_id_prefix(Options, String) -> Options
pub fn with_keys(Options, Bool) -> Options
```

```gleam
// dapper/svg.gleam                          (no lustre import)
pub fn to_string(scene: Scene, opts: Options) -> String

// dapper/internal/attrs.gleam               (shared by both emitters)
pub fn tag_of(Prim) -> String
pub fn for_prim(Prim, Style, Options) -> List(#(String, String))

// dapper/lustre_svg.gleam
pub fn to_element(
  scene: Scene,
  opts: Options,
  on: fn(Key) -> List(attribute.Attribute(msg)),
) -> element.Element(msg)
```

## Task breakdown

1. **S — `dapper/format`.** `num`/`coord` per decision 8, with unit tests for negative zero, ties,
   trailing zeros, clamping and non-finite. Run under `--target erlang` *and* `--target javascript`
   from the first commit. Unblocks: literally everything.
2. **S — `Key` + `key.to_string`.** Unblocks: emitters, and core-api's mark emission.
3. **M — `dapper/scene`.** The ADT above, opaque `Scene`, builders and accessors, doc comments
   stating the coordinate contract. Unblocks: core-api can compile against a real seam.
4. **M — `internal/attrs`.** `tag_of` + `for_prim`, default-attribute omission, `Paint`/`CssVar`
   rendering, dash arrays, path-data construction, symbol geometry (area→radius, the five shapes).
   Unblocks: both emitters.
5. **M — `dapper/svg.to_string`.** `StringTree` assembly, root element, `viewBox`/`Sizing`,
   `clipPath` defs and id allocation, `crispEdges` groups, `role`/`title`/`desc`, `data-k`.
6. **S — escaping.** One `escape_text` / `escape_attr` pair; CSS-var-name validation
   (`[-A-Za-z0-9_]` or drop); a hostile-string fixture (`"/><script>`, `&amp;`, RTL, emoji, newline)
   as both a datum label and a title. Unblocks: shipping without an injection bug.
7. **M — snapshot harness.** birdie over ~12 hand-built `Scene` fixtures (no grammar dependency),
   asserted byte-identical on both targets in CI. This is the regression net for decisions 8 and 9.
8. **M — `dapper/lustre_svg.to_element`** plus the parity test
   `element.to_string(to_element(s, o, no_events)) == svg.to_string(s, o)`. Structural parity comes
   from task 4; the test exists to catch the day someone bypasses it.
9. **S — `Options`.** Builders, defaults, docs for the id-prefix sharp edge and for
   `Responsive` meaning scaled.
10. **S — external-renderer smoke check.** The snapshot fixtures opened in Chrome, Safari, resvg and
    librsvg, plus one `data:` URI round trip. Manual, once, before tagging.
11. **M — `custom(fn(Frame) -> Scene)` wiring.** Blocked on core-api's `Frame`. Terminal and
    one-way, per the ECharts `renderItem` shape.

## Risks and unknowns

- **Lustre as a hard dependency of the package.** One package keeps release friction low for a solo
  maintainer, but every BEAM-only user then compiles Lustre. Mitigated by keeping `scene`, `format`,
  `svg` and `attrs` Lustre-free so it is only a build-time cost; the fallback is a `dapper_lustre`
  split, which is cheap to do later and expensive to undo.
- **Rounding to 2 decimals can make a thin bar degenerate** (`x0 == x1`) at large category counts,
  producing an invisible mark. Needs a minimum-extent rule in the mark layer, not in the emitter.
- **CSS variables do not resolve inside `<img>` or in most PNG converters.** The literal fallback
  handles it; the residual risk is a user who sets only the variable and never sees the fallback
  path until someone screenshots the chart.
- **Snapshot churn.** Any change to attribute order, default omission or precision rewrites every
  snapshot. Freeze attribute order early and treat it as public.
- **10k marks of fully-resolved style is a large string.** Acceptable per the accepted scope; the
  answer past that is a transform, not a backend.
- **Lustre's keyed-element and attribute APIs** are the one external surface that can move under us.

## What is explicitly NOT in v0.1

A `Backend` record of functions. Canvas, WebGL, PNG, PDF, headless anything. A transform/matrix
stack. Gradients, patterns, filters, markers, arrowheads, text-on-path. Curve interpolation
(`CubicTo` exists in the ADT; no mark emits it yet). Animation and transitions. A hit-test spatial
index. Attribute hoisting, class-based style sharing, or any output minification. Text-to-path
conversion. `Raw` markup. User-supplied CSS classes derived from data.

## Open questions needing a human call

1. **One package or `dapper` + `dapper_lustre`?** Recommendation: one package for v0.1; revisit if
   a BEAM-only user complains about the dependency.
2. **`data-k` on by default in the string emitter?** It is what makes hydration possible and costs
   roughly 12 bytes per mark. Recommendation: on.
3. **Default `decimals`: 2 or 3?** 2 is my recommendation; 3 only if someone intends charts wider
   than ~4000 units.
4. **Should the Lustre emitter default to `Responsive` while `svg.to_string` defaults to `Fixed`?**
   Two defaults is a trap, but it is also what each caller actually wants. Recommendation: single
   `Fixed` default, and document `with_sizing(Responsive)` prominently in the Lustre guide.
5. **Is `Scene` versioned in its own right?** If third parties are meant to write emitters, `Prim`
   changes are a public API event and that should be stated in the README before v0.1 ships.
