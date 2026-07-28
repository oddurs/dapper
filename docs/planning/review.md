# Adversarial review

Nine planning documents, planned independently against one prior-art synthesis and one accepted
decision. They agree on philosophy and disagree on almost every type signature that has to be
written first. This review names the disagreements, not the agreements.

Convention: streams are named by their file — `core-api`, `scales`, `layout`, `scene`, `testing`,
`theming`, `lustre`, `ecosystem`, `roadmap`.

---

## Blocking contradictions

### B1. `Chart` has a `row` parameter in five streams and not in `core-api`

`core-api` D1: *"`Chart`, `Layer` and `Scene` are unparameterised"* — erasure moves into the mark
constructor.

Everyone else wrote code against the opposite:

- `layout`: `pub fn layout(chart: Chart(row), metrics: Metrics) -> Frame`, `pub fn diagnose(chart: Chart(row), metrics: Metrics)`
- `roadmap`: `pub opaque type Chart(row) { Chart(data: List(row), layers: List(Layer(row)), …) }`
- `theming`: `pub fn build(chart: Chart(row, msg), theme, metrics, size) -> Scene`
- `lustre` L6: *"`Chart(row)` stays free of `msg`"*
- `testing`: *"a heterogeneous `List(Chart(row))` is not expressible"* — the entire justification for
  the `Fixture` thunk shape

