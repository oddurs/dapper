# dapper v0.1 plan

Supersedes the nine stream plans in `docs/planning/` wherever they disagree with it. Downstream of
[decision 0001](decisions/0001-positioning.md) and [prior art](prior-art.md); it does not revisit
them. Where a stream plan and this document conflict, this document wins.

---

## Architecture in one page

dapper is a **compiler from a typed spec to a resolved scenegraph, plus two folds over that
scenegraph**. There is no runtime, no DOM, no measurement at render time, and no mutable state.

```
        List(row) × accessor channels
              │  mark.bar / mark.line / mark.point / mark.custom
              ▼  ─────────── ERASURE: `row` disappears here ───────────
            Layer                       (opaque: MarkKind, Columns, Style, series label)
              │  dapper.chart(layers, resolve:, theme:, size:)
              ▼
            Chart                       (opaque, unparameterised, printable, comparable)
              │
              │  1  transform   Columns -> Columns        (per-role Log/Sqrt; identity by default)
              │  2  stat        Columns -> Columns        (v0.1 identity, stage present)
              │  3  move/data   Columns -> Columns        (v0.1 identity, stage present)
              │  4  train       List(Columns) × Resolve -> Domains
              ▼
           Domains                      (Domain = Empty | Numeric(lo,hi) | Categorical(List(String)))
              │  layout.solve(domains, size, theme, metrics, axis_opts)   ← two passes, then stop
              ▼
            Frame                       (TRANSPARENT: canvas Rect, plot Rect, x/y Scale, ticks,
              │                          kept labels, AxisSpace per edge, resolved Theme)
              │  5  map         Columns × Frame -> List(Datum)   (+range-space move, +Key)
              │  6  draw        MarkKind × Style × Frame × Datums -> List(Node)
              │  7  chrome      Frame × Theme × Series           -> List(Node)   (axes, grid, legend)
              ▼
            Scene                       (opaque container; Node/Prim are public closed sums)
              ├─ svg.to_string(scene, opts)        -> String          pure & total on the BEAM
              └─ dapper_lustre.static(scene)       -> Element(msg)    second package
```

Types at the boundaries, in one line each. `Columns = List(#(Role, Column))` where
`Column = Numbers(List(Float), NumericKind) | Labels(List(String))` — the erased representation, one
column per encoding role, all layers uniform. `Role = X | Y | Fill | Stroke`. `Datum` is a mapped
row: pixel coordinates plus a `Key`. `Key = DatumKey(facet: Int, series: String, index: Int) |
ChromeKey(Role, Int)`, opaque, one stringifier. `Scale = Linear | Log(base) | Band(...)` — closed
sums holding *parameters*, never closures, so they print, compare and can be inspected by `validate`.

Two functions and two option-carrying siblings are the whole public entry surface:

```gleam
pub fn build(chart: Chart) -> Scene                            // total
pub fn render(chart: Chart) -> String                          // = build |> svg.to_string; total
pub fn validate(chart: Chart) -> List(Diagnostic)              // total; never gates render
pub fn build_with(chart: Chart, opts: Options) -> Scene
pub fn render_with(chart: Chart, opts: Options) -> String
pub fn validate_with(chart: Chart, opts: Options) -> List(Diagnostic)
```

`Options` is opaque and carries the *rendering environment* — `metrics`, chart `id`, `decimals`,
`Sizing`, `keys`. The `Chart` carries the *chart description* — layers, resolve, theme, size, labels,
domains, margin policy. Nothing is merged; nothing is global.

---

## Decision register

### Core types and erasure

| # | Decision | Why |
|---|---|---|
| C1 | `Chart`, `Layer` and `Scene` carry **no** `row` parameter. Erasure happens inside the mark constructor. | The only shape where layers may hold different row types, `Chart` stays printable/comparable, and `render : Chart -> String` is literally true. |
| C2 | The justification is **not** "Gleam lacks existentials" — it encodes them by closing over the witness. It is that a deferred `fn() -> Columns` in `Layer` destroys `echo`, equality and snapshot debugging, and buys only stats-over-rows, which v0.1 does not ship. | Corrects the false premise in `core-api` D1. |
| C3 | Data lives on the **mark**, not the chart. `mark.bar(data:, x:, y:, …) -> Layer`; `dapper.chart(layers, …)`. | Follows from C1; kills `roadmap`'s `chart.new(data, metrics)`. |
| C4 | Stage order is fixed forever: transform → stat → data-move → train → layout → map → range-move → draw → emit. All stages are threaded through `build` from day one, identities where unimplemented. | Inserting a stage later silently changes every existing chart. |
| C5 | Two channel wrappers only: `Continuous(row)`, `Discrete(row)`, both opaque, both taking a mandatory `label: String`. | Arity-as-compatibility; the label is the only human-readable name left after accessors delete field names, and axis titles, legends and `<desc>` need it. |
| C6 | Opaque: `Chart`, `Layer`, `MarkKind`, channels, `Resolve`, `Scale`, `BandScale`, `Theme`, `Metrics`, `Options`, `Key`, `Scene`, every `*Style`. Transparent: `Node`, `Prim`, `Frame`, `Domain`, `Diagnostic`. | Opaque-plus-setters is Gleam's only non-breaking growth path; a seam you cannot destructure is not a seam. |
| C7 | `Diagnostic` is a **public closed sum** with one variant per condition, plus `severity` and a `message` renderer. Adding a variant is minor-breaking and stated in the compatibility promise. | Tests must assert on `EmptyDomain(X)`, not a string. |
| C8 | `Resolve` is mandatory and opaque; v0.1 exposes `resolve.shared()` and `resolve.independent_color()` only. | Vega-Lite's worst trap is silent unioning; a variant `validate` then rejects is worse than none. |
| C9 | Two total eliminators over `MarkKind`: `requirements/1` and `draw/4`. `Requirements` gains `min_extent: Float` and `legend: LegendShape` from day one. | Domains and legends derive from erased columns, never from the mark. `min_extent` closes G7. |
| C10 | `custom(data: List(row), draw: fn(Frame) -> List(Node)) -> Layer` — erases `data` to `Columns` like any other mark and hands `draw` the `Frame`; it returns `List(Node)`, never a `Scene`. | A layer returning a whole `Scene` cannot compose with other layers. One-way, terminal, per ECharts' `renderItem`. |

