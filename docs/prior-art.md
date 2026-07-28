# Prior art

A synthesis of the nine briefs in `docs/research/`. This exists to make decisions, not to survey.
Where the briefs disagree, it picks a side.

## The three theories of what a chart is

Three real answers, plus a fourth that is a theory of the *back half* and composes with all of them.

### 1. A chart is a specification — a point in a generative parameter space

*Wilkinson → ggplot2 → Vega-Lite/Altair → Observable Plot → seaborn.objects.*

"Scatterplot" and "histogram" are derived facts, not primitives. A chart decomposes into orthogonal,
independently variable slots — Wickham's `data × mapping × stat × geom × position`, Vega-Lite's
`(data, transforms, mark, encodings)`. Wickham's evidence that the decomposition is *correct* is
that it accidentally generated a chart nobody had a name for.

**Easy:** novelty (a frequency polygon is `bin` + `ribbon`, not a feature); composition (Vega-Lite's
view algebra unifies layering, trellis, SPLOM and dashboards under one operator set); charts as
searchable data (Voyager and Draco exist only because a spec is a point in a finite space); and —
via `resolve` — *naming* the scale-sharing ambiguity every other tradition guesses at silently.

**Hard:** anything not decomposed. The spec grows a compiler and the compiler grows a wall —
Vega-Lite's authors concede "components determined at compile-time cannot be interactively
manipulated." Errors surface late: ggplot2's from deep inside `ggplot_build()`, Vega-Lite's from a
JSON Schema `anyOf` cascade quoting the wrong property. And the grammar is honest that it does not
save you — "we can produce many plots that don't make sense, yet are grammatically valid."

### 2. A chart is a table of query results, drawn

*Polaris → Tableau/VizQL → Show Me → Power BI → Looker/Malloy.*

The *layout algebra is primary and the mark is a leaf detail*. Shelf expressions over a field algebra
(`cross ×`, `nest /`, `concat +`) normalize to a set whose entries *are* the rows, columns and layers
of a pane grid. One specification is read two ways — geometry and SQL — and they must agree, because
a pane is literally `SELECT … WHERE {Row(i) ∧ Col(j) ∧ Layer(k)}`. Mark, aggregation, scales and
legends are *derived*; automation is the thesis, not a convenience.

**Easy:** small multiples (they are the base case; a single chart is a 1×1 table), pushing work to a
database, undo/redo (push the spec on a stack), and teaching non-programmers a type system — the
dimension/measure split is the most successful piece of type propaganda in the industry.

**Hard:** anything the algebra cannot say. Measures are second-class (`P = {P}` is a singleton, so
only ordinal fields partition), making "plot sales and profit side by side" inexpressible and forcing
the `Measure Names` pseudo-dimension — twenty years of pain from one line of the algebra. Interaction
and multi-view composition sit outside the formalism entirely; Vega-Lite's view algebra exists
*because* the table algebra could not do dashboards. And `nest` is data-dependent, exactly where a
compile-time story cannot follow.

### 3. A chart is a region of a host document, bound to data

*D3 → Recharts/Victory/visx/nivo → shadcn.*

Composition is already solved — by the DOM, or by React — so don't invent a second mechanism. D3's
principle is *representational transparency*: refuse an intermediate scenegraph so CSS, devtools and
immediate evaluation keep working. The React lineage makes the same bet one level up: the component
tree *is* the description.

**Easy:** debuggability, styling, arbitrary user content inside the chart (a tooltip is a div),
reconciliation/events/SSR for free.

