# Rendering & Output (the backend/scenegraph lineage)

## The vision (what this tradition believes a chart is)

The grammar lineage says a chart is a *specification*. The rendering lineage says a chart is a
**scenegraph**: a resolution-independent tree of positioned, styled primitives that exists
before any pixel or tag does. Drawing is then a fold over that tree into whatever surface you
have — Agg, Cairo, PDF, SVG string, DOM, canvas, an embosser for tactile printing.

matplotlib states this as three stacked layers — scripting, artist, backend — where "each layer
that sits above another knows how to talk to the layer below, but the lower layer is not aware
of the layers above." Vega compiles specs to a scenegraph, then hands it to a registered
renderer. `diagrams` normalises to an `RTree` with all measurements resolved to output units
before any backend sees it. Three unrelated communities converged on the same shape.

The dissent is D3: don't build a scenegraph, *transform the one the browser already has*.
Bostock/Ogievetsky/Heer call this "representational transparency" — expressiveness and
debuggability come from the DOM being inspectable in devtools and styleable with CSS. D3 won the
browser and lost everywhere else; the price is that D3 charts cannot render without a DOM, which
is why the JS charting ecosystem drags a headless Chrome around for server-side images.
**dapper is structurally on the scenegraph side of this argument and should say so.**

## Core abstraction

A scenegraph plus a *deliberately tiny* backend interface. matplotlib's key refactor (through
0.98) reduced the required renderer to essentially four methods:

```
draw_path(gc, path, transform)          # everything is a compound path
draw_image(gc, x, y, im)
draw_text(gc, x, y, s, prop, angle)
get_text_width_height_descent(s, prop)  # <-- the only method that ASKS a question
```

Note the asymmetry. Rendering is write-only except for **text measurement**. That single query
is where the whole architecture leaks: you cannot decide how much space the y-axis needs until
you know how wide `"1,250,000"` is in 11px Inter, and you cannot know that without a font engine.
So the pipeline is not a clean one-way fold; it contains a cycle:

```
scale domain -> tick values -> formatted strings -> measured widths
      ^                                                    |
      +---------- reserved margin -> scale range <---------+
```

Everything hard about chart rendering — axis title space, label collision, autosize, responsive
resizing, faceting — is that cycle.

## Unique contributions

- **Backend as data, not inheritance.** A new output target is a handful of functions, not a
  subclass hierarchy — matplotlib's `FigureCanvas`/`Renderer` split, Vega's `renderModule`
  registry, Plotters' backend crates.
- **Bundled fonts + pinned engine as a correctness strategy.** matplotlib ships DejaVu Sans and
  pins the FreeType version *because glyph rasterisation changes between versions and would break
  image-comparison tests*. Determinism chosen over fidelity — the key precedent for a
  snapshot-tested library.
- **Text measurement without a browser.** `vl-convert` runs Vega-Lite under embedded V8 but
  overrides Vega's text-width function with a Rust call into `usvg`/resvg — proving the DOM was
  never the requirement, a *font file* was.
- **Tick selection as optimisation, not heuristic.** Talbot/Lin/Hanrahan score candidate labelings
  on simplicity, coverage, density and legibility, optimising format, font size and orientation
  *simultaneously*. It is most of the gap between "professional" and "homemade".
- **Overlap resolution as declarative policy.** Vega's `labelOverlap: "parity" | "greedy"` turns a
  fiddly geometric problem into a one-word user choice.
- **Data reduction as a rendering concern.** M4 (first/last/min/max per pixel column) is
  *pixel-exact* for line charts at a known width; LTTB preserves visual shape in one O(n) pass.
  Both are parameterised by plot width — i.e. by layout.
- **Accessibility as generated semantics.** Highcharts derives ARIA, keyboard navigation, a data
  table and a downloadable SVG (for tactile embossing) from one model. Lundgard & Satyanarayan's
  four-level model says *what* to emit: L1 encodings/axes, L2 statistics/extrema, L3 perceptual
  trends, L4 domain context — blind readers rated L3 most useful, L4 least.

