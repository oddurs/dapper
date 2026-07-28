# D3 and Observable Plot

## The vision (what this tradition believes a chart is)

D3's founding claim is that **a chart is not a thing**. It is a transformation of a document by
data. The 2011 paper rejects the toolkit tradition it came from: "D3 is not a traditional
visualization framework. Rather than introduce a novel graphical grammar, D3 solves a different,
smaller problem: efficient manipulation of documents based on data."

The principle is *representation transparency*: "Rather than hide the underlying scenegraph within
a toolkit-specific abstraction, D3 enables direct inspection and manipulation of a native
representation." The case against Protovis/Prefuse-style abstract marks is a usability case — an
intermediate scenegraph costs compatibility (CSS, fonts, dev tools), expressiveness (you can only
draw what the toolkit modelled), and above all debuggability: "internal structures are exposed only
when errors arise, often at unexpected times."

The second half of the vision is anti-taxonomic. Bostock: elegant design needs "a theory of
graphics, not charts," the alternative being "the tyranny of charts." D3's docs still say: "It has
no concept of 'charts'. When you visualize data with D3, you compose a variety of primitives."

Observable Plot is the same author conceding that composition-from-primitives is too expensive for
most work. D3's docs now carry the post-mortem in Amanda Cox's words — "Use D3 if you think it's
perfectly normal to write a hundred lines of code for a bar chart" — and route users away. Plot
keeps the anti-taxonomy ("Plot doesn't have chart types; instead, you construct charts by layering
marks") but adds what D3 refused: inference. "If you specify the semantics — your data and the
desired encodings — Plot will figure out the rest."

## Core abstraction

Three, in historical order, and only the middle one is worth porting.

1. **The data join** (D3). `selection.data(values, key)` is a keyed diff partitioning a selection
   into *enter* (unbound data), *update* (matched), *exit* (unbound elements): "you handle these
   three states without any branching (`if`) or iteration (`for`)." A virtual-DOM reconciler from
   2011, before React, expressed as a set operation.

2. **The pure encoding math**, extracted as standalone modules in D3 v4. A scale is "a function
   that takes an *abstract value* of data … and returns a *visual value*", most of them invertible
   ("you can invert the mapping … facilitating interaction"). A shape generator is a function from
   data to path commands, *parameterised by a rendering context* — no context yields an SVG path
   string, a context yields `moveTo`/`lineTo` calls. Curves are a pluggable streaming interface.
   Time intervals are an algebra (`floor`/`ceil`/`offset`/`range`/`count`/`every`) from which
   time-axis ticks fall out.

3. **The mark** (Plot). A mark is (data, channels, options) → SVG; a plot is a list of marks that
   *share* inferred scales. Transforms (`bin`, `group`, `stack`, `window`, `dodge`, `normalize`, …)
   are options-to-options functions that compose before the mark sees them.

## Unique contributions

- **The join as a declarative diff**, and debuggability as a first-class design axis: "immediate
  evaluation of operators further simplifies debugging and allows iterative development."
- **Decomposing the grammar of graphics into ordinary math libraries.** `d3-scale`, `d3-shape`,
  `d3-array`, `d3-time`, `d3-hierarchy`, `d3-force` outlived D3 itself: Plot, Vega and nearly every
  React chart library are built on them. This is the durable payload.
- **The 1–2–5 tick algorithm.** `ticks(start, stop, count)` returns values that are "a power of ten
  multiplied by 1, 2 or 5", selected via the constants `e10 = √50`, `e5 = √10`, `e2 = √2`.
- **Band scale as closed-form geometry** rather than a layout pass:
  `step = (stop − start) / max(1, n − paddingInner + paddingOuter × 2)`,
  `bandwidth = step × (1 − paddingInner)`, with `align` distributing outer padding.
- **Plot's transforms-inside-the-spec**, which "accelerates what is often the most onerous task in
  visualization: getting data into the right shape."

## Where it struggles

- **The join is the hardest idea in dataviz pedagogy.** Bostock added `selection.join()` in D3 5.8
  to hide `enter`/`exit`/`merge`. Needing a facade over your central abstraction is an admission.
- **D3 is an imperative mutation API wearing declarative clothes** — `this`, `(d, i, nodes)`
  callbacks, stringly-typed attributes, method chaining as pseudo-configuration. It resists static
  typing so badly that `@types/d3` is a running joke.
- **"Towards Reusable Charts" (2012) failed.** Closures with getter/setters invoked via
  `selection.call(chart)` was offered as a "strawman convention" for composable charts; the
  ecosystem produced incompatible half-libraries instead of a component market. A low-level kernel
  with no composition law does not converge.
- **Duck-typed interfaces everywhere.** A scale is a function with properties bolted on: `invert`
  exists on continuous scales and not band, `bandwidth` only on band, `ticks` only on some — each a
  runtime `undefined` where a type could have said no.
- **Plot's inference is magic that fails quietly.** "Inference is based solely on the first
  non-null, non-undefined value" — one stray string and you silently get an ordinal axis. Its
  compatibility rules are runtime rules too: "barY requires that the x scale is a band scale."
- **Plot is stateless by design and thin on interaction.** No incremental re-render outside render
  transforms; brushing, zoom/pan and declarative animation are all still "planned". Official advice
  is "throw away an old plot and replace it with a new one" and let a reactive host own state.
  Aisch's field report: superb for exploration, but production interactives hit dead ends and get
  rewritten in D3.
- **Conciseness is bought with implicitness.** Plot is short *because* it guesses. Making the
  grammar explicit inherits D3's verbosity problem unless you also ship defaults.

## Implications for dapper

1. **Port the math, not the interface.** Take `d3-scale`, `d3-shape` curves, `d3-array` ticks,
   `d3-time` intervals. Do not port selections, the data join, transitions or the reusable-chart
   closure pattern — Lustre's VDOM already owns reconciliation, and `Chart -> Element(msg)` is a
   better answer to that problem than `enter`/`exit`/`merge`.
2. **Model `Scale` as a closed sum type, not a record of functions.** No type classes means no
   polymorphic scale interface — take that as a feature. The closed set *is* the grammar, and
   closedness is what the compiler checks; you also get exhaustive matching, structural equality and
   serialisability. Cost: no user-defined scale types. Accept it at v0.1.
3. **Make D3's partiality total by splitting types, not by phantom parameters** (phantoms buy little
   without HKTs). Put `invert`/`ticks` on the continuous type, `bandwidth`/`step` on the band type,
   and let `bar` *require* a band scale on its categorical axis. That one constructor signature
   converts Plot's most common runtime error into a compile error — the cheapest demonstration of
   the wedge available.
