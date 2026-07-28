# Vega-Lite (and Mosaic): the UW/MIT declarative lineage

Vega → Vega-Lite → Altair → Mosaic/vgplot. Jeffrey Heer's lab plus Arvind Satyanarayan and Dominik Moritz.

## The vision (what this tradition believes a chart is)

A chart is **a value in a small algebra, not a program**. You write down *what* you want; a compiler synthesizes the dataflow, the event handling, the scales, the layout. Because the chart is a value, it is portable (JSON crosses Python/R/Julia/Elm), inspectable, diffable, and — the ambition that really drives the lab — **machine-enumerable**. Voyager, Draco, and chart recommendation only exist because a Vega-Lite spec is a point in a finite, searchable design space. That is the deep bet: shrink the surface area enough and the tool can reason about charts, not just draw them.

The second bet is the one nobody else made: **interaction is part of the value too**. Vega-Lite's claim is that an interaction design "decomposes into concise, enumerable semantic units" — so brushing, panning, zooming, and cross-filtering are not callbacks bolted on, they are terms in the same grammar. An interactive chart is still a static thing you can print.

Underneath sits Reactive Vega, whose vision is different again: a chart is **one dataflow graph in which input data, scenegraph elements, and interaction events are all first-class streaming sources**. The grammar is the surface; the dataflow is the machine.

Mosaic then inverts the whole stack: a chart is **a client that publishes declarative queries**. Not a spec compiled to a runtime, but a component that says what data it needs and lets a Coordinator optimize and push the work to DuckDB.

## Core abstraction

Three tuples, verbatim from the 2017 paper:

```
unit      := (data, transforms, mark-type, encodings)
encoding  := (channel, field, data-type, value, functions, scale, guide)
selection := (name, type, predicate, domain|range, event, init, transforms, resolve)
```

Plus a **view algebra** closing over units: `layer`, `hconcat`, `vconcat`, `facet`, `repeat`, each parameterized by a `resolve` component that decides, per channel, whether scales and guides are `union`ed or `independent`.

The selection is the cleverest object in the lineage. It separates **backing points** (the minimal state an event populates) from **selected points** (what a predicate function derives). An interval brush is *two points plus a predicate*. That decoupling is what lets one abstraction serve as conditional encoding, as input data, and as a scale domain — brush, pan, zoom, and overview+detail become the same primitive under different transforms (`project`, `toggle`, `translate`, `zoom`, `nearest`).

Mosaic generalizes exactly this: a `Selection` is a set of predicate **clauses** (each with a source, a client set, and a SQL predicate) plus a resolution strategy that produces a *client-specific* predicate. Selection-as-SQL rather than selection-as-Vega-signal is the entire interoperability argument.

## Unique contributions

1. **The view algebra with automatic scale resolution.** ggplot2 has faceting; Tableau has a table algebra plus a *separate* dashboard mechanism. Vega-Lite unified layered plots, trellis plots, SPLOMs, and arbitrary dashboards under one closed operator set that merges scales when it makes sense.
2. **`resolve` as an explicit, enumerable knob.** "One brush for the SPLOM, or one per cell?" is a real ambiguity every multi-view tool silently guesses. Vega-Lite names it: `single | independent | union | intersect | union_others | intersect_others`. The `_others` variants make cross-filtering a one-word change. Under-copied; steal it outright.
3. **Predicate-backed selections** — the reason interaction fits in 1–2 lines instead of tens.
4. **Specification-as-data**, which bought the Python/R ecosystem and the entire visualization-recommendation research line.
5. **Mosaic's middle tier**: decoupling data processing from specification, so grammar authors and database people work on separate halves. Billion-row interaction falls out of automatic data-cube indexing over linked selections.

## Where it struggles

**The compile-then-run split is a hard ceiling.** The authors say it themselves: "components that are determined at compile-time cannot be interactively manipulated." A selection cannot change which field is binned or aggregated. No lasso, because there are no arbitrary path marks. Animated Vega-Lite (same lab, later) states flatly that selections cannot alter visual encodings or data-transformation pipelines at runtime. Everything expressive lives on one side of a wall the compiler erected.

