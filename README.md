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

Vega-Lite validates its grammar with a JSON Schema **at runtime** — you find out a
channel is invalid for a mark when the chart fails to render. In Gleam the same
grammar is checked by the compiler.

Second wedge: Gleam compiles to both Erlang and JavaScript. The same chart definition
renders to a static SVG string server-side (emails, reports, PDFs, no headless browser)
and hydrates into an interactive Lustre component client-side. No other charting
library gets this for free.

## v0.1 scope

Deliberately small. Ship one chart type end-to-end before generalising.

- [ ] `Scale` — linear, log, time, band/ordinal. Port `d3-scale` semantics.
- [ ] `Mark` — bar, line, point only.
- [ ] Encoding channels — x, y, color.
- [ ] SVG renderer targeting a string (Erlang) and Lustre elements (JS) from shared code.
- [ ] Axes with tick generation and label collision avoidance.
- [ ] Snapshot tests via [birdie](https://hexdocs.pm/birdie/) over rendered SVG.

## Non-goals for v0.1

Animation, interactivity/tooltips, faceting, geo projections, WebGL, streaming data.
All are v0.2+ once the grammar has settled.

## Open questions

1. **Data input shape.** `List(Row)` with a decoder, or a column-oriented struct?
   Column-oriented is faster and matches Vega-Lite; row-oriented is more idiomatic
   Gleam. Decide before the scale API hardens — it leaks everywhere.
2. **How typed is too typed?** Enforcing mark/channel compatibility in the type system
   may produce error messages worse than the bugs they prevent. Prototype the hostile
   case before committing to it.
3. **Theming.** Bake in a palette or require the caller to supply one? Accessible
   defaults in both light and dark are table stakes.

## Status

Kickoff. Nothing implemented yet.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
