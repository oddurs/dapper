# React component charting (Recharts, visx, Victory, nivo, shadcn/ui charts)

## The vision (what this tradition believes a chart is)

A chart is **not a specification**. It is a *region of the UI component tree*. This lineage's
founding bet is that composition has already been solved — by React — and a charting library
should not invent a second composition mechanism. Where Vega-Lite says "describe the chart as
data, we'll render it," this tradition says "the tree *is* the description; render it the way you
render everything else."

The payoff is that charts inherit the host framework for free: reconciliation, keys, event
delegation, SSR, theming, dev tools, and — crucially — the user's own components living *inside*
the chart. A tooltip is a div. An annotation is JSX. There is no "escape hatch" because there is
no cage.

The tradition splits on how much to pre-assemble. visx is explicit that it is
["not a charting library"](https://github.com/airbnb/visx) — "as you start using visualization
primitives, you'll end up building your own charting library that's optimized for your use case."
Recharts/Victory/nivo are batteries-included. shadcn/ui takes the position to its logical end:
charts are *source you copy into your repo*, and "we do not wrap Recharts... you're not locked
into an abstraction."

A second shared conviction, stated most sharply by visx: **D3 for the math, React for the DOM**,
because "two mental models for updating the DOM opens the door for bugs to sneak in." Scales,
path generators, tick algorithms are pure functions; only React touches nodes. That split is
directly reusable by dapper.

## Core abstraction

The real abstraction is not the component — it is the **invisible chart context**: a parent that
owns dimensions + scales + interaction state, and children that read from it. Every library in
the lineage converged on this, by four different mechanisms:

- **Victory**: `VictoryChart` *clones* its children via `React.cloneElement`, injecting `domain`,
  `scale`, `standalone`, `theme`. Children must be "Victory-aware."
- **visx/xychart**: "modularized React.context layers for scales, canvas dimensions, data, events,
  and tooltips" — the wrapper "largely equates to managing shared state across the elements."
- **Recharts v3**: a *per-chart Redux store* (`createRechartsStore`). Children no longer get
  introspected; they are registration components (`RegisterGraphicalItemId`,
  `SetCartesianGraphicalItem`, `SetTooltipEntrySettings`) that `dispatch` their settings in
  `useEffect`. Geometry is then derived by selectors (`getTicksOfAxis`, `useOffsetInternal`).
- **nivo**: props-down, with SVG/Canvas/HTML variants of each chart and an SSR HTTP API — the
  author's stated motivation was that "just a few [libraries] provide server side rendering
  ability and fully declarative charts."

The tell is Recharts v3: after a decade, the component tree stopped being the model and became a
*builder for an implicit spec* held in a store. The tree was always a spec in disguise.

## Unique contributions

1. **Primitives as the reusable unit, not charts.** visx's packaging (`@visx/scale`,
   `@visx/shape`, `@visx/axis`, `@visx/tooltip`, `@visx/brush`, `@visx/zoom`) says the durable
   artifact is a scale and a path generator, not a `BarChart`.