### Scales, ticks, numbers

| # | Decision | Why |
|---|---|---|
| S1 | Scale domains erase to `Float`/`String`. Scales are closed sums of parameters, never records of closures. | `validate` cannot inspect a closure; closures kill `echo` and equality. |
| S2 | Three types: `Scale` (continuous: convert/invert/ticks/nice/clamp), `BandScale` (convert/bandwidth/step, **no** invert), `OrdinalScale(a)`. `point` is a `BandScale` constructor with `padding_inner = 1.0`. | d3's decomposition; a fourth type to catch one mistake is not worth it when `validate` emits `ZeroBandwidth` free. |
| S3 | The scale **kind is derived from the channel type**. The user sets `x_domain`, `x_transform`, `x_label`; never a scale kind. `bar` takes `x: Discrete(row)`. | A continuous x passed to `bar` reads `expected Discrete(row), found Continuous(row)` *at the call site* — better than the three-stages-deep error. The band-scale invariant survives one level down; `dapper/scale` stays standalone-usable. |
| S4 | `Domain` is a monoid (`Empty` identity, total `union`); training is `list.fold`. Categorical order is **first appearance in layer-construction order, then row order**. | Sorting silently reorders bar charts. The traversal order is a tested invariant (closes G4). |
| S5 | Ticks: d3's 1–2–5 only. **Extended-Wilkinson is cut from v0.1 entirely.** | Its density term makes ticks layout-dependent and its legibility term needs `Metrics` — the ticks↔layout fixpoint prior art forbids, entered by accident. |
| S6 | Never trust `log10` directly. One shared helper truncates it, verifies with an integer-exponent power comparison and corrects the off-by-one; both `ticks` and `format` use it. | `math:log10` and `Math.log10` may differ in the last ulp; one ulp flips a floor and changes the tick step. This is the sharpest cross-target hazard anyone found. |
| S7 | **Time scales, `channel.time`, `dapper/time/*` and `gleam_time` are cut to v0.2.** | 60–80 h for the interval algebra alone — the difference between a shippable v0.1 and a fantasy budget. `ContinuousKind` reserves `Time(Zone)` inside an opaque type, so v0.2 is non-breaking. Update the README. |
| S8 | One formatter: **`dapper/format`, public, in core, importing nothing from dapper.** `coord/1` (2 dp, clamped ±1e9, never exponent, non-finite → `"0"`), `fixed/2` (0–6 dp, guarded so `\|x\|·10^d < 2^53`), `si/2`, `scientific/2` (digits assembled, never via `Int` scaling), `tick_format/2` + `label/2`. | Reconciles five conflicting specs. Exponents are banned **in geometry**, permitted **in tick labels** via an explicit format, so a 4.2e9 axis reads `4.2G`, not `4200000000`. |
| S9 | `float.to_string` and `string.inspect` are banned in `src/`, enforced by a grep in CI. | Measured divergence on both. |

### Scene and rendering