This is not cosmetic. `roadmap`'s shape puts `data: List(row)` **on the `Chart`**, so every layer
shares one row type (ggplot2's model) and the constructor is `chart.new(data, metrics) |> chart.layer(mark)`.
`core-api`'s shape puts data **on each mark** (`mark.bar(data:, x:, y:, …) -> Layer`) and the
constructor is `dapper.chart(layers, resolve:)`. These are different libraries. `core-api` itself
says the choice is *"unfixable after v0.1"*. Nothing can be written until it is made.

### B2. `core-api`'s existential argument — the premise is false, and its own siblings prove it

`core-api` D1: *"holding `List(Layer(?))` for differing `?` requires existential types, which Gleam
does not have. The only way to encode an existential here is to apply the eliminator eagerly — that
is, to erase."*

The second sentence is wrong. Gleam encodes existentials the ordinary way — by closing over the
witness. `testing` does exactly this, in this very sprint:

```gleam
pub type Fixture { Fixture(name: String, scene: fn() -> Scene, svg: fn() -> String) }
```

`layout` does it too: `metrics.custom(advance: fn(String, Font) -> Float, …)`. A `Layer` holding
`erase: fn() -> Columns` is a heterogeneous list of layers with differing `row`, is total, and
defers erasure to `build` — i.e. prior-art open question 7 *as literally worded*. So the decision
that `core-api` calls unfixable was made against a constraint that does not exist.

That does not automatically make erase-at-build right (a closure in `Layer` also breaks `echo` and
structural equality — the exact objection `core-api` D6 and `scales` D2 raise against closures in
scale records, and which `layout` violates anyway with `Metrics.custom`). But the trade must be
argued on that ground, not on "Gleam cannot express it."

### B3. CSS variables in presentation attributes: two streams, opposite browser facts

`scene` D4: *"A `CssVar` always emits with its literal fallback — `fill="var(--chart-1, #4e79a7)"`"*,
called *"the best-aged idea in the React lineage"* and made the basis of the whole colour wire format.

`theming` D8: *"`fill="var(--x)"` as a presentation attribute does **not** resolve — `var()` is only
substituted inside CSS declarations."*

`theming` is correct. `scene`'s emission rule produces charts that are silently uncoloured wherever
a `CssVar` is used. This invalidates `scene` D4, `scene`'s `Colour { Literal | CssVar }` type, and
`scene`'s claim that the escape surface is one function wide — because `theming`'s correct fix
requires a `<style>` block in `<defs>`, an `id`-scoped selector namespace, generated class names,
and a `Rule` list on the `Scene`. None of that exists in `scene`'s ADT, and `scene` explicitly bans
`Raw(String)`.

Downstream: `theming`'s `Paint { NoPaint | FixedPaint(Color) | AdaptivePaint(role, light, dark) }`
and `scene`'s `Paint { NoPaint | Solid(Colour) }` are both declared **public and frozen**. They are
incompatible. One must be deleted before either is written.

### B4. Byte-equality of the two renderers is asserted by three streams and measured false by a fourth

`testing` D4, `scene` task 8, `lustre` task 5 all assert
`element.to_string(to_element(s)) == svg.to_string(s)` byte-for-byte, and `lustre` L3 justifies it:
*"Lustre emits attributes in list order."*

`ecosystem` D2, from the tarball: *"Lustre sorts attributes alphabetically… it emits `<rect …></rect>`
rather than `<rect/>`"* — and therefore prescribes `canonical(...)` on both sides.

Two streams claim to have read Lustre 5.7.1 source and reached opposite conclusions. Byte equality
and alphabetical attribute sorting cannot both hold. `lustre` open question 2 (*"byte equality or
normalised equality? Decide before task 4 fixes attribute order"*) is the right question; it must be
answered by rerunning `ecosystem`'s experiment, not by picking a document.

Compounding it: `scene` D6 puts escaping **only** in the SVG emitter and relies on Lustre's
`attribute.attribute` to escape identically. Lustre escapes via `houdini`. `scene` task 6 hand-rolls
`escape_text`/`escape_attr`. Byte equality then depends on dapper's hand-rolled escaper matching
houdini's character set exactly, forever. `ecosystem` puts `houdini` in dapper core's dependencies —
presumably for this reason — but no stream says "use houdini, do not hand-roll," and `roadmap`'s
definition of done says *"`dapper` depends on `gleam_stdlib` only,"* which forbids it.

### B5. The drift test cannot live where two streams put it

`lustre` L2 / `ecosystem` D1 / `roadmap` D5: two packages, `dapper_lustre` depends on `dapper`.

`testing` task 10 and `ecosystem`'s own `test/differential_test.gleam` put the agreement test in
**core's** suite, calling `scene.to_lustre(...)` / `dapper_lustre.view(scene)`. Core cannot import
`dapper_lustre` — that is a dependency cycle. Either the test moves to `dapper_lustre`'s suite
(where `testing`'s fixture corpus is not), or the corpus is duplicated, or core rebuilds the Lustre
tree itself — which is the drift it exists to prevent.

Meanwhile `core-api` open question 2 recommends **in-package** `dapper/lustre` and `scene` open
question 1 recommends **one package**. Four streams, three positions, and the packaging choice
determines where the anti-drift mechanism can physically exist.

### B6. Time is in microseconds in one stream and seconds in another

`core-api` D2: *"`channel.time(fn(row) -> Timestamp)`, which erases to a Float (microseconds since
epoch — under 2^53, so exact)"*.

`scales` D12: *"The scale's `Float` domain is *seconds* since the Unix epoch (**not** milliseconds —
seconds keeps the whole plausible range inside 40 bits of a 53-bit mantissa)."*

A channel erased in µs feeding a scale that generates ticks by converting its Float domain back to
`Timestamp` in seconds produces ticks off by 10⁶ — and, because both paths are internally
consistent, it will look like a scale bug for a week. `scales`'s reasoning is the load-bearing one
(the tick ladder walks `Timestamp` space); `core-api` should adopt seconds.

### B7. `bar` requires a `BandScale` — in a signature that `core-api` deletes

`scales` D3: *"`bar` requires a `BandScale` on its categorical axis; that one signature converts
Observable Plot's commonest runtime error into a compile error"* — and `scales`'s dependency section
states it as a hard requirement: *"`bar` must take `BandScale` in its signature."*

`core-api` D3: *"the user configures (`x_domain`, `x_transform`, `x_label`) but never names a scale
kind. The trained scale is an **output** of `build`, not an input."* And `core-api`'s `mark.bar`
takes `x: Discrete(row)` — no scale anywhere.

Both streams claim to be implementing prior-art "what to steal" #4. `core-api`'s version is the
better error, but as written `scales`'s central justification for the `ContinuousScale`/`BandScale`
split, and the demo the README leans on, do not exist. Decide which signature ships; `scales` D3 and
D4 need rewriting either way.

### B8. Four incompatible `build`/`render`/`layout` signatures

| Stream | Signature |
|---|---|
| `core-api` | `build(Chart) -> Scene`; theme/metrics/size are setters on `Chart` |
| `theming` | `build(chart: Chart(row, msg), theme: Theme, metrics: Metrics, size: Size) -> Scene` — *"a mandatory argument… no optional fields, no deep merge"* |
| `roadmap` | `build(Chart(row)) -> Scene`; metrics injected at `chart.new(data, metrics)` |
| `layout` | `layout(chart, metrics) -> Frame`; *"`Chart` carries its own `Size`"*; two entry points `render` / `render_with_metrics` |
| `lustre` L9 | `layout(chart, metrics, Size)` — *"must take `Size` as an explicit input so resize can be a message rather than a measurement"* |

`layout` and `lustre` disagree directly about whether `Size` is a `Chart` field or a `layout`
argument, and `lustre`'s entire responsive story (L9, task 10) depends on its version. `theming`
says `Theme` must be a mandatory `build` argument *because* a setter would be the silent-override
the decision refuses; `core-api` ships `dapper.theme(Chart, Theme) -> Chart` as a setter with an
implied default. Both cannot be right about the same value.

Also unresolved by anyone: where `Options` (`id_prefix`, `decimals`, `Sizing`, `keys`) and the chart
`id` enter, given the headline `render : Chart -> String` takes neither.

### B9. `Scene`: opaque, transparent, and a third shape with different fields

- `core-api` D4: *"`Scene`/`Node`/`Frame` are **transparent**"* — with the variant set bounded to
  `Rect | Path | Text | Group`.
- `scene` D3: *"`Scene` itself is **opaque** with a builder, because it *will* grow fields (defs,
  a11y table, facet metadata)"* — with `Node = Group | Mark` and `Prim = Rect | Line | Path | Symbol | Label`.
- `theming`: `pub type Scene { Scene(id, width, height, rules: List(Rule), nodes, a11y: A11y) }` — a
  **transparent record**, with exactly the three fields `scene` said opacity existed to protect.
- `lustre` L7 requires `frame(scene) -> Frame`, `x_scale(scene) -> Scale`, `anchor(scene, key)`,
  `series(scene)` on `Scene`, and calls it *"a concrete requirement for the scene stream, not an
  afterthought."* None appear in `scene`'s or `theming`'s `Scene`. And a `Scale` inside `Scene`
  contradicts `scene` D1's *"shallow tree of absolutely-positioned primitives"* — it makes the
  snapshot subject carry the scale, which changes every golden.

`Frame` has the same problem: transparent in `core-api` D4, `pub opaque type Frame` in `layout`.
`core-api`'s stated reason for transparency — *"a seam you cannot pattern-match on is not a seam;
the `custom` escape hatch must destructure it"* — is defeated by `layout`'s opacity.

### B10. `Key`: three definitions, three wire formats, and hydration depends on the difference

| Stream | Type | Wire |
|---|---|---|
| `scene` D5 | `pub opaque type Key { Datum(facet: Int, series: **Int**, index: Int) \| Chrome(Role, Int) }` | `data-k`, `"f0s1d17"` |
| `lustre` | `pub type Key { Key(facet: Int, series: **String**, datum: Int) }` — not opaque, no `Chrome`, has `parse` | `data-lustre-key`, `"0:revenue:12"` |
| `core-api` | `(facet, series, datum_index)`, type unspecified | — |

`lustre` L4 says hydration works *because* Lustre's `virtualise` reads `data-lustre-key`. If the
string emitter emits `data-k` (as `scene` D5 specifies), hydration silently re-patches the entire
chart and the SSR story is dead with no error. Worse, `lustre` contradicts itself: L4 says emit
`data-lustre-key`, L7's decoder reads `["target","dataset","dapperKey"]` (i.e. `data-dapper-key`),
and its own risk list says *"`data-dapper-key` decodes as `dataset.dapperKey`."* Pick one attribute
name; if hydration is wanted it must be `data-lustre-key`.

The `series: Int` vs `series: String` split is not cosmetic either — `lustre`'s
`LegendToggled(series: String)`, `hidden(state) -> Set(String)` and `theming`'s
`explicit(by_label: Dict(String, Duo))` all key off a *string* series name that `scene`'s `Key`
cannot carry.

### B11. Five names for the float formatter, with incompatible specs

| Stream | Module | Spec |
|---|---|---|
| `scene` D8 | `dapper/format` (public) | `num(x, decimals)`, `coord = num(x,2)` clamped ±1e9, **never exponent notation**, non-finite → `"0"` |
| `ecosystem` D5 | `dapper/num` | `coord` at **3 dp**, plus `scientific(x, dp)` — *"digits assembled, never via Int scaling"* |
| `scales` D13 | `dapper/format` | `NumberFormat { Fixed \| Significant \| SiPrefix \| Grouped \| Percent }`, `tick_format`, `Locale`, `time_label` |
| `testing` task 2 | `dapper/internal/**fmt**` (private) | `fmt.round_to(3)` |
| `layout` task 1 | inside `dapper/geom` | *"2 dp, never exponent notation"* |

And `testing`'s conformance table, which it calls *"the tripwire that must fire before any snapshot
does"*, is unsatisfiable under `scene` D8:

```gleam
#(1.0e21, "1e21"),      // scene D8: "never emit exponent notation"
#(1.5e-7, "0.00000015") // scene D8 at 2 decimals: "0"
```

Separately, `scene` D8's algorithm is the scaled-integer approach that `ecosystem` **measured**
breaking on JS past 2^53 (`fixed(1.0e21, 3)` → `1e+21.784`). `coord` is safe because it is clamped
to ±1e9. **Tick labels are not coordinates and are not clamped** — a revenue axis at 4.2e9, or any
axis in a domain where `SiPrefix`/`Significant` would be used, routes straight into the unguarded
path. `ecosystem`'s own note applies: *"snapshots pass on BEAM and corrupt on JS."* Also
irreconcilable: `scales` needs `SiPrefix`/`Significant` for large domains, `scene` bans exponent
output entirely, so a 4.2e9 axis gets `"4200000000"` labels.

This module is task #1 in four separate plans. It cannot be task #1 anywhere until it has one name,
one precision, one visibility, and one agreed behaviour above 2^53.

### B12. Extended-Wilkinson is deferred by the stream that owns it and scheduled by two that do not

`scales` D9: ship 1–2–5; ship extended-Wilkinson *without* the legibility term as opt-in; **defer
the legibility term to v0.2**, explicitly to avoid a `Metrics` dependency and a ticks↔layout cycle.

`ecosystem` task 8: *"`dapper/ticks` — D3's 1–2–5 first, extended-Wilkinson second, **consuming
`Metrics` for the legibility term**"* (M).
`roadmap` task 5: *"1–2–5 floor then extended-Wilkinson scoring **over `Metrics`**"* (M).

`layout` states the constraint that makes this dangerous — *"layout calls ticks, ticks calls
measure, never the reverse"* — and then its own dependency section concedes *"the two streams are
mutually dependent."* That is the fixpoint prior art forbids, entered by accident. Cut the
legibility term from v0.1 in all three plans, or accept a ticks→metrics edge and re-derive the
two-pass bound.

### B13. `layout` as specified is a Gleam module cycle

`layout`: `pub fn layout(chart: Chart(row), metrics: Metrics) -> Frame` and
`pub fn diagnose(chart: Chart(row), metrics: Metrics)`.
`roadmap`: `pub fn build(Chart(row)) -> Scene` lives in `dapper/chart`.

`dapper/layout` must import `dapper/chart` for the type; `dapper/chart` must import `dapper/layout`
to run stage 5. Gleam has no mutual module recursion. It is resolvable — move `build` up to the
`dapper` batteries module, or have `layout` take `(Domains, Size, Theme, Metrics)` rather than
`Chart` — but as written it does not compile, and `roadmap`'s import-DAG test (task 7) would be the
thing that discovers it. Note also that `layout` and `Frame` appear **nowhere** in `roadmap`'s
module DAG.

---

## Decision-0001 violations

1. **`theming`: `build(chart: Chart(row, msg), …)`.** A `msg` parameter on `Chart` directly negates
   the primary claim (*"the same `Chart` value renders as an interactive Lustre component"*) and is
   the exact shape `lustre` L6 rejects: *"If `msg` is in `Chart`, then 'the same `Chart` value
   renders both ways' becomes false."* Probably a slip, but it is in the plan.

2. **`roadmap`: `pub fn layer(Chart(row), Mark(row)) -> Chart(row)   // stat/move/resolve defaulted`.**
   Prior art #7 and decision 0001 item 5 make `Resolve` mandatory precisely because *"Vega-Lite's
   worst trap is **silent** unioning"*. `core-api` D7 gets this right (`chart(layers, resolve:)`
   mandatory). `roadmap` silently defaults it — and additionally places `resolve` per-layer, where
   prior art #13 puts it per-channel and `core-api` puts it per-chart. Three placements, one of
   which re-admits the trap.

