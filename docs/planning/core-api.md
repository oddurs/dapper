# Core API

The central type architecture: `Chart`, `Layer`, channels, scales, the build pipeline, and the
public module surface. Downstream of decision 0001; it does not revisit it.

## Decisions

### 1. Erasure happens at *layer construction*, not at `build` — and `Chart` therefore carries no row parameter

Prior art open question 7 says "erase at `build`, after stat, before training." **That is not
coherent in Gleam.** Training must see every layer, layers legitimately have different row types
(a bar series over `Sale` overlaid with a line over `Forecast`), and holding `List(Layer(?))` for
differing `?` requires existential types, which Gleam does not have. The only way to encode an
existential here is to apply the eliminator eagerly — that is, to erase. So erasure moves to the
mark constructor, which is the one point where the accessors and the data are both in scope:
`mark.bar(data: List(row), x: Discrete(row), y: Continuous(row), …) -> Layer`. `row` appears in
the constructor's signature and nowhere else. `Chart`, `Layer` and `Scene` are unparameterised,
which is also what the README's headline `render : Chart -> String` already says.

The *stage order* the grammar brief insists on (scale-transform → stat → train → map → render) is
preserved exactly; only the erasure point moves earlier. The single consequence is that **stats
operate on erased channel columns, not on user rows** — which is seaborn.objects' model, not
ggplot2's, and it dissolves the `..count..` problem differently: a `Bin` stat consumes the erased
x column and emits `x0`/`x1`/`count` columns. The cost is that the typed stat→mark contract the
grammar brief wanted (`Bin(x0, x1, count)` as a record the mark's accessors read) is unavailable;
that contract becomes a `validate` diagnostic. Given decision 0001 explicitly disclaims
compiler-checked validity and prior art files stats under "good ideas that are wrong for v0.1",
this is the right trade.

### 2. Two channel wrapper types, and time is a `Continuous`

`Continuous(row)` and `Discrete(row)`, both opaque, both wrapping an accessor. There is no
`Temporal(row)`. A timestamp channel is built with `channel.time(fn(row) -> Timestamp)`, which
erases to a Float (microseconds since epoch — under 2^53, so exact) and sets a private tag that
selects time tick generation and time formatting. This is the decision that prevents the
constructor explosion that hvega and elm-vegalite suffer: without it every mark needs
`line`/`line_time`/`area`/`area_time`, and the arity story collapses under its own combinatorics.
The tag being private means `x_transform(Log)` applied to a time channel is a `validate`
diagnostic rather than a type error — an honest instance of the line decision 0001 draws.

### 3. The scale *kind* is derived from the channel type; the user configures, never chooses

Prior art item 4 wants "`bar` requires a band scale" as the cheapest demonstration of the wedge.
Deriving the scale from the channel gives a strictly better error: passing a continuous x to a bar
is `expected Discrete(row), found Continuous(row)` **at the call site**, not three pipeline stages
deep — which was exactly the hostile error decision 0001 told us to prototype before going
further. So the chart exposes `x_domain`, `x_transform`, `x_label` and nothing that names a scale
kind. The trained scale is an output of `build`, not an input.

### 4. Opaque everything except `Scene`, `Node`, `Frame` and `Diagnostic`

In Gleam, adding a field to a public record and adding a variant to a public sum type are both
breaking. Opaque-plus-setters is the only shape where adding a knob is *not* breaking, so
`Chart`, `Layer`, `MarkKind`, `Continuous`, `Discrete`, `Resolve`, `scale.Continuous`,
`scale.Band`, `Theme` and every `*Style` are opaque from day one. `Scene`/`Node`/`Frame` are
transparent, because a seam you cannot pattern-match on is not a seam — third-party emitters and
the `custom` escape hatch both need to destructure it. Adding a `Node` variant is accepted as a
minor-breaking change and stated in the compatibility promise.

### 5. Two eliminators per mark, and domains do not go through them

The typed-FP brief's fold explosion (elm-charts: one new mark, six edited functions) is caused by
`definePlane`/`getItems`/`getLegends`/`getTickValues` each pattern-matching the mark. Fix: domains
and legend entries derive from the **erased columns plus a data-independent `Requirements`
record**, so they never case on the mark at all. That leaves exactly two total functions over
`MarkKind`:

- `mark.requirements(MarkKind) -> Requirements` — which channel roles are required, which erased
  kind each demands, default stat and move, legend shape. Data-independent; drives `validate`.
- `mark.draw(MarkKind, Style, Frame, List(Datum)) -> List(Node)` — the only site where geometry is
  computed.

Adding a mark touches one variant and two `case` arms. This is a genuine improvement over the
lineage, not a restatement of it.

### 6. Scales store parameters plus a private kind tag; they do not store closures

elm-visualization passes a dictionary of `convert`/`invert`/`ticks` closures in the record and its
own docs regret the resulting signatures. Closures in records also cannot be compared or printed,
which breaks `echo` and snapshot debugging on the BEAM. Store the parameters and dispatch inside
one function per operation. Capability split is preserved by having **two types**:
`scale.Continuous` (`convert`, `invert`, `ticks`, `nice`) and `scale.Band` (`convert`,
`bandwidth`, `step`, no `invert`).

### 7. `Resolve` is mandatory and opaque, exposing only the constructors v0.1 implements

Prior art item 7 wants `Resolve` required, because Vega-Lite's worst trap is *silent* unioning.
But shipping an `Independent` variant that `validate` then rejects is worse than not shipping it.
Opaque `Resolve` with `resolve.shared()` and `resolve.independent_color()` only: illegal states
are unconstructible, and `resolve.independent_x()` can be added later without a breaking change.

### 8. Required channels are arguments; optional channels are `Option` arguments; only constants live in `Style`

The rule is one sentence: **if it maps data, it is a function argument; if it is a constant, it is
style.** `Some(…)`/`None` at the call site is four characters that state an absence, and it keeps
`Style` free of the `row` parameter. This is decision 0001 item 5 applied literally.

### 9. `Stack` runs before training; `Dodge` runs at map

A stacked bar's y-extent exceeds any individual datum, so `Move` cannot be a post-mapping step or
every stacked chart clips. But dodging needs `bandwidth`, which only exists after the range is
known. So `Move` splits: data-space moves (`Stack`) run after stat and before training;
range-space moves (`Dodge`, `Jitter`) run during mapping. v0.1 ships `NoMove` only, but the slot
and the split are recorded now because getting it wrong silently changes every chart later.

## Concrete shapes

```gleam
// dapper/channel
pub opaque type Continuous(row)   // erases to Float, private kind: Numeric | Time
pub opaque type Discrete(row)     // erases to String

pub fn continuous(get: fn(row) -> Float) -> Continuous(row)
pub fn int(get: fn(row) -> Int) -> Continuous(row)
pub fn time(get: fn(row) -> timestamp.Timestamp) -> Continuous(row)
pub fn discrete(get: fn(row) -> String) -> Discrete(row)
```

```gleam
// dapper/mark  — arity IS the compatibility relation
pub opaque type MarkKind
pub type Requirements {
  Requirements(roles: List(Role), default_stat: Stat, default_move: Move, legend: LegendShape)
}

pub fn bar(
  data data: List(row),
  x x: Discrete(row),
  y y: Continuous(row),
  fill fill: Option(Discrete(row)),
  style style: BarStyle,
) -> Layer

pub fn line(
  data data: List(row),
  x x: Continuous(row),
  y y: Continuous(row),
  stroke stroke: Option(Discrete(row)),
  style style: LineStyle,
) -> Layer

pub fn point(
  data data: List(row),
  x x: Continuous(row),
  y y: Continuous(row),
  fill fill: Option(Discrete(row)),
  size size: Option(Continuous(row)),
  style style: PointStyle,
) -> Layer

pub fn custom(data data: List(row), draw draw: fn(Frame) -> List(Node)) -> Layer

pub fn requirements(kind: MarkKind) -> Requirements
pub fn draw(kind: MarkKind, style: Style, frame: Frame, data: List(Datum)) -> List(Node)
```

```gleam
// dapper — internal erased representation
type Column {
  Numbers(List(Float), NumericKind)
  Labels(List(String))
}
type Columns = List(#(Role, Column))
pub type Role { X | Y | Fill | Stroke | Size }

pub opaque type Layer   // Layer(kind, columns, stat, move, style, series_key)
pub opaque type Chart
```

```gleam
// dapper — public surface
pub fn chart(layers: List(Layer), resolve resolve: Resolve) -> Chart
pub fn size(Chart, width width: Float, height height: Float) -> Chart
pub fn x_domain(Chart, Domain) -> Chart
pub fn x_transform(Chart, Transform) -> Chart
pub fn y_label(Chart, String) -> Chart
pub fn metrics(Chart, metrics.Metrics) -> Chart
pub fn theme(Chart, theme.Theme) -> Chart

pub fn build(chart: Chart) -> Scene          // total
pub fn render(chart: Chart) -> String        // = build |> svg.to_string; total
pub fn validate(chart: Chart) -> List(Diagnostic)   // total, never gates render

pub type Domain { Numeric(Float, Float) | Categories(List(String)) }
pub type Transform { Identity | Log(base: Float) | Sqrt | Symlog(c: Float) }
pub type Stat { NoStat | Bin(BinSpec) | Agg(Estimator) }        // v0.1: NoStat only
pub type Move { NoMove | Stack | Dodge(gap: Float) | Jitter(w: Float) }  // v0.1: NoMove only
pub type Diagnostic { Diagnostic(severity: Severity, message: String, hint: String) }
```

```gleam
// dapper/scale — usable standalone (packaging: two public layers)
pub opaque type Continuous
pub opaque type Band
pub fn convert(Continuous, Float) -> Float
pub fn invert(Continuous, Float) -> Float
pub fn ticks(Continuous, count: Int) -> List(Float)
pub fn band_convert(Band, String) -> Option(Float)
pub fn bandwidth(Band) -> Float
```

End to end:

```gleam
pub type Sale { Sale(month: String, revenue: Float, region: String) }

pub fn revenue_svg(sales: List(Sale)) -> String {
  [
    mark.bar(
      data: sales,
      x: channel.discrete(fn(s) { s.month }),
      y: channel.continuous(fn(s) { s.revenue }),
      fill: Some(channel.discrete(fn(s) { s.region })),
      style: mark.bar_style(),
    ),
  ]
  |> dapper.chart(resolve: resolve.shared())
  |> dapper.size(width: 640.0, height: 320.0)
  |> dapper.y_label("Revenue (USD)")
  |> dapper.render
}
```

The Lustre path is the same value: `… |> dapper.build |> scene.to_lustre`.

### The pipeline, precisely

```
0  construct  List(row) × channels        -> Columns        (in the mark constructor; ERASURE)
1  transform  Columns                     -> Columns        (chart-level Transform per role)
2  stat       Columns                     -> Columns        (v0.1 NoStat)
3  move/data  Columns                     -> Columns        (Stack only; v0.1 NoMove)
4  train      List(Columns) × Resolve     -> Domains        (across all layers, always)
5  frame      Domains × Size × Metrics    -> Frame          (ticks→format→measure→margins→
                                                             re-range→re-tick; two passes, stop)
6  map        Columns × Frame             -> List(Datum)    (+ range-space Move; + stable key
                                                             (facet, series, datum_index))
7  draw       MarkKind × Frame × Datums   -> List(Node)
8  emit       Scene                       -> String | Element(msg)
```

Stages 1–8 are `build`; stage 0 already ran. Every stage is total. Stage 4 runs over a 1×1 pane
grid from day one (Polaris), so faceting is a change to stages 4–5, not a rewrite.

## Task breakdown

1. **S — `dapper/channel` + `Column`/`Role` erasure.** Unblocks every other task.
2. **S — `Columns` training: domain union per role, category ordering, `Resolve`.** Unblocks frame.
3. **M — `dapper/scale`: `Continuous` (linear/log/sqrt/time) and `Band`.** Port d3-scale verbatim.
   Standalone-releasable. Unblocks map and axes.
4. **M — `dapper/ticks`: d3 1–2–5 first, extended-Wilkinson second.** Unblocks axes; the highest
   quality-per-line item on the list.
5. **S — `dapper/scene`: `Scene`, `Node`, `Frame`, `Datum`, stable keys.** Unblocks both emitters
   and the `custom` hatch. Bars stored as `(x0, y0, x1, y1)`.
6. **M — `dapper/mark`: `MarkKind`, three constructors, `requirements`, `draw`.** Unblocks build.
7. **M — `dapper`: `Chart` opaque, setters, stages 1–7 wired.** Unblocks render.
8. **M — layout: two-pass margin reservation consuming `Metrics`.** Depends on the metrics stream.
9. **S — `validate` over `requirements` + erased columns.** Unblocks nothing; ships the honesty.
10. **S — `custom(fn(Frame) -> List(Node))`.** Sokol's lesson, cheapest insurance on the list.
11. **M — snapshot harness: birdie over `build` (the `Scene`) and over the SVG, on both targets.**

## Risks and unknowns

- **Erasure at construction is one-way.** Anything wanting the original row later — a tooltip
  carrying arbitrary user content, a typed stat→mark contract, hit-test → row — must go through
  `(series, datum_index)` and the caller's own list. Mitigated by emitting stable keys now.
- **`Continuous` hiding a `Numeric | Time` tag** means a category of mismatch (log on time,
  time-formatted linear data) is a diagnostic, not a type error. Accepted; it is the price of one
  `line` constructor.
- **Stage 3/6 `Move` split is asserted, not exercised.** v0.1 ships `NoMove`, so the split is
  untested until stacking lands, and it is the one ordering decision that is expensive to revise.
- **Transparent `Scene`/`Node`** makes every new primitive a breaking change. Bound the variant set
  to `Rect | Path | Text | Group` in v0.1 and resist growth.
- **N accessor passes over `List(row)`** — one traversal per channel at construction. Acceptable on
  BEAM for the target sizes; do not fuse speculatively.
- **`dapper/lustre` in-package** pulls a Lustre dependency into pure-BEAM users' builds.

## What is explicitly NOT in v0.1

Faceting and the pane algebra (the grid is 1×1 but real). Stats (`Bin`, `Agg` reserved, not
implemented). Moves (`Stack`, `Dodge` reserved, not implemented). `independent_x`/`independent_y`
resolve. Dual axes. Marks beyond bar/line/point. Selections, tooltips, animation, interaction
state. A serialisable spec. A `Backend` record of functions — two plain emitter functions until a
third target exists. Any `Dynamic` props bag. Per-layer scale overrides. `repeat`.

## Open questions needing a human call

1. **Does `Chart` really lose its `row` parameter?** Decision 1 above contradicts the literal
   wording of prior art open question 7 and the typed-FP brief's "thread `row` everywhere". The
   argument is that the literal wording is not expressible in Gleam. If the answer is instead
   "keep `Chart(row)`, force users to unify heterogeneous layers into a sum row", say so now —
   it is unfixable after v0.1.
2. **`dapper/lustre` in-package, or a separate `dapper_lustre`?** In-package is one release to
   cut; separate keeps the BEAM dependency graph clean. Recommend in-package for a solo maintainer.
3. **Is `Discrete` keyed by `String`, or by `fn(row) -> a` plus `fn(a) -> String`?** String is
   simpler and matches every erasure decision above; the generic form buys ordering by a user enum
   without a `List(String)` domain literal. Recommend `String`.
4. **Does `chart()` default `size`, or require it?** No autosize exists without a viewport, and SSR
   needs explicit dimensions. Recommend a 640×400 default on the opaque type with `size` as an
   override — a starting value, not merge semantics.
5. **Is `gleam_time` a v0.1 dependency?** The README lists time scales in v0.1, and decision-doc
   open question 4 says settle time before `Scale` hardens. Confirm the dependency, or cut time
   scales to v0.2 and drop `channel.time` for now.