2. **Interaction as composable objects.** Brush, zoom, voronoi hit-testing are things you *add to*
   a chart (Victory's `VictoryBrushContainer`/`VictoryVoronoiContainer`, `@visx/brush`), not modes
   you configure. Interaction is part of the grammar, not a callback bolted on.
3. **Declarative event→mutation tables.** Victory's `events` prop addresses rendered elements by
   `(childName, target, eventKey)` and handlers return *mutations* — prop deltas, not imperative
   DOM writes. It is TEA smuggled into React.
4. **Presentation metadata as a third value.** shadcn's `ChartConfig` splits series *meaning* from
   data and from marks: `{ desktop: { label, icon, color, theme: { light, dark } } }`, with colors
   as CSS variables. Simple, and the best-aged idea in the lineage.
5. **Multi-target rendering taken seriously** (nivo: SVG/Canvas/HTML + SSR).

## Where it struggles

**The tree is a grammar with no type checker.** Recharts classified children by component
identity, so wrapping `<Bar>` or `<YAxis>` in your own component makes them *silently vanish*
(issues [#412](https://github.com/recharts/recharts/issues/412),
[#2788](https://github.com/recharts/recharts/issues/2788),
[#3416](https://github.com/recharts/recharts/issues/3416)) — the library checked for
`item.type.getComposedData`. Victory's `cloneElement` has the same shape of failure from the other
direction: any wrapper swallows the injected props. TypeScript cannot express "an `XAxis` is only
meaningful inside a Cartesian chart" or "this `stackId` refers to a compatible mark." **This is
Vega-Lite's runtime-schema problem relocated into JSX, and it fails more quietly.**

**Measurement is a DOM side effect.** Text metrics are only knowable at render time, so Recharts
mounts a hidden `<span>`, styles it, and calls `getBoundingClientRect()`
(`DOMUtils.getStringSize`). Consequences: it dominates render time (~40,000 calls for a 10k-point
chart), returns 0 width in some environments
([#224](https://github.com/recharts/recharts/issues/224)), leaks spans
([#1169](https://github.com/recharts/recharts/issues/1169)), and trips CSP. Layout is therefore
*emergent*, not computed — which is why every library in this lineage makes you hand-tune
`margin`.

**Responsiveness needs a two-pass render.** `ResponsiveContainer`/`ParentSize` render once at zero,
observe, re-render. It requires a definitely-sized parent (shadcn's docs must instruct users to add
`min-h-*` or `aspect-*`), and breaks unevenly in flex/grid
([#2251](https://github.com/recharts/recharts/issues/2251)).

**Cross-cutting state doesn't fit a tree**, hence the reinvented stores above. Recharts' v3
"register via `useEffect` dispatch" means the chart model is assembled by side effects *during*
render — order-sensitive, awkward to SSR, awkward to test.

**Low-level regrows high-level.** visx's own README concedes its packages "are (by design)
low-level and modular which maximizes their flexibility, but also requires more work to create
even simple charts" — hence `@visx/xychart`. And batteries-included ages into weight: Victory
pulls `victory-core` + lodash for one line ([#202](https://github.com/FormidableLabs/victory/issues/202),
[#547](https://github.com/FormidableLabs/victory/issues/547)).

## Implications for dapper

1. **Do not make the Lustre element tree the grammar.** Make the chart an opaque typed value and
   make Lustre + SVG-string two *renderers* of it. This deletes the Recharts introspection class
   of bug outright: a user helper returning a `Mark` composes by construction.
   ```gleam
   pub opaque type Chart(msg) {
     Chart(x: Scale, y: Scale, marks: List(Mark), meta: Dict(String, SeriesMeta),
           on: List(Interaction(msg)))
   }
   // dapper/lustre.view : Chart(msg), State, Size -> Element(msg)
   // dapper/svg.render  : Chart(msg), Size -> String
   ```
   Required channels live in the constructor (`Bar(x:, y:, fill: Option(_))`), so the compiler
   enforces what Vega-Lite's schema and Recharts' `displayName` check enforce at runtime.
2. **Text measurement must be a pure injected function**, because BEAM has no DOM.
   `type Measure = fn(String, Font) -> Size`. Default: a bundled advance-width table for two or
   three font stacks; on the JS target let callers swap in a canvas-backed measurer. Memoize by
   `(string, font)` — Recharts' perf post-mortem is the warning.
3. **Layout is a pure function, not an emergent property.** `layout(chart, measure, Size) -> Frame`
   derives margins from measured ticks. Then SSR passes a `Size` explicitly, and in Lustre the
   size arrives as a `Msg` from one `Effect` wrapping `ResizeObserver` — no render-prop, no
   two-pass, no `min-h` folklore.
4. **State: TEA already gives you Recharts v3's store — don't ship your own.** Expose
   `ChartState` + `update(ChartState, ChartMsg) -> ChartState` and keep it in the *user's* model.
   Steal Victory's addressing (`series_id`, `datum_index`) but as typed messages
   (`HoverDatum(String, Int)`), not prop mutations, and let the user's `update` decide.
5. **Steal `ChartConfig`.** `Dict(String, SeriesMeta)` with `label`, `color: Literal(String) |
   CssVar(String)`, and a light/dark pair — one chart value, both themes, no recompile.
6. **Ship both layers in v0.1**, since the visx→xychart arc is inevitable: `dapper/primitive`
   (scales, tick generation, path data, axis geometry returned *as data*) under a batteries
   `dapper` API. Snapshot-test the primitive layer; it has no DOM.
7. **Gleam constraints are a feature here.** No type classes → make `Scale` a closed ADT
   (`Linear`/`Log`/`Time`/`Band`) with `scale(Scale, Value) -> Float`; exhaustiveness then flags
   every site that must handle a new scale. No HKTs → don't chase a polymorphic `Scale(a)`;
   monomorphize per mark.
8. **Avoid:** a `Dynamic`/`props`-bag escape hatch (that *is* runtime validation, re-added); a
   Victory-style common-props record that every constructor must thread; and requiring users to
   supply margins.

## Sources

- Chris Williams & Harrison Shoff, ["Introducing visx from Airbnb"](https://medium.com/airbnb-engineering/introducing-visx-from-airbnb-fd6155ac4658), Airbnb Tech Blog
- [airbnb/visx README](https://github.com/airbnb/visx) and [@visx/xychart README](https://github.com/airbnb/visx/blob/master/packages/visx-xychart/README.md) / [RFC #734](https://github.com/hshoff/vx/issues/734)
- [Recharts v3.0.0 release discussion](https://github.com/recharts/recharts/discussions/5984) and [3.0 migration guide](https://github.com/recharts/recharts/wiki/3.0-migration-guide)
- [Recharts chart generation & component lifecycle](https://deepwiki.com/recharts/recharts/2.1-chart-generation-and-component-lifecycle) (Redux store, registration components, selectors)
- Bernardo Belchior, ["Improving Recharts performance"](https://belchior.me/blog/improving-recharts-performance) — `getStringSize` cost analysis; [PR #3953](https://github.com/recharts/recharts/pull/3953)
- Recharts issues [#224](https://github.com/recharts/recharts/issues/224), [#412](https://github.com/recharts/recharts/issues/412), [#1169](https://github.com/recharts/recharts/issues/1169), [#2251](https://github.com/recharts/recharts/issues/2251), [#2788](https://github.com/recharts/recharts/issues/2788), [#3416](https://github.com/recharts/recharts/issues/3416)
- [Victory docs — common props](https://nearform.com/open-source/victory/docs/common-props/) and [victory-chart source](https://github.com/FormidableLabs/victory/blob/main/packages/victory-chart/src/victory-chart.tsx) (`cloneElement` prop injection); bundle-size issues [#202](https://github.com/FormidableLabs/victory/issues/202), [#547](https://github.com/FormidableLabs/victory/issues/547), [#656](https://github.com/FormidableLabs/victory/issues/656)
- [nivo — About](https://nivo.rocks/about/) (SSR + declarative motivation, SVG/HTML/Canvas variants)
- [shadcn/ui — Chart](https://ui.shadcn.com/docs/components/base/chart) (`ChartContainer`, `ChartConfig`, CSS-variable theming, "we do not wrap Recharts")