**The escape hatch is a cliff.** When Vega-Lite runs out you drop to Vega — a different, far lower-level JSON language. And the monolithic compiler became an extension bottleneck: Heer & Moritz open the Mosaic paper by noting that requests for raster/contour marks, table views, and interoperable selections "have gone unaddressed for years."

**Elegance regretted.** Vega-Lite 5 dissolved `selection` into a general `param` for uniformity. The maintainers' own issue #7149 ("Revise whether to blend selection into parameter") asks whether that was a mistake, since filtering-by and scale-domain-from only ever work with *selections*. A nameable concept was traded for symmetry.

**On dapper's stated wedge — be honest.** Vega-Lite's grammar *is already compile-time typed*, in TypeScript. The JSON Schema is a **derived artifact**, generated by `vega/ts-json-schema-generator` purely so the spec can cross a language boundary. And that derivation is where the pain actually is: Moritz reports hitting "a wall … with intersection types" — `additionalProperties: false` plus intersections yields unsatisfiable schemas, `A & (B | C)` blows up exponentially, JSON Schema cannot express inheritance. The maintainers openly considered abandoning JSON Schema. So the pain is real, but it is *schema-encoding* pain, not *we-forgot-to-type-the-grammar* pain.

More importantly: **the errors that actually bite users are not structural.** `"field": "temp_max"` is a string keyed against a dataset that does not exist yet. `"filter": "datum.location === 'Seattle'"` is an expression string. Aggregate-plus-detail conflicts, `x2` without `x`, stacking under an independent scale — all schema-valid, all wrong. Vega-Lite's own debugging guide tells you that after checking schema validity you should go read Vega runtime logs. That is the tell. A compile-time grammar buys you *shape*; it does not buy you *semantics* or *data binding* unless you change what a spec is.

## Implications for dapper

**1. Encode the algebra's non-closure in the type, not in prose.** Vega-Lite's `layer` "restricts its operands to be unit views" — a rule enforced by its compiler and documented in English. In Gleam it's free:

```gleam
pub type View(row) {
  Unit(UnitSpec(row))
  Layer(List(UnitSpec(row)), Resolve)   // units only — enforced by the type
  Concat(Dir, List(View(row)), Resolve)
  Facet(FacetDef(row), View(row), Resolve)
}
```

That is the wedge in miniature: cheap, real, small. Collect a dozen of these (scheme-on-a-non-color-channel, `x2` without `x`, stack config on a non-stackable mark) and you have a genuine, demonstrable claim. Also heed their footnote that `repeat` "is not strictly algebraic" — it needs inner-spec parameterization. Don't ship `repeat` in v0.1; it is the operator that breaks your ADT.

**2. Make `Resolve` mandatory.** Vega-Lite's worst usability trap is *silent* scale unioning — the paper admits "Vega-Lite can not enforce that a unioned domain is semantically meaningful." Gleam has no optional/default arguments, which is normally a nuisance and here is an asset: force the caller to pass `Resolve` (or an explicit `resolve.defaults()`), or expose it via `layer(a, b) |> independent_y`.

**3. Decide, deliberately, between typed field access and spec-as-data. You probably cannot have both.** The single biggest thing a typed FP language can do that JSON Schema structurally cannot is kill the `field: String` category entirely:

```gleam
pub type Channel(row) {
  Quantitative(get: fn(row) -> Float, scale: ContinuousScale)
  Nominal(get: fn(row) -> String, scale: BandScale)
}
```

Accessor functions make field typos compile errors and eliminate the whole `datum.x` expression-string surface. The cost is exactly what Vega-Lite bought with strings: a chart is no longer serializable data, so you lose portability and you lose machine-enumerability — you cannot write Voyager over `fn(row) -> Float`. Recommendation: take the accessors, and keep `dict.Dict(String, Value)` as a supported `row` type so genuinely-unknown schemas degrade instead of blocking. State the tradeoff in your README rather than discovering it at v0.3.