3. **`theming`: `explicit(by_label: Dict(String, Duo), fallback: Categorical) -> Categorical`.**
   This is string-keyed lookup with a silent fallback — the field-name error class that decision
   0001's win #1 (*"accessor functions instead of field names"*) exists to delete, re-entering
   through the colour door. A typo'd label produces a plausible-looking chart in the wrong colours
   with no diagnostic. `theming`'s own open question 3 half-admits it: *"the risk is that it becomes
   the default idiom."* At minimum it needs an `UnknownSeriesLabel` diagnostic. It also collides
   with `ecosystem` D6 (`Dict` iteration order differs by target); nothing forbids iterating it.

4. **`layout`: `metrics.custom(advance: fn(String, Font) -> Float, vertical: fn(Font) -> #(Float, Float))`.**
   A record of closures, injected by the user, stored in `Metrics`, which `roadmap` stores in
   `Chart`. This is dictionary-passing — the pattern `core-api` D6 and `scales` D2 reject for
   scales, on reasons that transfer verbatim: *"closures in records cannot be compared or printed,
   which breaks `echo` and snapshot debugging."* With `Metrics` inside `Chart`, no `Chart` is
   printable or comparable. Nobody noticed that the two streams applied opposite rules to the same
   problem in the same sprint.

5. **`ecosystem` D11 vs `layout` task 11.** *"dapper core ships zero FFI, and that is a hard rule,
   not an aspiration"* — against `dapper/metrics/canvas`, a JavaScript-only FFI module inside core
   (`layout` task 11, `layout`'s shapes section). Opt-in or not, it is FFI in core, and it is
   `@target(javascript)`-only, which `ecosystem` reserves for *"declarations that cannot exist on
   the other side."* Either the hard rule loses, or canvas metrics move to `dapper_lustre`.

6. **Three validation surfaces where 0001 specifies one.** Decision 0001 and prior art #12 promise a
   single total `validate(Chart) -> List(Diagnostic)`. The plans produce: `validate(Chart)`
   (`core-api`), `layout.diagnose(Chart, Metrics)` (`layout`, its own open question 5), and
   `theming`'s five diagnostics which require *trained domains* and therefore cannot be produced by
   either. See G2 below — this is also a gap.

7. **`testing`'s `resvg` in CI** — correctly self-flagged (open question 1). It is defensible (no JS
   engine, no DOM, never in the shipped library) but the README says *"no headless browser"* and the
   exception must be written into the README, not left as CI folklore.