| # | Decision | Why |
|---|---|---|
| R1 | `Scene` is a shallow tree of absolutely-positioned primitives in final SVG user space. No transform stack; `Label(rotate)` is the one per-element exception. | Hit-testing is point-in-rect; the emitters cannot disagree about composition because there is nothing to compose. |
| R2 | Rects are `(x0,y0,x1,y1)`. | Negative SVG `width` silently drops the element; endpoints are what stat/move arithmetic composes over. |
| R3 | **The `Scene` never holds an unresolved colour.** `Paint = NoPaint \| Solid(Colour)`, `Colour = Literal(hex)`. All lateness — CSS vars, dark overrides — is a `Rule` in `scene.rules`, emitted as one `#id`-scoped `<style>` inside `<defs>`, plus the light literal as a presentation attribute. | `fill="var(--x)"` in a presentation attribute **does not resolve**. Deletes `scene`'s `CssVar` colour and `theming`'s `AdaptivePaint` in one move. |
| R4 | `Scene` is opaque with accessors (`nodes`, `size`, `frame`, `rules`, `a11y`); `Node` and `Prim` are public closed sums shipping the full vocabulary on day one (`Rect \| Line \| Path \| Symbol \| Label`). Adding a `Prim` variant is a semver-major event, stated in the README. | The container will grow fields; the vocabulary must not. |
| R5 | `Frame` is **transparent** and carries the trained `Scale`s. `scene.frame(s)` exposes it. | `custom` cannot convert data without the scales; the v0.2 Lustre Axis trigger needs `x_scale`. Scales are plain data, so printability is unharmed. |
| R6 | One `Key`, one wire attribute: **`data-lustre-key`**, on by default. `series` is a `String`. | Hydration works only because Lustre's `virtualise` reads that exact attribute; `data-k` silently kills SSR. Legend toggles and colour assignment key off a string series name. |
| R7 | One `internal/attrs.for_prim` shared by both emitters, emitting attributes in **alphabetical order**. Escaping lives only in the SVG emitter. | Alphabetical matches Lustre's serialiser, so order agrees by construction rather than by test. |
| R8 | Renderer agreement is asserted as `canonical(svg.to_string(s)) == canonical(element.to_string(static(s)))` where `canonical/1` does **exactly one** rewrite: expanding `<x …/>` to `<x …></x>`. Nothing else, ever. | `ecosystem` executed it and measured alphabetical sorting plus `<rect></rect>`; `lustre`'s "list order" claim is wrong. Byte equality is unreachable; a one-rule normalisation is auditable. **Experiment re-run and confirmed — see R13.** |
| R9 | dapper hand-rolls `escape_text`/`escape_attr`, with a conformance test against `houdini` as a **dev**-dependency. The apostrophe is `&#39;`, per R13 — *not* `&apos;`. | Keeps core at `gleam_stdlib` only while pinning the escaper to what Lustre uses. |
| R13 | **Measured against lustre 5.7.1, byte-identical on both targets** (`test/lustre_serialiser_test.gleam`, M0-2). Attributes are emitted **alphabetically**, not in list order — B4 resolved in `ecosystem`'s favour. Empty elements are **expanded**, never self-closed, confirming `canonical/1`'s single rule. Plus two findings no stream predicted: **`xmlns` appears on the outermost namespaced element only**, children inheriting it; and the **apostrophe escapes to the numeric entity `&#39;`**. | The xmlns rule matters because emitting it per-element would make the two renderers disagree on every scene with nested marks — which is every real scene. The apostrophe rule matters because `&apos;` is the natural fifth choice when implementing "the five XML entities", and it is wrong; the disagreement would first appear on a category name containing an apostrophe, long after the escaper was written. R10's "always `xmlns`" is hereby narrowed to "on the root element". |
| R14 | The oracle tests stay in core's suite permanently, with `lustre` as a dev dependency. They assert nothing about dapper. | They are the tripwire for risk 6, Lustre serialiser churn. `element.to_string` is not a stability contract, so the only defence is finding out on the release that changes it. |
| R10 | SVG rules fixed: always `xmlns` + `viewBox`; `width`/`height` by default (`Sizing(Fixed)`); `shape-rendering="crispEdges"` on grid/axis groups only, no half-pixel snapping; absolute path commands, space-separated; deterministic ids `{id}-clip-{n}`; `role="img"`, `<title>`, L1 `<desc>`, `aria-hidden` on decorative groups. | Decided rather than discovered. |
| R11 | **One id system.** `Options.id` (default `"dapper"`) serves clipPath prefixes, `<style>` scoping and `aria-labelledby`. Two charts on a page need distinct ids — a documented sharp edge, not something a pure function can solve. | Closes G5. |
| R12 | No `Backend` record of functions until a third real target exists. | `diagrams` is the cautionary tale. |

### Layout and metrics