**Hard:** everything off the host. D3 cannot render without a DOM, which is why the JS ecosystem
drags a headless Chrome around for server-side images. And the tree turns out to be a grammar with no
type checker: Recharts classified children by component identity, so wrapping `<Bar>` in your own
component makes it *silently vanish* (#412, #2788, #3416) — Vega-Lite's runtime-schema failure
relocated into JSX, failing more quietly. The tell is Recharts v3, which after a decade replaced tree
introspection with a per-chart Redux store. **The tree was always a spec in disguise.**

### 3½. A chart is a product feature (the config tradition)

*ECharts, Highcharts, Chart.js, Plotly.* Theory 1 with the algebra removed and the feature list
maximised. Because deep merge forces every field optional, the spec's type is
`DeepPartial<Everything>` — Plotly ships 4.4 MB of schema, 49 traces, ~11,340 leaf attributes — so
static checking is *structurally* impossible here. Wins on completeness (tooltips, zoom, export,
WCAG 2.2, WebGL boost); loses on composition: no `overlay()`, no `facet()`, just a flat `series[]`
and hand-wired `xAxisIndex: 1`.

### 4. (Orthogonal) A chart is a scenegraph

*matplotlib's artist layer, Vega's renderer registry, `diagrams`, Plotters, vl-convert.* A theory of
output, not authoring: a resolution-independent tree of positioned primitives existing before any
pixel or tag, with rendering as a fold onto whatever surface you have. matplotlib reduced the backend
to roughly four methods, and the asymmetry is the whole story — rendering is write-only *except for
text measurement*. **dapper is structurally on the scenegraph side of the D3 argument and should say
so**; the dual-target claim is unavailable otherwise.

## What every serious library converges on

1. **Invertible scales.** The inverse *is* the axis and legend (Wickham) and the interaction
   primitive (Bostock).
2. **A real tick algorithm.** D3's 1–2–5 (`e10=√50, e5=√10, e2=√2`) is the floor; Talbot/Lin/
   Hanrahan's scored optimisation is most of the gap between professional and homemade.
3. **Text measurement and the layout cycle it creates** — ticks → format → measure → reserve margin
   → re-range → re-tick. Axis space, label collision, autosize, resize and faceting are all *that
   cycle*. Nobody has a principled fixpoint.
4. **A resolved intermediate between spec and output.** Even the tradition that refused one rebuilt
   it: Recharts v3's store, Plot's channels, Vega's scenegraph, `ggplot_build`/`ggplot_gtable`.
5. **An explicit answer to "shared or independent scales?"** Vega-Lite alone *named* it (`single |
   independent | union | intersect | *_others`); everyone else guesses and gets complaints for it.
6. **A terse layer over the explicit one.** D3 → Plot, Plotly → Express, visx → xychart, ggplot2's
   `geom_*`. Every explicit-only API grew a wrapper — but heed the `qplot` post-mortem: "to which
   layer does the `method` argument apply?"
7. **An escape hatch.** Sokol abandoned her own opinionated `elm-plot` because "it's very difficult
   to predict what is a good chart." The only question is whether the hatch is a step or a cliff.
8. **Slots for title, legend, tooltip, annotation.** Retrofitting these hurt the grammar lineage.
9. **Theming, light/dark, and size-for-medium** — seaborn's `style` vs `context` axis is the one
   nobody else models and dapper needs (server report vs dashboard component).
10. **Large-data reduction as a flag** (`boost`, `sampling: 'lttb'`, `decimation`), never a
    user-authored transform.
11. **Accessibility**, possible only *because the chart type is known*. "Rect marks" cannot narrate;
    "bars over a band scale" can.
12. **Two packaging layers.** d3-scale/d3-shape outlived D3; visx's thesis is that the durable unit
    is a scale, not a `BarChart`.

## What dapper should steal, ranked

1. **Accessor-function channels over `List(row)`** *(typed-FP: elm-charts, Swift `Plottable`)*.
   Settles README question 1 and deletes the entire field-name-typo and expression-string error
   class — where real Vega-Lite errors live, and which JSON Schema structurally cannot reach.
   Row-oriented, not columnar: columnar forces string field names back into the API.
2. **A public `Scene` ADT as the seam between grammar and output** *(Vg's "denotation before API";
   matplotlib's artist/backend split)*. Marks emit resolved primitives with geometry computed;
   `Scene -> String` and `Scene -> Element(msg)` are two plain functions. This makes the dual-target
   claim true rather than aspirational, and snapshots assert geometry, not string formatting. Do
   **not** build a `Backend` record of functions until a third target exists — `diagrams` is the
   cautionary tale.
3. **Text metrics as an injected value, defaulting to an embedded advance table on *both* targets**
   *(matplotlib's bundled DejaVu + pinned FreeType; vl-convert proving "the DOM was never the
   requirement, a font file was")*. Identical metrics on BEAM and JS means one snapshot suite covers
   both and the render paths *cannot* drift. Canvas `measureText` is opt-in, never default.
4. **Split scale types instead of faking a uniform interface** *(D3's lesson inverted;
   elm-visualization's admitted mistake)*. `invert`/`ticks` on continuous, `bandwidth`/`step` on
   band, and `bar` *requires* a band scale. One signature converts Plot's most common runtime error
   into a compile error — the cheapest real demonstration of the wedge.
5. **Port d3-scale/d3-array math verbatim**, then extended-Wilkinson tick selection — ~100 lines of
   pure scoring consuming the `Metrics` you already have. Highest quality-per-line item on the list.
6. **Encode compatibility as *arity*, not a predicate** *(typed-FP)*. Per-mark constructors taking
   exactly their channels, so the error reads "expected `Continuous(row)`, found `Discrete(row)`" —
   about charts, not type machinery.
7. **Mandatory `Resolve`** *(Vega-Lite)*: `union | independent | intersect | *_others`, required.
   Vega-Lite's worst trap is *silent* unioning ("cannot enforce that a unioned domain is
   semantically meaningful"); Gleam's lack of default arguments is an asset.
8. **`Stat` and `Move` as separate stages** *(seaborn.objects — a genuine advance over ggplot2's
   bolt-on `position_*`)*. Never fold dodging into `Bar`.
9. **Render into a 1×1 pane grid from day one** *(Polaris)*, and train scales across all layers even
   with one layer *(ggplot2)*. A renderer assuming a single plot region is the rewrite this lineage
   exists to warn you about.
10. **ECharts' SSR/hydrate split, literally**: SVG string on the BEAM, then a small Lustre component
    hydrating legend toggles and tooltips — not a full client re-render.
11. **`ChartConfig`-style presentation metadata as a third value** *(shadcn)*: `Dict(String,
    SeriesMeta)` with `label` and `Color = Literal | CssVar` plus a light/dark pair.
12. **Total `validate(Chart) -> List(Diagnostic)` beside a total `render`** *(typed-FP)*. Compiler
    owns shape, validator owns semantics, no "spec rejected" branch.
13. **Stable keys `(facet, series, datum_index)` on every emitted mark** — free now, enables keyed
    diffs and hit-testing later, unretrofittable.
14. **Generated accessibility at string-construction time** *(Highcharts; Lundgard/Satyanarayan)*:
    `role="img"`, `<title>`, an L1 `<desc>` derivable from the spec alone. Never fabricate L3/L4.

## What dapper should refuse

- **`+` and a base plot object.** Wickham says outright it "is not necessary in a stand-alone
  grammar" and exists only to preserve declarativeness *in R*. Use pipelines.
- **A serialisable spec.** Accessor closures and JSON portability are an either/or; accessors win.
  This forfeits cross-language portability, machine-enumerability (you cannot write Voyager over a
  closure), and "generate on server, store in a DB, render anywhere." **Say so in the README rather
  than discovering it at v0.3.** Mitigation: allow `Dict(String, Value)` as a legal `row`.
- **A reactive dataflow runtime.** In Lustre a selection is `fn(Msg, Chart(row)) -> Chart(row)`; TEA
  already is the runtime.
- **Owning interaction state.** Recharts v3 rebuilt a Redux store TEA gives you free. Emit typed
  messages; let the user's `update` decide.
- **Deep-merge-of-partials and index references.** `xAxisIndex: 1` is a permanent dangling-ref bug
  class; hold the scale as a value inside the layer.
- **Any `Dynamic`/props-bag escape hatch** — that is runtime validation, re-added.
- **DOM-dependent measurement.** `getStringSize` dominates Recharts render time (~40k calls for a
  10k-point chart), returns 0 in some environments, leaks nodes, trips CSP — and is absent on BEAM.
- **Iterating layout to a fixpoint.** Bound at two passes; Vega's `autosize: "fit"` is the warning.
- **`repeat`** — its own authors concede it "is not strictly algebraic." It breaks the ADT.
- **Canvas, WebGL, headless browsers** — all destroy `render : Chart -> String` as a pure BEAM
  function. ~10k marks of SVG is fine; past that the answer is a transform, not a backend.
- **Phantom-typed pipelines.** `plotters` bought type-level correctness and paid in a forum thread
  titled *"Lost in trait bound hell."*

**Good ideas that are wrong for v0.1:** the **table algebra** (most original decomposition here, but
`Nest` is data-dependent and cuts against the compile-time story — ship the pane grid, not the
algebra); **faceting** (the biggest chunk beyond v0.1 — but reserve `ScaleResolve(Shared |
Independent)` per channel and a per-layer `facet_scope` copying seaborn's `col=None`); **stats**
(seaborn is right that the estimator belongs in the spec, but a wrong `Stat` ADT is harder to undo
than a missing one); **`dapper/suggest`** (a `case` over `(FieldKind, FieldKind)` the compiler proves
total is lovely, but in core it invites use as a default — Tableau's morphing-marks failure mode);
**uncertainty by default** (a decade of published figures had error bars nobody chose; the fix was
making the choice *nameable*, not defaulting it).

## The hard problems nobody solved elegantly

**Text measurement without a DOM** is load-bearing and *still broken in the state of the art*. Vega
#2940: the same string measures 44px on a raster node-canvas and 40.5px on an SVG canvas; Vega always
instantiates the raster one; node-canvas locks measurement to whichever was created first; open for
years. Without node-canvas, Vega falls back to a per-character estimate and axis layout visibly
breaks. dapper's position should be matplotlib's — bundle the metrics, pin them, choose determinism
over fidelity — with the error budget declared: fine for axis labels and legends, probably not for
long titles or rotated labels near a boundary. And perfect measurement is *still wrong* if the viewer
lacks the font; the only fixes are embedding the font or converting text to paths, and the latter
destroys selectability and screen-reader access.

**Label layout** is downstream of the same cycle. Vega's `labelOverlap: parity | greedy` is the best
answer anyone has — a fiddly geometric problem reduced to a one-word choice. Take it verbatim.

**Runtime vs compile-time validation.** Nobody drew this line well, and the briefs agree why: some of
the grammar is shape and some is data. "Bar with two continuous axes" is arguably typeable; "log
scale crossing zero", "empty domain", "200 categories on colour", "is this `nest` inhabited" are not.
Polaris draws it honestly — `Chart` is a checked *shape*, `resolve(chart, data) -> Result(Layout,
DataError)` is where cardinality enters. Copy that line and write it down before the API hardens.

**Large data.** Everyone flipped a flag rather than solving it. The interesting part: M4 is
*pixel-exact for line charts at a known plot width* — parameterised by layout, which the cycle above
produces. Correct placement is inside layout; simple placement is an explicit transform with a
declared width. Take the simple one for v0.1 and know it is the compromise.

**The escape hatch.** Every tradition's is either a cliff (Vega-Lite → Vega, Plot → D3, seaborn's
"two-library problem") or a hole that re-admits runtime validation. ECharts' `renderItem` is
least-bad: arbitrary graphics per datum that *still inherit* coordinate systems, layout and events.
Copy that shape — `custom(fn(Frame) -> Scene)`, one-way and terminal.

## Where compile-time typing actually pays

**The README's first wedge, as worded, is partly wrong, and the second wedge is the stronger one.**

"Vega-Lite validates its grammar with a JSON Schema at runtime; in Gleam the compiler checks it"
misdescribes the situation. Vega-Lite's grammar *is already compile-time typed* — in TypeScript. The
JSON Schema is a **derived artifact**, generated so specs can cross a language boundary, and the
maintainers' pain is *schema-encoding* pain (`additionalProperties: false` plus intersections yields
unsatisfiable schemas; `A & (B | C)` blows up exponentially; no inheritance) — not "we forgot to type
the grammar." Altair and hvega users already have a typed surface. The people dapper beats are people
hand-writing JSON.

Worse, the errors that bite are mostly not structural: `"field": "temp_max"` keyed against a dataset
that does not exist yet; `"filter": "datum.location === 'Seattle'"` as a string; aggregate-plus-detail
conflicts; `x2` without `x`; stacking under an independent scale. All schema-valid, all wrong.
Vega-Lite's debugging guide makes schema validity *step one of four*, then sends you to runtime logs.
A typed grammar buys **shape**, not **semantics** and not **data binding**.

The typed-FP brief is more deflating still: **nobody has actually type-checked the mark × channel
compatibility relation.** Swift Charts encodes *nothing* — two quantitative axes compile fine and
render badly. elm-vegalite's `position` makes every combination typecheck and delegates validity back
to Vega-Lite's runtime schema; the strong typing is an autocompleting spell-checker over JSON. hvega
*retrofitted* even crude newtype separation. `plotters` produced trait-bound hell.
elm-visualization's own docs concede: "the cost is a certain ugliness and complexity of the type
signatures… I recommend ignoring the types."

**Where static checking genuinely pays, descending:**

1. **Accessor functions instead of field names** — the biggest win, and barely "clever typing": a
   change of representation that deletes an error class JSON Schema cannot reach.
2. **Split scale types** — `bar` requiring a `Band` converts Plot's commonest runtime error into a
   compile error, in one signature, with a readable message.
3. **Exhaustiveness over closed ADTs** — not "you can't write a bad chart" but "the library cannot
   forget a case": a total `case` over `(FieldKind, FieldKind)`; a new `Scale` variant flagging every
   site that must handle it; one eliminator per sum type.
4. **Arity in constructors** — `Bar(x: Discrete(row), y: Continuous(row), fill: Option(_))`. This is
   hvega's newtype separation, whose honest win was **separation plus autocomplete, not
   validation**: ~80% of the felt benefit for ~5% of the type-system effort. Ship exactly that.
5. **Mandatory arguments** — no optional fields means no deep merge, no silent theme override, and a
   `Resolve` the caller must state. Gleam's poverty is the feature.

**Where it does not pay:** domains, cardinality, non-emptiness, log-crossing-zero, stack coherence,
inhabited facets, "is this chart misleading." All need data, a lint, or both, and belong in
`validate`. Wickham stands unamended: the compiler rules out *ungrammatical* charts, not *misleading*
ones.

**The honest wedge, restated:** dapper's strongest claim is that **`render : Chart -> String` is pure
and total on the BEAM — no DOM, no headless browser, no font engine — and the same `Chart` renders as
a Lustre component in the browser.** Nobody has this; nivo built an SSR HTTP service and ECharts a
special SSR mode to approximate it. The typing claim is real but modest: **no field names, no
optional-field merge semantics, no forgotten cases, and mark constructors that state their
channels.** Do not claim compiler-checked chart *validity*. Prototype the hostile error — a band
scale passed where a linear one is required, three pipeline stages deep — before going past level 4.

## Open design questions for v0.1

1. **Data shape.** → **Row-oriented `List(row)` with accessor channels.** The rendering brief argues
   columnar (BEAM cost, Arrow alignment); it loses, because columnar forces string field names back
   into the API. Gleam records are tuples on BEAM, so the cost is smaller than argued.
2. **Serialisable spec?** → **No, loudly.** Closures win; portability and enumerability are forfeit.
3. **`Scale`.** → **Closed sum type, split by capability.** `Continuous` carries `invert`/`ticks`;
   `Band` carries `bandwidth`/`step` and has no `invert`. No user-defined scale types at v0.1.
4. **Time.** → **Settle before `Scale` hardens** — the largest hidden cost on the v0.1 list. Use
   `gleam_time`'s `Timestamp`; port d3-time's `Interval(floor, offset, count)` with `ceil`/`range`/
   `every` derived. That record is the entire reason D3's time axes look right.
5. **Metrics public or internal?** → **Public.** Freezing the signature early is the honest price of
   letting users inject a font.
6. **Float formatting.** → **Pin dapper's own formatter.** Both targets are IEEE-754, so arithmetic
   agrees; float-*to-string* is where BEAM and JS diverge and where snapshots break.
7. **Where does erasure happen?** Scale training must see values across layers of *different* row
   types, so channels erase to `List(Float)`/`List(String)`. → **Erase at `build`, after stat, before
   training.** Commit to the order now: scale-transform → stat → train over all layers → map →
   render. Getting it wrong is unfixable later without silently changing every chart.
8. **`build`/`render` split.** → **Yes, `Scene` public.** Snapshot `build`, not only the SVG. Store
   bars as `(x0,y0,x1,y1)`, never `(x,y,w,h)` — free now, mandatory if polar ever lands.
9. **Escape hatch in v0.1?** → **Yes.** `custom(fn(Frame) -> Scene)` inheriting scales, layout and
   legend; one-way and terminal.
10. **Packaging.** → **One package, two public layers.** `dapper/scale`, `dapper/shape`,
    `dapper/ticks` usable standalone; `dapper` batteries on top. The visx → xychart arc is inevitable.
11. **Theming (README question 3).** → **Bake a palette, but as a typed `Scheme`, not hex strings.**
    Applied at render via `apply_theme(Theme, Chart)` with `Theme(style, context)`; the colour channel
    fillable only from a `Scheme` whose variants encode categorical/sequential/diverging intent,
    CVD-safe default; colours as `Literal | CssVar` with a light/dark pair.
12. **Interaction state.** → **The user's model.** Emit typed messages; ship no store.
13. **Reserved-but-unimplemented slots.** → `title`, `legend`, `tooltip`, `annotation` on `Chart`;
    `stat: Identity`, `move: NoMove` on `Layer`; `ErrorBar`; per-channel `ScaleResolve`;
    `LabelOverlap`. All cheap now, all breaking later — and keep `Chart` opaque from day one, since
    in Gleam adding a public record field is a breaking change.