8. **Overclaim carried into the README.** README v0.1 scope says *"SVG renderer targeting a string
   (Erlang) and Lustre elements (JS) **from shared code**."* Every stream now says the opposite —
   two independent folds over a shared `Scene`, with an equality test rather than shared code
   (`scene` D6/D10, `lustre` L3, `ecosystem` D2). Fix the README line.

---

## Gleam impossibilities

1. **`core-api`: `pub fn custom(data data: List(row), draw draw: fn(Frame) -> List(Node)) -> Layer`.**
   `Layer` is unparameterised and `draw` never receives `row`. Either `data` is dead weight, or the
   `List(row)` must be stored in an unparameterised `Layer` — which is the existential `core-api`
   D1 says Gleam lacks. Not expressible as written. (`scene` and prior art both specify
   `custom(fn(Frame) -> Scene)`, which has the different problem that a *layer* returning a whole
   `Scene` cannot compose with other layers into one `Scene`.) The escape hatch — decision 0001's
   *"cheapest insurance on the list"* — has no coherent signature in any stream.

2. **`layout` module cycle** — see B13.

3. **`core-api`: `pub type Diagnostic { Diagnostic(severity, message: String, hint: String) }` vs
   everyone else's variants.** `scales` contributes *"`EmptyDomain(channel)`,
   `LogDomainCrossesZero(channel)`, `DegenerateDomain(channel)`, `ZeroBandwidth(channel)`,
   `OrdinalRangeExhausted(channel, needed, have)`, `TimeSpanBelowResolution`"*; `layout` adds
   *"`TitleOverflowsCanvas`, `AllLabelsDropped`, `UnshapedLabelText`, `PlotAreaDegenerate`"*;
   `theming` adds five more. A record with a `message: String` cannot express any of them, and tests
   cannot assert on them. A public sum type makes every new diagnostic a breaking change — the exact
   hazard `core-api` D4's opacity rule and `roadmap` D4's eliminator pattern exist to avoid. Nobody
   picked. This blocks `testing`'s degenerate-input unit tests, which *"assert on what `validate`
   diagnoses."*