| # | Decision | Why |
|---|---|---|
| L1 | `layout.solve(domains, size, theme, metrics, axis_opts) -> Frame`. It does **not** take `Chart`. | `layout` importing `chart` while `chart` calls `layout` is a Gleam module cycle. |
| L2 | Exactly two passes: seed insets → ticks → format → measure → reserve → re-range → re-tick → stop. Data is mapped **once**, after pass B. | The second pass is O(ticks), not O(n) — what makes the bound affordable where Vega's `autosize: "fit"` is a warning. |
| L3 | `Metrics` is opaque with `embedded()` and `custom(...)`; `embedded()` is the default on **both** targets. | One snapshot suite covers both targets only if the numbers are identical. |
| L4 | Bundle **Arimo** (sans) and **Cousine** (mono), SIL OFL 1.1. Emit `font-family="Arimo, Liberation Sans, Arial, Helvetica, sans-serif"` explicitly. | dapper never rasterises, so metric-compatibility with the font the viewer *has* beats fidelity to one they do not. Ugly-but-correct is the accepted default. |
| L5 | The advance table is generated Gleam source — one ~400-arm `case` per (family, weight) — produced by `scripts/gen_metrics.py`, with a `table_digest` constant asserted by a test. `.ttf`s live in `fonts/` at repo root, in git, outside the Hex tarball. | Measured: 1400 arms compile in 0.3 s on Erlang, 0.03 s on JS; zero allocation, zero deps. Determinism is the correctness strategy. |
| L6 | Error budget, declared: exact-in-our-model for numeric labels; ≤2 % for mixed-case Latin; ~10 % on clients with no Arial-metric font, manifesting as crowding, never reflow. Every reserved inset pads 4 % + 2 px. | The pad also absorbs the pass-B tick-widening residual — one mechanism, two problems. In the README, not a bug report. |
| L7 | Missing glyphs fall back by class; CJK/Hangul/Kana = 1.0 em; combining = 0; astral = 1.2 em; complex scripts are classified `Unshaped` and **diagnosed**. | Wrong-and-loud beats Vega #2940's wrong-and-silent. |
| L8 | `labelOverlap` verbatim from Vega: `Show \| Parity \| Greedy`, defaulting Parity on continuous axes, Greedy on band axes, 2 px gap, first and last never dropped. Rotation is `Horizontal \| Angled45 \| Vertical`, never automatic. | Auto-rotation trades width for height reservation — the fixpoint the two-pass bound refuses. |
| L9 | The pane grid is the top level from day one; v0.1 always builds 1×1; axis space is reserved **per grid edge** (`AxisPlacement` fixed to `OuterEdges`). | Polaris's lesson: near-zero now, a rewrite later. |
| L10 | `MarginPolicy = Auto \| AtLeast(Insets) \| Fixed(Insets)`, default `Auto`. `Fixed` makes geometry independent of the metrics table. | The escape for a user shipping their own webfont, and byte-stable SSR across a table regeneration. |
| L11 | **`dapper/metrics/canvas` is cut from v0.1.** | FFI in a core that declared zero FFI, JS-only, self-marked "shipping without it is fine". If it returns, it returns in `dapper_lustre`. |

### Theme, colour, accessibility

| # | Decision | Why |
|---|---|---|
| T1 | `Theme(style, context, mode)` is a **mandatory argument to `dapper.chart`**, resolved before layout. No merge, no global, no partial override. | Context (base font px) feeds the metrics → margin → re-range cycle; a theme applied at render would be a lie. |
| T2 | v0.1 ships `ColorMode = Fixed(Light) \| Fixed(Dark)`. **`Adaptive` (`@media prefers-color-scheme`) is v0.2.** The `Rule` list and per-mark `class` slot ship now. | Halves the theming snapshot matrix; the unretrofittable part still lands. |
| T3 | v0.1 ships `Categorical` schemes only. **`Sequential` and `Diverging` are cut**, along with `QuantizeScale` and Oklab interpolation. | v0.1 has no continuous colour channel — `fill` is `Discrete(row)`. Ramps for channels that do not exist are dead weight. |
| T4 | Default palette is Okabe–Ito reordered blue/orange/green/purple; `tol_bright()` second. Every published hex is verified against source before release. | Blue-vs-orange is the one hue axis fully preserved under protanopia and deuteranopia, and most charts have two or three series. |
| T5 | CVD safety is asserted by a **test**: Viénot/Brettel LMS simulation for three deficiency types plus WCAG contrast over every scheme × style × mode. It gates publishing the hex values. | The only thing converting "CVD-safe by default" from claim to property. ~120 lines of matrix maths. |
| T6 | **`scheme.explicit(by_label:)` is cut from v0.1.** | String-keyed lookup with a silent fallback re-admits the field-name error class decision 0001 deletes. If it returns, it returns with an `UnknownSeriesLabel` diagnostic. |
| T7 | Accessibility: L1 always (`role="img"`, `<title>`, `<desc>`, `aria-labelledby`), derived from mark type, channel labels, scale kinds and axis extents. **L2 statistics, the data table and `render_figure` are cut.** | L1 is unretrofittable and free; the rest is self-marked "unblocks nothing". `Scene.a11y` holds `#(title, desc)`, never the dataset (closes G11). |

### Process, packaging, validation