## Where it struggles

- **Server-side text metrics are still broken in the state of the art.** Vega issue #2940: the
  same string measures 44px on a raster node-canvas and 40.5px on an SVG canvas; Vega always
  instantiates the raster one; node-canvas locks measurement to whichever type was created first.
  Open for years. With no node-canvas at all, Vega falls back to a crude per-character estimate
  and axis layout visibly breaks.
- **The layout cycle resists a clean solution.** Vega's `autosize: "fit"` is a second pass,
  notorious for interacting badly with signals and padding. Nobody has a principled fixpoint.
- **Two render paths drift.** An SVG-string path plus a DOM path means testing one and shipping
  two.
- **Client fonts are unknowable.** Perfect server measurement is still wrong if the viewer lacks
  the font. The only real fixes are embedding the font or converting text to paths — the latter
  destroys selectability and screen-reader access.
- **Elegant backend polymorphism has a real tax.** `diagrams`' `Backend b v n` class with
  existential `Prim` and a `Renderable` bridge is beautiful and yields famously unreadable type
  errors — elegance users hated.
- **Canvas discards accessibility and hit-testing**; you rebuild both by hand. WebGL discards
  text, so nearly every WebGL chart draws marks in GL and axes in DOM — two coordinate systems to
  keep in sync, which is where the bugs live.
- **"Responsive" usually means "scaled".** `width:100%` on an SVG scales the type too. Real
  responsiveness needs re-layout, hence re-measurement, hence a client round-trip.
- **Faceting forces shared scales.** Vega-Lite and Observable Plot both draw steady complaints
  that per-facet independent scales are awkward or impossible.

## Implications for dapper

1. **Make the scenegraph a public type.** `Scene` is the seam between grammar and output; the
   renderers are then two pure functions, `scene.to_svg_string : Scene -> String` and
   `scene.to_lustre : Scene -> Element(msg)`. Gleam has no type classes and needs none here — a
   plain function per target *is* the backend interface. Do **not** build a `Backend` record of
   functions until a third target exists (`diagrams` is the cautionary tale).
2. **Invert text metrics into a value, not an effect.** The one decision that determines whether
   dapper works on the BEAM at all:
   ```gleam
   pub type Metrics {
     Metrics(advance: fn(String, Font) -> Float, ascent: fn(Font) -> Float,
             descent: fn(Font) -> Float)
   }
   ```
   Ship `dapper/metrics/embedded`: a compiled-in advance-width table (upem 1000) for one sans and
   one mono family, summed per codepoint, no kerning, with a per-class fallback (digit /
   lowercase / uppercase / punctuation) for unknown codepoints. Use tabular digits so numeric
   labels measure exactly.
3. **Default to the embedded table on *both* targets.** Do not reach for canvas `measureText` on
   JS by default — identical metrics on BEAM and JS means one snapshot suite covers both and the
   two render paths cannot drift. Offer canvas-backed `Metrics` as opt-in. This is matplotlib's
   pinned-FreeType lesson.
4. **Own the font declaration.** Emit an explicit `font-family` naming the family you shipped
   metrics for, plus a fallback stack. Never inherit ambient CSS for measured text.
5. **Bound the layout cycle at two passes**: `ticks -> format -> measure -> reserve margins ->
   re-range -> re-tick -> stop`. Do not iterate to a fixpoint; autosize is the warning.
6. **Implement extended-Wilkinson tick selection in v0.1.** ~100 lines of pure scoring over
   candidate `q` values, with the legibility term consuming the `Metrics` you already have.
   Highest quality-per-line item in the plan.
7. **Model overlap as a variant**: `LabelOverlap(Show | Parity | Greedy)`, resolved during layout
   from measured widths. Free in an ADT language; a config bag in JS ones.