4. **`testing`'s flagship property is not well-typed.**
   ```gleam
   let xs = list.map(cats, scale.band_convert(s, _))     // List(Result(Float, Nil))
   p.0 +. scale.bandwidth(s) <=. p.1                     // Float +. Result — type error
   list.first(xs) |> result.unwrap(0.0)                  // Result(Result(Float,Nil),Nil) — type error
   ```
   `scales` D-shapes make `band_convert` return `Result(Float, Nil)` and its own risk section warns
   *"expect this to feel heavy in the mark stream."* It is heavier than the testing stream noticed:
   every property, every mark, and every axis must thread it.

5. **Nine public type-name collisions across streams.** These compile only after renames, and every
   rename is a doc rewrite:
   `Continuous` (channel, `core-api`) vs `ContinuousScale` (`scales`) — flagged by `scales`, unfixed;
   `Style` (per-primitive paint, `scene`) vs `BarStyle`/`LineStyle`/`PointStyle` (mark options,
   `core-api`) vs `Style` (theme appearance, `theming`);
   `Role` (`X|Y|Fill|Stroke|Size`, `core-api`) vs `Role` (`AxisX|AxisY|Grid|Frame|Legend|Annotation`, `scene`);
   `Frame` (transparent scene node, `core-api`) vs `Frame` (opaque layout result, `layout`) vs
   `Frame` (a `Chart` field, `roadmap`);
   `Domain` (`Numeric|Categories`, `core-api`) vs `Domain` (`EmptyDomain|NumericDomain|CategoricalDomain`, `scales`);
   `Font`/`Weight` (`Font(family, weight, size_px)`, 2 weights — `layout`) vs (`Font(family, size_px, weight)`, 3 weights — `ecosystem`);
   `Color` (`theming`) vs `Colour` (`scene`);
   `Metrics.custom` arity 2 (`layout`) vs arity 3 (`ecosystem`), both declared "frozen at v0.1";
   `Scheme` (erased wrapper, `theming`) vs `Scheme` (the thing `roadmap` task 14 ships).

6. **Gleam has no default arguments — and the workaround is combinatorial.** Correctly cited
   everywhere, then quietly ignored. `layout` proposes `render` + `render_with_metrics`; `theming`
   wants `Theme`, `ColorMode` and an `id` mandatory at `build`; `scene` wants `Options`; `lustre`
   wants `Size`. Two entry points become sixteen, or everything becomes a `Chart` setter with a
   default, which is the merge semantics decision 0001 forbids. No stream owns this.

7. Minor, but pervasive in the shapes blocks: `pub type Shape { Circle  Square  Triangle }` on one
   line, `pub type Interp { Quantize(bins: Int) Smooth }`, `pub type Paint { NoPaint  Solid(Colour) }`
   — not valid Gleam. Harmless shorthand, but it means none of these blocks were compiler-checked,
   which is consistent with the type errors in items 3–5.

---

## Scope problems

**The budget is off by roughly a factor of three.** `roadmap` commits to *"~200 hours ± 30%, five to
seven months at 8–10 h/week"* across 20 tasks. The eight streams enumerate **95 tasks** — 33 marked
M and 4 marked L. At the streams' own sizing (S≈4h, M≈10h, L≈20h) that is ~650–750h. The 200h figure
is `roadmap`'s own task list costed in isolation; it does not price the work the other seven streams
scheduled.

**The specific under-costings:**

- **`scales` task 9 (`dapper/time/interval`, L)** — the stream calls it *"the one that will
  overrun."* `roadmap` folds all of linear + log + **time** + band into one task 4 (L, inside a 50h
  milestone). d3-time's interval algebra over a `Zone`, with `floor`/`offset`/`count` primitive and
  Day-and-above through `gleam/time/calendar`, plus the duration ladder, plus cascading labels, plus
  an English `Locale`, is 60–80h alone.