| # | Decision | Why |
|---|---|---|
| P1 | **Two packages.** `dapper` depends on `gleam_stdlib` only. `dapper_lustre` depends on both. Lockstep versioning, released together. | Lustre 5.7.1 pulls a seven-package manifest including an OTP supervision tree, and Gleam has no optional dependencies. |
| P2 | The fixture corpus is a **public module `dapper/gallery` in core `src/`** — chart constructors, no test dependency. Core's suite snapshots it; `dapper_lustre`'s suite imports it for the drift test. | Resolves B5 without duplicating the corpus or creating a cycle — and it *is* the docs gallery, so examples cannot rot. |
| P3 | **One validation surface.** `build_result(Chart, Options) -> #(Scene, List(Diagnostic))` is internal; `build` takes the first, `validate` takes the second. `layout.diagnose` does not exist. | Diagnostics needing trained domains or measured labels cannot come from a function that sees neither. One code path, no drift; calling both runs the pipeline twice, documented. Closes G2. |
| P4 | A **series** is `#(layer_index, Option(category))`. Its name is the fill/stroke category when a colour channel exists, else the layer's y-channel label. Order is layer order, then first-appearance order within the layer. Colour index is the position in the globally trained category list under `resolve.shared()`. | Keys, colours, legends and hydration all depend on it and no stream defined it. Closes G3. |
| P5 | `Dict` is never iterated to produce ordered output. Ordering always comes from an explicit `List`. CI greps for it. | Measured: `dict.keys` returns different orders per target. |
| P6 | Degenerate inputs have **specified** behaviour, not merely "no crash": empty data → `Numeric(0.0, 1.0)` domain, axes drawn, `EmptyDomain` diagnostic; single datum → `[v−0.5, v+0.5]`; `[5.0, 5.0]` → `[4.5, 5.5]` + `DegenerateDomain`; log convert on ≤0 → clamped to the smallest positive domain value + `LogDomainCrossesZero`; NaN/∞ skipped in training and rendered as `"0"` if they reach geometry. | These are the tests written first; G6 left nothing to write them against. |
| P7 | Verbatim ports carry attribution: a `NOTICE` with d3's ISC text and per-file provenance comments; `fonts/OFL.txt` alongside the vendored faces. | Apache-2.0 repo, ISC sources. Cheap in M0, awkward at release. |
| P8 | Publish `0.0.1` at the end of M0, `0.0.2` at the end of M3. `0.1.0` is the first version with a compatibility promise. Pre-1.0: minor may break, patch may not. No 1.0 until faceting has shipped. | Shakes out the release pipeline while nothing depends on it. |
| P9 | The README line "*from shared code*" is wrong and must be fixed: two independent folds over a shared `Scene`, held equal by a test. So must the v0.1 scope list (time scales out) and the "no headless browser" claim (resvg is a static rasteriser, exception written down). | Overclaims are what get quoted back. |

---

## Resolutions to the adversarial review

| # | Blocker | Resolution | Streams that change |
|---|---|---|---|
| B1 | `Chart(row)` in five streams, unparameterised in one | **Unparameterised wins** (C1, C3). Data on the mark, not the chart. | `layout`, `roadmap`, `theming`, `lustre`, `testing` rewrite every signature. `testing`'s `Fixture` thunk becomes a plain `List(Chart)`. |
| B2 | The existential argument is false | Conceded. The decision stands on printability/comparability, not expressibility (C2). | `core-api` rewrites D1's justification. |
| B3 | `var()` in presentation attributes | `theming` is right. The `Scene` holds only literal colours; lateness is a `Rule` list + scoped `<style>` (R3). | `scene` deletes `Colour.CssVar` and `Paint`; `theming` deletes `AdaptivePaint`. |
| B4 | Byte equality vs measured alphabetical sorting | `ecosystem` wins — it executed the code. Alphabetical attribute emission by construction, plus a one-rule `canonical/1` for self-closing tags (R7, R8). Re-run the experiment first. | `lustre` L3, `scene` task 8, `testing` D4. |
| B5 | The drift test cannot see both emitters | `dapper/gallery` is public in core; `dapper_lustre`'s suite imports it (P2). | `testing` task 10 and `ecosystem`'s differential test move to `dapper_lustre`. |
| B6 | µs vs seconds | Moot — time is cut to v0.2 (S7). When it returns it is **seconds**. | `core-api` D2. |
| B7 | `bar` requires a `BandScale` in a deleted signature | The channel type carries the arity claim; the band scale is derived (S3). `dapper/scale` keeps the split types for standalone use. | `scales` D3/D4 rewrite their justification. |
| B8 | Four `build`/`layout` signatures | `chart(layers, resolve:, theme:, size:)` mandatory; `metrics`/`id`/`decimals`/`sizing` in an opaque `Options`; six entry points, not sixteen. `layout` takes domains, not `Chart` (L1). | All four. |
| B9 | `Scene` opaque/transparent/third-shape | `Scene` opaque with accessors; `Node`/`Prim`/`Frame` transparent; `Frame` carries the scales (R4, R5). | `core-api` D4, `layout`'s opaque `Frame`, `theming`'s record. |
| B10 | Three `Key`s, three wire attributes | One opaque `Key`, `series: String`, `data-lustre-key` (R6). | `scene` D5, `lustre` L7's decoder. |
| B11 | Five formatters | One `dapper/format`, public, in core; geometry bans exponents, tick labels get `si`/`scientific` by digit assembly with a 2^53 guard (S8). | `scene`, `ecosystem`, `scales`, `testing`, `layout` all point at it. `testing`'s conformance table is rewritten per-function. |
| B12 | Extended-Wilkinson deferred and scheduled | **Cut** (S5). `ticks` never imports `metrics`. | `ecosystem` task 8, `roadmap` task 5. |
| B13 | `layout` is a module cycle | `layout.solve(domains, size, theme, metrics, axis_opts)` (L1); the import DAG test enforces it. | `layout`, `roadmap`'s DAG. |
| G1 | Nobody owns axis/grid/legend emission | New owned component `dapper/internal/chrome`, an M–L task on the critical path. Legends **ship**, because `fill` ships. | new. |
| G2 | `validate` cannot see trained domains | `build_result` returns both (P3). | `core-api`, `layout`, `theming`. |
| G3 | "Series" undefined | Defined (P4). | all. |
| G7 | Minimum mark extent | `Requirements.min_extent`, applied in `draw` (C9). | `mark`. |
| G8–G11 | Licensing, font choice, deps, a11y table | P7, L4, P1 (core = stdlib only, since time and houdini are out), T7. | `roadmap`'s DoD now true as written. |

