# dapper

A grammar-of-graphics charting library for Gleam. Type-checked encodings, SVG output,
one codebase for server-rendered charts on the BEAM and interactive Lustre components
in the browser.

## Why this exists

Searching the Gleam package index for "chart" returns exactly one result:
`fishgirl 1.0.0-incomplete` — "Mermaid charts in a Lustre component. Currently mostly
for my own use." There is no charting story in Gleam at all, while Lustre is the
ecosystem's fastest-moving framework and every dashboard built with it needs one.

## Prior art to learn from

| Library | What to take |
|---|---|
| [Vega-Lite](https://vega.github.io/vega-lite/) | The encoding grammar: mark + channel + scale + transform. The right conceptual model. |
| [Observable Plot](https://observablehq.com/plot/) | Ergonomics — sensible defaults so a basic chart is three lines. |
| [Recharts](https://recharts.org/) | Component API shape for the Lustre side. |
| [D3](https://d3js.org/) | Scale and axis math. Don't copy the API; do copy `d3-scale`. |

## The wedge

**`render : Chart -> String` is pure and total on the BEAM.** No DOM, no headless
browser, no font engine — and the same `Chart` value renders as an interactive Lustre
component in the browser. Nobody has this. It is why the JavaScript ecosystem drags a
headless Chrome around for server-side images; nivo built an SSR HTTP service and
ECharts a dedicated SSR mode to approximate it.

Secondary, and stated honestly: no field names, no optional-field merge semantics, no
forgotten cases, and mark constructors that state their channels. dapper does **not**
claim compiler-checked chart *validity* — a grammar rules out ungrammatical charts, not
misleading ones. Semantics live in a total `validate(Chart) -> List(Diagnostic)` beside
a total `render`.

An earlier version of this README claimed compile-time grammar checking as the primary
wedge, on the grounds that Vega-Lite validates at runtime. That was wrong — Vega-Lite is
written in TypeScript and its JSON Schema is a derived artifact. See
[decision 0001](docs/decisions/0001-positioning.md).

**Accepted cost:** no serialisable spec. Accessor closures and JSON portability are an
either/or, and accessors win. This forfeits cross-language portability, machine
enumerability, and "generate on the server, store in a database, render anywhere."
`Dict(String, Value)` remains a legal `row`.

## v0.1 scope

Deliberately small. Ship one chart type end-to-end before generalising. Full
sequencing is in [`docs/plan.md`](docs/plan.md).

- [x] `dapper/format` — the one place a `Float` becomes a `String`
- [x] `dapper/geom` — rectangles as interval endpoints
- [x] `dapper/ticks` — d3's 1–2–5 algorithm, checked against generated fixtures
- [x] `dapper/scale` — linear, log, band, point, ordinal, and domain training
- [ ] `dapper/metrics` — embedded font advance table, identical on both targets
- [ ] `Scene` and the SVG emitter
- [ ] `Mark` — bar, then line and point
- [ ] Encoding channels — x, y, colour
- [ ] Axes, gridlines and label collision avoidance
- [ ] `dapper_lustre` — the same `Scene` as Lustre elements

## Non-goals for v0.1

**Time scales are cut to v0.2** (decision S7). The interval algebra is 60–80
hours on its own, which is the difference between a shippable v0.1 and a
fictional schedule. Until then, pass epoch seconds through a continuous channel
and get numeric labels. `ContinuousKind` reserves the variant inside an opaque
type, so adding time later is not a breaking change.

Also out: extended-Wilkinson tick selection (its legibility term needs text
metrics, which would create exactly the ticks-to-layout fixpoint the two-pass
layout bound exists to forbid), faceting beyond a 1×1 pane grid, statistical
transforms, sequential and diverging colour schemes, animation, interactivity,
geo projections, WebGL and streaming data.

Two renderers, one `Scene` — **not** "shared code". They are two independent
folds over a shared intermediate, held equal by a test.

## Resolved

The kickoff's three open questions are settled — see
[decision 0001](docs/decisions/0001-positioning.md) and [prior art](docs/prior-art.md).

1. **Data shape** → row-oriented `List(row)` with accessor channels. Columnar forces
   string field names back into the API.
2. **How typed is too typed** → compatibility encoded as *arity*, not as a predicate.
   `bar(x: Discrete(row), y: Continuous(row), …)`.
3. **Theming** → a typed `Scheme` whose variants encode categorical/sequential/diverging
   intent, CVD-safe, colours as `Literal | CssVar` with a light/dark pair.

## Documentation

- [`docs/prior-art.md`](docs/prior-art.md) — synthesis of nine charting lineages
- [`docs/research/`](docs/research/) — the underlying briefs
- [`docs/decisions/`](docs/decisions/) — accepted decisions

## Status

Kickoff. Research complete, nothing implemented yet.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