- **The `layout` stream is a milestone, not a task.** 11 tasks including a Python font-parsing
  generator, a ~30 KB generated Gleam module, a cross-target parity test, the pane grid, the
  two-pass cycle, overlap resolution and rotation. `roadmap` gives it one M inside M0.
- **The `theming` stream is a package.** Oklab round-trip, Viénot/Brettel LMS simulation for three
  deficiency types, WCAG contrast over scheme × style × mode, three opaque scheme types, `<style>`
  emission with id-scoping, L1 sentence generation, L2 statistics, HTML table generation,
  `render_figure`. `roadmap` gives it one M (task 14) plus one S (task 15).
- **`lustre` task 6, the hydration example ("v0.1 ends here"), is marked S.** It requires a mist
  server, a JSON encoder on the server, a decoder on the client, a client build pipeline, and a
  worked demonstration that the rebuilt `Chart` produces a byte-identical tree. That is M–L and it
  is the README's demo.
- **`layout` task 8 (rotation, S)** — rotated bounding-box math, an anchor/baseline table across
  three angles × three anchors × three baselines, and overhang folding into pass-A seed insets, in
  a stream that admits *"rotated labels near the first or last tick remain the ugliest output dapper
  will produce."* Not S.

**Cut list, in order:**
1. Extended-Wilkinson entirely (B12). `scales` already says *"cut it without regret."*
2. Time scales and `channel.time` to v0.2 — the honest alternative to a 200h budget. This costs the
   README a line and `scales` its largest task. If time stays, the budget must triple.
3. L2 a11y statistics, `render_figure`, the data table, the docs swatch page (`theming` T9, T10, T13
   — all self-marked "unblocks nothing").
4. `dapper/metrics/canvas` (`layout` task 11 — self-marked "shipping without it is fine").
5. `scales` `QuantizeScale` + `OrdinalScale`-driven sequential/diverging colour — v0.1 has no
   continuous colour channel in `core-api`'s `mark` signatures. `theming` ships `Sequential` and
   `Diverging` schemes for channels that do not exist.

**Honest critical path** (nothing renders before all of it lands):
formatter → geom → font generator → metrics → domain/training → ticks (1–2–5) → linear scale →
band scale → Scene ADT → attrs → SVG emitter → channels/erasure → Chart/build → **axis emission
(unowned, see G1)** → two-pass layout → bar mark → snapshot harness on both targets.

That is ~15 items, four of them L, and it delivers exactly one bar chart. Everything else — line,
point, colour, theme, a11y, Lustre, validate — is after it.

---

## Gaps nobody covered

**G1. Nobody owns axis, gridline or legend rendering.** `layout` produces `kept_labels(frame, edge)
-> List(#(Float, String))` and `axis_space`. `scene` defines primitives. `core-api`'s only
`Node`-producing function is `mark.draw(MarkKind, …)`, which is per-mark. Who emits the axis rule,
the tick marks, the tick labels at the right anchor/baseline, the gridlines, the axis title? Only
`roadmap` task 11 mentions it, bundled inside "Axes with two-pass layout." It is a substantial M on
its own and it is on the critical path.

Legends are worse: `roadmap` lists legends as *"reserved slots only"* in v0.1, yet `core-api`'s
`bar` takes `fill: Option(Discrete(row))`, `theming` ships `cat_at` and derives legend entries, and
`layout` D12 reserves *"a single right-hand column whose width is the widest measured entry plus
swatch and gap."* A colour-encoded chart with no legend is unreadable. Decide: no `fill` channel in
v0.1, or legends ship.

**G2. `validate(Chart)` cannot see the things it is specified to diagnose.** `EmptyDomain`,
`LogDomainCrossesZero`, `DegenerateDomain`, `TooManyCategories`, `DivergingCenterOutsideDomain` all
require *trained domains* — stage 4 of `build`. `validate(Chart) -> List(Diagnostic)` therefore
either re-runs stages 0–4 (doubling the cost, and duplicating logic that must not drift), or `build`
must return diagnostics alongside the `Scene`. No stream states which. This also decides whether
`layout.diagnose` is a second function or a merge.

**G3. What is a "series"?** `Key` carries one. `Resolve` unions across them. Colour is assigned by
one. `LegendToggled(series: String)` toggles one. `theming.explicit` is keyed by one. But
`mark.bar(…, fill: Option(Discrete(row)))` means a *single layer* produces N series — one per
distinct fill value. Nothing defines the mapping from (layer index, fill category) → series
index/name, its ordering across layers under `resolve.shared()`, or its stability when the data
changes. Keys, colours, legends and hydration all depend on it, and it is unretrofittable.

**G4. Categorical domain ordering across layers.** `scales` D6 specifies first-appearance order, but
first appearance *in what traversal*? Layer order × row order, presumably — nobody says. Combined
with `ecosystem` D6 (`dict.keys` returns different orders on Erlang and JavaScript), an accidental
`Dict` anywhere in colour assignment or legend building produces a chart that differs by target and
passes every property test. Needs a stated invariant plus the grep-based CI ban `ecosystem`
proposes.