**4. Sum types are enough; Gleam's gaps mostly don't bite.** No type classes means no `Scalable` interface — you get a `Scale` sum type and per-scale functions, closed to extension. That is *fine*: a grammar wants closure, and Vega-Lite's extensibility failures came from a monolithic compiler, not a closed grammar. Keep marks a closed ADT in v0.1; add a `Custom(fn(Scales, List(row)) -> svg.Element)` escape only once the core is stable, and note that the escape hatch being a *cliff* is Vega-Lite's most-cited practical complaint.

**5. Dual-target argues for splitting like Mosaic, not like Vega.** Do *not* build a reactive dataflow runtime. Make `render : Chart(row) -> String` pure and total — that's the BEAM/SSR path. Then implement selections in Lustre as `fn(Msg, Chart(row)) -> Chart(row)`: Elm-architecture updates that produce a new spec. Brushing and cross-filtering with zero dataflow machinery, one renderer shared by both targets. Steal `resolve`'s union/intersect/`_others` semantics for that layer verbatim; defer selections themselves past v0.1.

**6. Keep data requirements as values.** Mosaic's lesson: don't bake in-memory `List(row)` assumptions into the mark type. Represent bin/aggregate as a *description* so a future backend can push it to Postgres or DuckDB. Cheap now, impossible to retrofit.

**7. Error text is the product.** Vega-Lite's validator famously reports the *parent* property name (#8137). Name constructors so they read as grammar (`Layer`, `Resolve(Independent)`, `Color(Scheme(..))`) — a Gleam type error quoting your constructors beats a JSON Schema `anyOf` cascade, and costs only naming discipline.

## Sources

- Satyanarayan, Moritz, Wongsuphasawat, Heer. [*Vega-Lite: A Grammar of Interactive Graphics*](https://idl.cs.washington.edu/files/2017-VegaLite-InfoVis.pdf), InfoVis 2017 — formal tuples, view algebra, selections, compiler phases, limitations §7.
- Heer, Moritz. [*Mosaic: An Architecture for Scalable & Interoperable Data Views*](https://idl.cs.washington.edu/files/2024-Mosaic-TVCG.pdf), IEEE VIS 2024 — Coordinator/Client/Selection, critique of Vega-Lite's opaque internals, discussion of the transform/encoding partition. Project page: https://idl.uw.edu/papers/mosaic
- Satyanarayan, Russell, Hoffswell, Heer. [*Reactive Vega: A Streaming Dataflow Architecture*](https://idl.cs.washington.edu/files/2015-ReactiveVega-InfoVis.pdf), InfoVis 2016 — E-FRP signals, event selectors, unified streaming data model.
- Satyanarayan et al. [*Critical Reflections on Visualization Authoring Systems*](https://idl.cs.washington.edu/files/2019-ReflectionsVisAuthoring-InfoVis.pdf), InfoVis 2019 — the lab on expressivity/learnability tradeoffs.
- Moritz et al., [`vega/ts-json-schema-generator` issue #86, "Future of JSON schema for Vega and Vega-Lite"](https://github.com/vega/ts-json-schema-generator/issues/86) — intersection types, `additionalProperties: false`, exponential blowup, considering dropping JSON Schema.
- [`vega/vega-lite` issue #7149, "Revise whether to blend selection into parameter"](https://github.com/vega/vega-lite/issues/7149) — post-hoc doubt about the v5 unification.
- [`vega/vega-lite` issue #8137, "Schema validator logs incorrect property name"](https://github.com/vega/vega-lite/issues/8137) — the runtime-validation UX failure mode.
- [Vega-Lite debugging guide](https://vega.github.io/vega-lite/usage/debugging.html) — schema validity is step one of four.
- [Animated Vega-Lite](https://vis.csail.mit.edu/pubs/animated-vega-lite/) — "selections cannot alter visual encodings or data transformation pipelines at runtime."