8. **Emit accessibility at string-construction time** — free there, unretrofittable later.
   Always `role="img"`, `<title>`, and a level-1 `<desc>` (mark type, encodings, axis ranges,
   units) derivable from the spec alone. Opt-in: level-2 extrema/range/correlation from
   aggregates the scales already computed, plus a sibling `<table>`. Never fabricate L3/L4.
9. **Make CVD-safety a type.** Fill the `color` channel only from a named `Scheme`, with a
   CVD-safe categorical default and variants encoding categorical/sequential/diverging intent, so
   a categorical palette cannot be applied to a quantitative field.
10. **Columnar input; reduction as a transform.** Take parallel typed columns, not `List(Dict)` —
    the BEAM penalises a map per row, and it lines up with Arrow later. Expose `bin`, `aggregate`
    and explicit `downsample(M4(pixel_width))` / `downsample(LTTB(n))`. M4 is the principled
    default for lines: pixel-exact at a known plot width, so it belongs *after* layout.
11. **Facet as a Scene combinator** with explicit `ScaleResolve(Shared | Independent)` per
    channel — the complaint both Vega-Lite and Plot attract, fixed by a one-word ADT choice.
12. **Defer animation, keep the option**: attach a stable key (facet, series, datum index) to
    every emitted mark now, so a Lustre keyed diff can animate later.
13. **Refuse canvas, WebGL and headless browsers for v0.1.** The whole claim is that
    `render : Chart -> String` is a pure BEAM function. ~10k marks of SVG is fine; beyond that the
    answer is a transform, not a new backend.

## Sources

- Hunter & Droettboom, "matplotlib", *The Architecture of Open Source Applications, Vol. 2* — https://aosabook.org/en/v2/matplotlib.html
- "Fonts in Matplotlib" (bundled DejaVu, pinned FreeType for image tests) — https://matplotlib.org/stable/users/explain/text/fonts.html
- Bostock, Ogievetsky & Heer, "D³: Data-Driven Documents", InfoVis 2011 — http://vis.stanford.edu/files/2011-D3-InfoVis.pdf
- Vega View API (renderer types, headless mode, node-canvas) — https://vega.github.io/vega/docs/api/view/
- Vega issue #2940, server-side SVG text measurement inaccuracy — https://github.com/vega/vega/issues/2940
- Vega issue #2396, "Improve font metrics" — https://github.com/vega/vega/issues/2396
- vl-convert (Vega-Lite → SVG/PNG with usvg-based text measurement, no browser) — https://github.com/vega/vl-convert
- Talbot, Lin & Hanrahan, "An Extension of Wilkinson's Algorithm for Positioning Tick Labels on Axes", InfoVis 2010 — http://vis.stanford.edu/files/2010-TickLabels-InfoVis.pdf
- Steinarsson, "Downsampling Time Series for Visual Representation" (LTTB), MSc thesis 2013 — https://skemman.is/bitstream/1946/15343/3/SS_MSthesis.pdf
- Jugel et al., M4 pixel-exact aggregation; survey context in "Data Point Selection for Line Chart Visualization" — https://arxiv.org/pdf/2304.00900
- Lundgard & Satyanarayan, "Accessible Visualization via Natural Language Descriptions: A Four-Level Model of Semantic Content", IEEE VIS 2021 — https://vis.csail.mit.edu/pubs/vis-text-model/
- Highcharts Accessibility module feature overview — https://www.highcharts.com/docs/accessibility/accessibility-module-feature-overview
- `Diagrams.Core.Types` (Backend class, `renderRTree`, existential `Prim`) — https://hackage.haskell.org/package/diagrams-core/docs/Diagrams-Core.html
- Plotters (Rust): pluggable backends, `ab_glyph` font registration for text without system fonts — https://github.com/plotters-rs/plotters
- Observable Plot facets / shared-scale limitation discussion — https://github.com/observablehq/plot/discussions/874