**G5. Two independent id systems.** `scene` D9 needs `id_prefix` for deterministic `clipPath` ids;
`theming` D8 needs a chart `id` for `#id`-scoped CSS selectors; a11y needs ids for
`aria-labelledby`. Three id concepts, two of them caller-supplied, never reconciled — and neither
has a route through `render : Chart -> String`.

**G6. Degenerate input behaviour is asserted but never specified.** `core-api` risks: *"an unhandled
empty domain or a zero-width range must produce a degenerate `Scene`, never a crash. Needs explicit
tests, not just intent."* `testing` agrees and wants *"named unit tests with exact expectations."*
Neither states the expectations. What is the `Scene` for `chart([])`? For a single datum? For a
`[5.0, 5.0]` domain? For `log` convert on a negative value (`scales` says *"total convert with
documented fallback"* and never documents the fallback)? These are the tests that must be written
first and there is nothing to write them against.

**G7. Minimum mark extent.** `scene` risks: *"rounding to 2 decimals can make a thin bar degenerate
(`x0 == x1`)… needs a minimum-extent rule in the mark layer, not in the emitter — a cross-stream
fix."* No stream schedules it. `theming`'s `Context` has a "minimum mark size" field that nothing
consumes.

**G8. Licensing of the d3 port.** Every stream says *"port d3-scale/d3-time verbatim."* d3 is ISC;
the repo is Apache-2.0. Verbatim ports require attribution and probably a `NOTICE`. `scales` open
question 5 asks only about *test fixtures*. The code itself is the larger surface. Similarly the OFL
question for Arimo/Cousine: `layout` decides to bundle them and keep the `.ttf`s out of the Hex
tarball while shipping *derived* advance tables — whether the derived table needs the OFL notice is
unanswered, and `ecosystem` flags it as *"a licensing surface."*

**G9. Font family is decided in one stream and open in two.** `layout` D3 commits to Arimo + Cousine
with a specific emitted `font-family` stack. `ecosystem` open question 1 says *"Inter and Source
Sans 3 are the obvious candidates. This blocks task 5, which blocks most of the plan."* `roadmap`
open question 1 says it is *"effectively permanent"* and unanswered. Additionally `theming`'s
`Style` carries a font family the user can set — which invalidates every measurement, a
consequence `layout` names as a risk and `theming` does not mention at all.

**G10. Core dependency list is contradicted by the definition of done.** `roadmap` DoD:
*"`dapper` depends on `gleam_stdlib` only."* `ecosystem`'s `gleam.toml`: `gleam_stdlib` + `houdini`.
`scales`: *"`gleam_time` package must be added to `gleam.toml`."* If time ships and escaping uses
houdini, core has three dependencies and the DoD is false as written. Also `gleam.toml` currently
declares `version = "0.1.0"` while `roadmap` D2 wants `0.0.1` published from M1.

**G11. `theming` puts the entire dataset inside `Scene`.** `A11y(title, description, table: Table)`
with `Table(rows: List(List(String)))` on every `Scene`, whether or not `render_figure` is called.
That doubles the snapshot subject, appears in every golden and every `to_debug_string` diff, and is
carried across the `dapper` → `dapper_lustre` boundary for no browser purpose.

---

## Weak claims

1. **`core-api`: *"microseconds since epoch — under 2^53, so exact."*** True today (≈1.8e15 µs) and
   until ~2255, but only for whole microseconds; `Timestamp` is `#(seconds, nanoseconds)`
   (`ecosystem` D7), so the conversion truncates and the claim of exactness is about the
   representation, not the round trip. And it is the wrong unit regardless (B6).

2. **`scene` D8: *"Both targets are IEEE-754 so arithmetic agrees."*** `scales` refutes this in its
   own risk list — *"the accepted line… is **false** for `log`/`pow`/`exp`; correct rounding is not
   required, and Erlang's `math:log10` and JS's `Math.log10` may differ in the last ulp"* — and
   `scales` is right. `scene` restates the false version as settled and builds decision 8 on it.
   The mitigation (`truncate` then verify by integer-exponent power comparison) belongs in a shared
   helper that both `ticks` and `format` use, and only `scales` knows about it.

3. **`lustre` L3: *"Lustre emits attributes in list order."*** Contradicted by `ecosystem`'s
   executed test. Both cite the same tarball. This is the single claim in the sprint most worth
   re-running before anyone writes an emitter.

4. **`layout` D6: *"measurement is **exact**"* for numeric labels.** Three assumptions stacked:
   Arimo's advances match Arial's (self-admitted as *"an assumption I have not verified
   glyph-by-glyph"*); the viewer *has* an Arial-metric font; and the browser's rendered width equals
   the sum of advances. The third is false in general — hinting, subpixel positioning and
   `text-rendering` all perturb it. "Exact" should be "exact in our model."

5. **`layout` D3: *"on the overwhelming majority of clients our measurements are… right."*** The
   same stream's risk list says clients lacking any Arial-metric font see ~10% error and names
   *"some Linux, some locked-down Android."* Those are not a rounding error in a server-rendering
   library whose output is embedded anywhere. The honest framing is the error budget, which the
   stream does state well — the "overwhelming majority" sentence overstates it.

6. **`core-api` D5: *"Adding a mark touches one variant and two `case` arms — a genuine improvement
   over the lineage."*** `requirements` + `draw` covers geometry and channel roles. It does not
   cover: legend swatch drawing, tooltip/anchor position, minimum extent (G7), series assignment
   (G3), the `include_zero` question (`scales` open question 4 — *"who owns `include_zero` for bar
   baselines… it determines whether `Domain` needs mark-awareness"*), or per-mark `validate` rules.
   elm-charts' six functions may simply reappear as six fields of `Requirements`. Unproven until the
   second mark lands.

7. **`scales` D1: the elm-visualization closure record *"exists ONLY because `Scale inp` is
   polymorphic in `inp`."*** A stronger causal claim than the cited source supports. It does not
   change the conclusion (closed sums are right, for the `validate`-cannot-inspect-a-closure reason,
   which is the good argument) but it should not be stated as fact.

8. **`testing` D4: *"One property retires [the drift risk]."*** Only if the property can be
   expressed in a package that can see both emitters (B5) and only if byte equality holds (B4).
   Currently neither is established.

9. **`theming` D2: separate nominal types make *"a sequential scheme cannot fill a nominal channel"*
   a compile error.** True at the channel constructors, then immediately reopened by the public
   erased `Scheme { Cat | Seq | Div }` wrapper *"used only where all three must be stored
   uniformly (legend rendering, the `Scene`)."* Wherever `Scheme` is accepted, the guarantee is
   gone. It is a smaller hole than the stream implies.

10. **`theming` D4/D5 palette hex values.** Self-flagged: *"from memory of published palettes and
    must be verified against source before release,"* and the dark column *"is a candidate derived
    by Oklab lightness lift, not a published palette."* Correctly handled — but `roadmap` task 14
    schedules `Scheme`/`Theme` without scheduling T3, the simulation harness that gates it.

11. **`roadmap`: *"~200 hours ± 30%."*** See Scope. The ±30% band does not contain the sum of the
    plans it is meant to sequence.

12. **`lustre` L4: hydration mismatch *"degrades to a re-patch, not a crash — a far better safety
    profile than React."*** True, and the same document then says *"hydration mismatch is
    invisible: a silently-repatching chart still looks correct… or the SSR path will rot
    unnoticed."* Those are the same fact framed twice, once as a selling point.

---

## What survives unscathed

Genuinely and without qualification:

- **`ecosystem-recon` as a whole.** It is the only stream that executed code rather than reasoning
  from documents, and every one of its measurements — `float.to_string` divergence, `string.inspect`
  divergence, the 2^53 scaled-integer blowup, `dict.keys` ordering by target, the 1400-arm `case`
  compile times, `string.to_graphemes` parity, birdie's shared snapshot directory on both targets —
  is load-bearing and correct. Where it disagrees with another stream, it should win by default. Its
  refusals (`string_width`, `svg_path`, `gleam_community_maths`, `gleam_json`, `glearray`,
  `glychee`) are all well argued.

- **`Scene` as the seam, rects as `(x0,y0,x1,y1)`, no `Backend` record, no transform stack.**
  Unanimous, correctly reasoned, and the negative-width SVG argument in `scene` D2 is a better
  justification than prior art gave.

- **Pinning dapper's own float formatter and banning `float.to_string`/`string.inspect` from `src/`,
  with a grep-based CI check.** The right call, for the right reason, in every stream — even though
  the five specs disagree (B11).

- **Embedded advance tables as generated Gleam source, defaulting on both targets, with a digest
  test.** matplotlib's determinism-over-fidelity position, correctly transferred, with a declared
  error budget. `layout` D5's "wrong-and-loud beats wrong-and-silent" for complex scripts is the
  right answer to Vega #2940.

- **Two-pass layout, with only ticks recomputed.** `layout` D1's observation that mapping data once
  makes the second pass O(ticks) rather than O(n) is the specific insight that makes the bound
  affordable, and it is not in the prior art.

- **`scales` D9's split of extended-Wilkinson**, and its transcendental-ulp risk with the
  integer-power-comparison mitigation. That risk is the sharpest thing anyone found and it would
  otherwise have surfaced as an unreproducible snapshot failure months in.

- **`testing` D3's two mechanisms** — birdie for `Scene`, plain viewable `.svg` files for output —
  with the review argument (*"you open the file in a browser and look at the chart"*) and the
  snapshot-review-fatigue mitigations in CONTRIBUTING. The `resvg` smoke test is 30 lines for the
  one failure a text snapshot structurally cannot see.

- **Okabe–Ito reordered blue-first, viridis, PuOr-over-RdBu, and asserting CVD safety with a test
  rather than a comment.** The reasoning is specific and correct, and `theming` is honest that the
  hexes need verifying before they ship.

- **Refusing named timezones, and saying so loudly.** `ecosystem` D7 and `scales` D11 reach the same
  conclusion from the same evidence, and the DST error budget is declared rather than discovered.

- **The 1×1 pane grid from day one with axis space reserved per *edge*.** Near-zero cost now,
  Polaris's rewrite avoided later. `layout` D10 identified the one choice inside it that actually
  matters.