---

## The critical path

Nothing renders until every one of these lands, in this order:

**`format` → `geom` → `ticks` → `scale` + `domain` → `metrics` (generator, table, `measure`) → `Scene`/`Key`/`attrs`/`svg` → `channel`/erasure → `layout.solve` → `chrome` (axes + grid) → `mark.bar` → `chart`/`build` → dual-target snapshot harness.**

Thirteen items and it delivers exactly one bar chart. Line, point, colour, legends, theme, a11y, Lustre and `validate` are all *after* it.

**Where the real risk sits**, in order:

1. **The metrics generator (M1).** The only task needing non-Gleam tooling, the only one whose output is 30 KB of generated source, and the one whose central assumption — Arimo advances equal Arial advances — is unverified. It gates layout, which gates everything visual.
2. **`chrome` (M3).** Unowned by every stream, on the critical path, and it is where "the chart looks right" actually lives. Budget it as an L.
3. **The two-pass layout cycle (M3).** Correct in principle, fiddly in practice, and the place where a third pass will be tempting. It must not be taken.
4. **`canonical/1` drift (M5).** If Lustre changes its serialiser, the test fails on a patch release. Pinned range, and `canonical/1` never grows a third rule.

---

## Work breakdown

Sizes: **S ≈ 4 h, M ≈ 10 h, L ≈ 20 h**, solo, evenings. Total ≈ **375 h ≈ 10 months at 9 h/week**. That is the honest number after the cuts; the pre-cut figure was ~700 h.

### M0 — Foundations (~55 h) · publish `0.0.1`
- **S** Re-run `ecosystem`'s Lustre serialiser experiment; record the answer in this document.
- **S** Repo hygiene: dual-target CI matrix, `gleam format --check`, `float.to_string`/`string.inspect`/`Dict`-ordering greps, `NOTICE`, dev-deps (`gleeunit`, `birdie`, `qcheck`, `simplifile`, `houdini`, `lustre` as oracles).
- **M** `dapper/format` — `coord`, `fixed`, `si`, `scientific`, `tick_format`, `label`, the safe-log10 helper, the 2^53 guard, and the per-function conformance table run on both targets.
- **S** `dapper/geom` — `Size`, `Rect(x0,y0,x1,y1)`, `Insets`.
- **S** d3 fixture harness: a one-off Node script emitting expected `ticks`/`tickIncrement`/`nice`/band values to checked-in JSON.
- **M** `dapper/ticks` — 1–2–5, `tick_increment` with the negative-return trick, `nice_bounds`, log ticks.
- **M** `dapper/scale` — `Scale` (Linear, Log), `BandScale`, `OrdinalScale`, `point`; `dapper/scale/domain` monoid and training.
- **S** Property suite: round-trip, monotonicity, endpoint exactness, tick containment, band partitioning without overlap.

*Done when:* every d3 fixture matches on both targets; `gleam docs build` is warning-free; `0.0.1` is on Hex.

### M1 — Metrics (~45 h)
- **M** `scripts/gen_metrics.py` (fonttools over `hmtx`/`cmap`), Arimo + Cousine vendored under `fonts/` with SHA-256 pins, `tables.gleam` + `table_digest`, and an assertion that Arimo advances match Liberation Sans on every covered codepoint.
- **S** `dapper/metrics` — opaque type, `embedded`, `custom`, `measure`, class fallbacks, `coverage`.
- **S** Cross-target parity test over a fixed corpus, byte-identical under both targets. In CI from here on.

*Done when:* a hand-edit to `tables.gleam` fails CI; `measure` agrees to the last digit on both targets.

### M2 — Scene and emitter (~55 h)
- **S** `dapper/scene/key` — opaque `Key`, `to_string`, `parse`, round trip.
- **M** `dapper/scene` — `Node`, `Prim`, `Seg`, `Style`, `Paint`, `Rule`, `A11y`; opaque `Scene` with builder and accessors; `to_debug_string` (3 dp) and `is_finite`.
- **M** `internal/attrs` — `tag_of` + `for_prim`, alphabetical order, default omission, dash arrays, path data, symbol geometry.
- **M** `dapper/svg.to_string` — StringTree assembly, root element, `viewBox`/`Sizing`, clip defs, crispEdges groups, `role`/`title`/`desc`, `data-lustre-key`, `<style>` from `rules`.
- **S** Escaping + a hostile-string fixture (`"/><script>`, `&amp;`, RTL, emoji, newline) as both datum label and title, conformance-tested against houdini.
- **S** `Options` builders and defaults.
- **M** Snapshot harness: birdie over the `Scene`, plain `.svg` goldens under `test/golden/svg/` via a ~30-line simplifile helper, ~12 hand-built scenes, both targets. Plus the pinned-`resvg` renderability smoke job.

*Done when:* twelve hand-built scenes are byte-identical on both targets and rasterise non-blank under resvg.