4. **Invert Plot's inference from values to types.** Plot infers scale type from the first data
   value; dapper should infer from the channel's Gleam type — `Channel(Float) → continuous`,
   `Channel(String) → band`, `Channel(Time) → time`. Ordinary generics, no HKTs required.
5. **Copy the generator/context split — it answers the dual-target problem.** Marks must not emit
   strings. Emit a `Scene` of resolved primitives (`Path(List(PathCommand))`, `Text`, `Rect`) with
   geometry already computed; the BEAM string renderer and the Lustre renderer are then two
   interpreters of one value, and snapshots assert on geometry, not string formatting. Plot gave
   this up when it committed to producing DOM. The cross-target risk is not float math (both targets
   are IEEE-754 doubles) but float-to-string formatting — pin your own formatter.
6. **Budget for `d3-time` properly.** Interval-as-a-record (`floor`, `offset`, `count`) with
   `ceil`/`range`/`every` derived is the whole reason D3's time axes look right. Gleam's stdlib has
   no calendar; that decision is the largest hidden cost on the v0.1 list and it leaks into the
   scale API. Settle it before `Scale` hardens.
7. **README open question 1: take Plot's answer minus its hole.** Tidy row-oriented data with
   channels as *accessor functions* — `x: fn(row) -> Float` — idiomatic Gleam, and it closes the
   stringly-typed gap (`x: "weight"`) Plot leaves open. Column-oriented buys throughput you do not
   need and destroys the accessor story.
8. **Open question 2: type the structure, default the cosmetics.** Type mark/channel/scale
   compatibility; default padding, palette, tick count, margins. Ship a thin opinionated constructor
   layer over a public typed core, or dapper reproduces D3's verbosity with none of D3's power.
9. **Publish the modules as independently usable, per D3 v4's best decision.** Someone should be able
   to use `dapper/scale` + `dapper/shape` with hand-written Lustre and never touch the mark layer.
   Plot's failure mode — hit the wall, rewrite from scratch — is avoided only if the layer below is
   a supported product, not an implementation detail.

## Sources

- Bostock, Ogievetsky, Heer, [*D3: Data-Driven Documents*, InfoVis 2011](https://vis.csail.mit.edu/classes/6.859/readings/pdfs/Bostock-D3.pdf) — design goals, representation transparency, the Protovis critique.
- Bostock, [*Thinking with Joins*](https://bost.ocks.org/mike/join/) (2012); [*Towards Reusable Charts*](https://bost.ocks.org/mike/chart/) (2012).
- Bostock, [*Introducing d3-scale*](https://medium.com/@mbostock/introducing-d3-scale-61980c51545f) (2016) — "a theory of graphics, not charts".
- Bostock, [*What Makes Software Good?*](https://medium.com/@mbostock/what-makes-software-good-943557f8a488) (2017) — parsimony, no modal behaviour, no overloaded meaning.
- [*What is D3?*](https://d3js.org/what-is-d3) — "no concept of charts"; the Amanda Cox line; the explicit recommendation to use Plot instead.
- [*Why Plot?*](https://observablehq.com/plot/why-plot), [Marks](https://observablehq.com/plot/features/marks), [Scales](https://observablehq.com/plot/features/scales), [Transforms](https://observablehq.com/plot/features/transforms), [Interactions](https://observablehq.com/plot/features/interactions); [*Introducing Observable Plot*](https://observablehq.com/blog/introducing-observable-plot) (2021).
- d3 source: [`d3-array/src/ticks.js`](https://github.com/d3/d3-array/blob/main/src/ticks.js), [`d3-scale/src/band.js`](https://github.com/d3/d3-scale/blob/main/src/band.js), [d3-shape](https://d3js.org/d3-shape).
- Gregor Aisch, [*Review of Observable Plot*](https://www.vis4.net/blog/2023/09/observable-plot-review/) (2023) — strongest independent critique of Plot's interaction/customisation ceiling.
- Wickham, *A Layered Grammar of Graphics* (2010); Wilkinson, *The Grammar of Graphics* (2005) — the tradition D3 declined and Plot re-adopted.