### M3 — Walking skeleton · **the first shippable slice** (~70 h) · tag `0.0.2`
- **S** `dapper/channel` — opaque `Continuous`/`Discrete` with mandatory labels; erasure to `Columns`/`Role`.
- **S** Training: domain union per role across layers, category ordering, `Resolve`.
- **M** `dapper/frame` + `layout.solve` — pane grid (1×1), `AxisSpace` per edge, margin policies, the two-pass cycle.
- **S** Overlap resolution (parity, greedy) and the three rotation angles with their anchor/baseline table and overhang folding. *(Sized M in practice; do not believe the S in `layout`'s plan.)*
- **L** `dapper/internal/chrome` — axis rule, tick marks, tick labels, gridlines, axis titles.
- **M** `dapper/mark` — opaque `MarkKind`, `bar`, `requirements`, `draw`, `min_extent`.
- **M** `dapper` — opaque `Chart`, `chart/4`, setters, `build_result`, `build`, `render`, `validate`, all six entry points.
- **S** The degenerate-input table from P6, as named unit tests with exact expectations.
- **S** Import-DAG test.

*Done when:* a bar chart built from a real `List(Sale)` with accessor channels renders identically on Erlang and JavaScript, `validate` returns `[]` on good input and exactly the specified diagnostics on each degenerate case, and no `panic`/`let assert`/partial function exists in `src/`. **This is the slice that proves the wedge. If the project stops here it has still demonstrated something nobody else has.**

### M4 — Grammar completion (~65 h)
- **M** `mark.line`, `mark.point`, `dapper/shape` path emission.
- **M** `dapper/color` (`Color`, `Duo`, hex, luminance, contrast) + the Okabe–Ito / Tol palette module.
- **M** Test-only CVD simulation + WCAG contrast over every scheme × style × mode; verify every hex against source.
- **M** `dapper/scheme` (`Categorical` only) and the colour channel; series assignment per P4.
- **M** `dapper/theme` — `Style`, `Context`, `Theme`, `Fixed(Light|Dark)`; resolution into the record layout consumes.
- **M** Legend emission (single right-hand column) inside `chrome`.
- **S** A11y L1 `describe` + `title`/`desc`/`role`/`aria-labelledby`/`aria-hidden`.
- **S** `custom(fn(Frame) -> List(Node))`.
- **M** `dapper/gallery` — ~8 charts, each a snapshot test writing `docs/gallery/*.svg`.

*Done when:* eight gallery charts render on both targets and the CVD suite is green.

### M5 — Second target (~50 h)
- **S** Scaffold `dapper_lustre` (repo, `gleam.toml`, dual-target CI, tight Lustre range).
- **M** `dapper_lustre.static : Scene -> Element(msg)`, a keyed mirror using `element/keyed.namespaced`.
- **M** The drift test over `dapper/gallery`, both targets, via `canonical/1`.
- **M** Hydration example: mist renders SVG + row JSON, client rebuilds the `Chart`, `lustre.start`s onto it, and asserts an empty first patch. *(This is the README demo. It is M, not S.)*

*Done when:* the drift test is green on both targets and the hydration demo produces an empty first patch.

### M6 — Ship (~40 h)
- **M** `docs/guide.md`: one narrative from `chart` to `render`, plus a scales-only section.
- **S** README rewrite (two targets, honest scope, the L6 error budget, the resvg exception, the `Prim`-is-public-API note).
- **S** `docs/benchmarks.md` reference table + the O(n) scaling test.
- **S** CONTRIBUTING: how to review a golden diff.
- **S** CHANGELOG `0.1.0`, release checklist, tag, `gleam publish` both packages.

---

## Reserved slots

Cheap now, breaking later. All of these ship in v0.1 as inert.

- **Pipeline stages.** `stat` and `move` threaded through `build` as identities, split by space (`Stack` before training, `Dodge`/`Jitter` at map). Inserting a stage later silently changes every chart.
- **Opaque slot types with one eliminator each:** `Stat`, `Move`, `Title`, `Legend`, `Tooltip`, `Annotation`, `LabelOverlap`, `ScaleResolve`. A user's `case` over a public sum breaks the day you add a variant; `stat.identity()` + `stat.apply()` does not.
- **`Key.facet: Int`** — always 0, emitted anyway.
- **Pane grid 1×1** with `AxisPlacement.OuterEdges`, axis space reserved per edge.
- **`Scene.rules: List(Rule)` and `Mark.class: String`** — empty in v0.1, the only route to `Adaptive` colour later.
- **`ContinuousKind.Time(Zone)`** reserved inside an opaque type, so v0.2's time scales are non-breaking.
- **`Requirements.min_extent` and `.legend`** — the fields that stop `requirements`/`draw` becoming elm-charts' six functions.
- **`Metrics`, `Options`, `Theme`, `Resolve` opaque** — every future knob is a setter, not a field.
- **`Continuous`/`Discrete` mandatory `label`** — a11y, legends and axis titles all need it and there is no second chance to collect it.

---

## Post-v0.1 candidates

Not scheduled, not committed to — recorded so they are not rediscovered from scratch.

**A LaTeX theme (Latin Modern / Computer Modern).** Likely the strongest single
differentiator available to dapper after the wedge itself, because the earliest plausible
audience is server-rendered reports and paper figures, and that audience already knows what
it wants figures to look like.

It cannot be done the way Arimo is done. Arimo works because it is metrically identical to
Arial, which the viewer already has; Latin Modern has no installed twin, so measuring with
LM metrics and falling back to Times mismeasures every label by far more than L6's error
budget. The only correct route is embedding the face as a base64 `@font-face`, which
*inverts* the argument — you are then measuring the font you are guaranteed to ship, so
measurements become exact rather than approximate.

Both seams already exist and neither needs changing now:

- `Metrics` is opaque with `metrics.custom(...)` (L3) and carries the advance table *and*
  the font stack as one unit — the correct coupling, since a font stack themed independently
  of its table silently invalidates every measurement.
- `Scene.rules` and the `#id`-scoped `<style>` inside `<defs>` (R3) are where an
  `@font-face` belongs.

So this is a second `Metrics` value plus a `Rule`, not a redesign. The real cost is bytes: a
full Latin Modern TTF is several hundred KB, acceptable for a single report and not for a
dashboard of twelve charts, so anything practical wants glyph subsetting — font surgery, a
genuine project, and firmly after the wedge is proven. matplotlib is the precedent for the
sequencing: bundle the boring face, make the beloved one opt-in.

Until then, `MarginPolicy.Fixed` (L10) already lets a user render in any font they like by
specifying margins by hand.

## Risks, ranked

1. **The schedule.** 375 h is ~10 months solo. *Mitigation:* M3 is a genuine shippable slice; M5 can slip to 0.2.0 at the cost of the headline claim's *proof* for one release, not the claim.
2. **The metrics table's central assumption.** Arimo ≈ Arial is unverified glyph-by-glyph. *Mitigation:* M1 asserts it against Liberation Sans and fails the build on any disagreement. If it fails, the fallback is the per-class table alone and a wider error budget.
3. **Cross-target transcendental drift.** `log10` differing by one ulp flips a tick step and produces an unreproducible snapshot failure months later. *Mitigation:* S6's shared truncate-then-verify helper, written in M0, not discovered in M4.
4. **`chrome` is unscoped.** No stream owned axis and legend emission; it is on the critical path and it is where visual quality lives. *Mitigation:* budgeted as an L in M3 and given its own module and snapshot set.
5. **Snapshot-review fatigue.** Any default change rewrites the corpus and a solo maintainer rubber-stamps it. *Mitigation:* defaults live in one module; fixtures not *about* a default pass it explicitly; CONTRIBUTING requires naming the cause of any mass rewrite in the commit message.
6. **Lustre serialiser churn.** `element.to_string` is not a stability contract. *Mitigation:* tight version range in `dapper_lustre` only; `canonical/1` frozen at one rule.
7. **Erasure is one-way.** Tooltips carrying arbitrary user content, typed stat→mark contracts and hit-test-to-row must all route through `(series, index)` and the caller's own list. *Accepted cost*, mitigated by emitting stable keys from day one.
8. **Transparent `Node`/`Prim`.** Every new primitive is a breaking change. *Accepted:* the vocabulary ships complete and the README says adding to it is semver-major.
9. **Clients with no Arial-metric font** see ~10 % advance error — crowded or airy labels, never reflow. *Accepted and declared* in the README, per L6.
10. **The stage-3/stage-6 `Move` split is asserted but untested** until stacking lands. *Accepted:* it is the one ordering decision expensive to revise, and reserving it costs nothing.
11. **Two packages means version skew.** *Mitigation:* lockstep releases, no exceptions.
12. **Two decimals of geometry** is a bet that nobody needs sub-pixel output; changing it later rewrites every downstream snapshot. *Accepted.*

---

## Open questions needing a human call

1. **Cut time scales to v0.2?** *Recommendation: yes* (S7). It is the single decision that turns a 700 h plan into a 375 h one. Cost of deferring the decision: `scales` cannot start task 9 and the budget stays fictional. Cost of the cut itself: one README line, and users with time axes pass epoch seconds through `channel.continuous` and get numeric labels until v0.2.
2. **Two packages, or one?** *Recommendation: two* (P1). `ecosystem`, `lustre` and `roadmap` agree; `core-api` and `scene` prefer one for release simplicity. Deferring this blocks M5's scaffold and the drift test's location. Merging later is easy; splitting later is breaking for everyone.
3. **Is ~375 h / ~10 months acceptable with no committed users?** If not, the honest cut is M5: ship server-side SVG only at 0.1.0 (~325 h) and make the dual-target claim at 0.2.0. Deferring this means discovering it in month eight.
4. **Arimo, or a modern face?** *Recommendation: Arimo* (L4) — correct measurement beats a pretty default, and any user who swaps in Inter invalidates every measurement anyway. Cost of deferring: M1 cannot start, and M1 gates everything visual. This is effectively permanent once shipped.
5. **Is a pinned `resvg` binary in CI compatible with "no headless browser"?** *Recommendation: yes* — static rasteriser, no JS engine, no DOM, never in the shipped library — but write the exception into the README rather than leaving it as CI folklore.
6. **Is the `dillydale` org created and `dapper` reserved on Hex?** External blocker on P8's `0.0.1` publish at the end of M0. Nothing else depends on it, but it is embarrassing to discover at tag time.
