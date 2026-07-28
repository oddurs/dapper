# Grammar of Graphics (Wilkinson 1999 → Wickham's layered grammar / ggplot2)

## The vision (what this tradition believes a chart is)

A chart is not a *type*. "Scatterplot", "histogram", "pie chart" are not primitives — they are
accidental names for points in a parameter space. Wickham's opening ambition is to "move beyond
named graphics (e.g., the 'scatterplot') and gain insight into the deep structure that underlies
statistical graphics."

The consequence is deliberately unsettling: the grammar generates charts nobody has a name for.
Wickham's bullseye chart ("we also *accidentally* created an unusual chart") is offered as
evidence the decomposition is correct. A pie chart is a stacked bar in polar coordinates. A
histogram is `bin` + `bar` and "does not contain the word histogram: a histogram is not
elemental."

Wilkinson's original vision was more mathematical: a graphic is the terminal stage of a
**pipeline** — `Source → Variable → Algebra → Scales → Statistics → Geometry → Coordinates →
Aesthetics → Renderer`. Data flows one way; each stage is total and independent. His `Algebra`
(`cross *`, `nest /`, `blend +` over *varsets*) let the specification itself restructure the
data. ggplot2 dropped it — the single most consequential edit in the lineage.

## Core abstraction

**The layer.** Wickham's reparameterisation is the whole contribution: he took Wilkinson's
`ELEMENT`, in which "all the parts of an element are intertwined," and split it into five
independent slots that can each default:

```
layer  = data × aesthetic mapping × stat × geom × position
plot   = default data+mapping
       + [layer]                  -- one or more
       + one scale per aesthetic used
       + coordinate system
       + facet spec
```

Two properties make it work. First, **components are orthogonal**: "you can generally change a
single component in isolation." Second, a **hierarchy of defaults** collapses the verbosity —
"every geom has a default statistic, and every statistic a default geom," so `geom_histogram()`
expands to `layer(geom="bar", stat="bin", mapping=aes(y=..count..))`.

A scale is defined as "a function, and its inverse, along with a set of parameters." The inverse
is not decoration — it *is* the axis/legend. Guides are derived, never authored: "guides are
either axes (for position scales) or legends (for everything else)."

## Unique contributions

**Stats as a first-class stage.** The underrated idea: a chart may *compute* its data before
drawing — not as preprocessing, but as part of the spec, re-run when the spec changes. Wickham
imposes a real constraint: "to make sense in a graphical context a stat must be location-scale
invariant: f(x+a) = f(x)+a and f(b·x) = b·f(x)." The payoff is that `bin`/`smooth`/`density`
compose against *any* geom, so a frequency polygon is not a feature — it is `bin` + `ribbon`.

**The stat→geom contract.** "The boxplot geom requires the position of the upper and lower
fences, upper and lower hinges, the middle bar, and the outliers. Any statistic used with the
boxplot needs to provide these values." That is an interface, stated in prose in 2010 and
enforced by nothing since.

**Ordered transformation stages.** Three distinct places to transform, with different meaning:
scale transform (before stats — "so that a plot of log(x) versus log(y) on linear scales looks
the same as x versus y on log scales"), data transform, and coord transform (last, bends the
geoms). Fitting a smooth then log-ing the *coordinate system* curves the line; log-ing the
*scale* straightens it. Same picture, different claim.

**Scale training across datasets.** Scales are trained on *every* layer and facet before mapping
— "if scales were applied locally, comparisons would only be meaningful within a facet." Shared
domains are a semantic guarantee, not a convenience.

## Where it struggles

- **The `+` operator is an admitted hack.** Wickham: "To preserve this [declarative] nature in R,
  ggplot2 uses `+`… **This base object is not necessary in a stand-alone grammar.**" A decade of
  `%>%` vs `+` confusion descends from a workaround, not from the grammar.
- **Late errors.** Layers are heterogeneous objects assembled at *print* time by `ggplot_build()`,
  so mistakes surface from deep inside the build pipeline, far from the offending line. A grammar
  checked that late is barely a grammar.
- **NSE.** `aes(carat, price)` is symbol lookup in a data mask; `aes_string()` was deprecated,
  programming over ggplot2 needs quasiquotation and rlang, and the failure mode is a variable
  silently resolving from the global environment.
- **Scale/guide sprawl.** `scale_<aesthetic>_<type>()` is combinatorial, and guides only became a
  documented extension point in **ggplot2 3.5.0 (2024)** — seventeen years in, finally retiring
  "4 possible ways to set the horizontal justification of legend text in 5 different functions."
  `ggproto` itself is conceded to be "something of a historical accident."
- **Stats lie under non-Cartesian coords.** Admitted: stats are computed in Cartesian space,
  "which, while not strictly correct, will normally be a fairly close approximation."
- **Dropping the algebra cost generality.** Faceting "is less flexible, as the layout of the
  facets always occurs in a Cartesian coordinate system." Wilkinson held that his grammar covered
  a wider range; ggplot2 is admittedly weak on area/mosaic plots — "it gives no great insight into
  their underlying structure."
- **Static by construction.** "All plots are static and separate… many ggplot2 graphics take over
  a second to draw."
- **Grammatical ≠ sensible.** The book's own warning: "we can produce many plots that don't make
  sense, yet are grammatically valid."

## Implications for dapper

1. **Don't ship `+`. Ship the pipeline.** Wickham says outright the base object is an R artifact.
   `plot.new(data) |> plot.layer(...) |> plot.scale_x(...)` is the grammar without the tax.
2. **`Layer` and `Plot` are literally ADTs** — five fields and five fields, with exhaustive
   matching on `Mark`, `Scale`, `Coord`. The 2010 paper is a type declaration that has been
   waiting sixteen years for a language.
3. **Accessors, not column names — this answers open question #1.** ggplot2's worst wart is that
   `aes()` is unchecked symbol lookup. The typed equivalent is `List(row)` plus `fn(row) -> Float`:
   no NSE, no decoder, no runtime "column not found". Column-oriented storage is a *renderer*
   concern; keep it out of the grammar.
4. **Type the stat→geom contract — the actual win over Vega-Lite.** Model a stat as
   `fn(List(a)) -> List(b)` with `b` a stat-specific record (`Bin(x0: Float, x1: Float,
   count: Int)`) and have the mark's channels map from `b`. The boxplot contract becomes a compile
   error instead of prose, and ggplot2's `..count..` hack dissolves: computed variables are just
   fields of `b`.
5. **Compatibility by constructor, not type-level machinery.** Wickham: "each geom can only
   display certain aesthetics." Without HKTs or type classes, express that as per-mark
   constructors taking exactly their channels — `mark.bar(x:, y:, fill: Option(...))` — so an
   illegal channel is an unknown-argument error, not a phantom-type essay. That answers open
   question #2: the types carry the constraint, the error message stays a missing/unknown field.
6. **Commit to the stage order now, at v0.1 scope:** scale-transform → stat → train scales over
   *all* layers → map → render. Getting this wrong is unfixable later without silently changing
   every existing chart. Train shared domains across layers from day one even though faceting is
   out of scope — same code path.
7. **Scale = map + invert + params, opaque.** Axes and ticks derive from `invert`; never let users
   author a guide separately. ggplot2's scale/guide split is its worst seam and took until 3.5.0
   to repair.
8. **Split build from render — this is what makes the Lustre story work.** `build(Plot) ->
   ResolvedGeometry` (pure, memoizable), then `render` to an SVG string or `lustre.Element`. That
   is `ggplot_build`/`ggplot_gtable`, and it is exactly the seam the BEAM/JS split needs.
   Snapshot-test `build`, not only the SVG. Store bars as (x0,y0,x1,y1), not (x,y,w,h).
9. **Defaults as constructors, not inference.** `dapper.bar(data, x:, y:)` fills a complete
   `Layer`; keep `dapper.layer(...)` as the escape hatch. Heed the `qplot` post-mortem — "to which
   layer does the `method` argument apply?" — a wrapper with ambiguous argument scope is worse
   than verbosity. Keep themes outside the grammar, applied at render.
10. **Don't oversell the wedge.** The compiler rules out *ungrammatical* charts, not *misleading*
    ones. Wickham's "grammar checker" ideas (too many aesthetics, alphabetical category ordering,
    polar coords) belong in lints, not types.
11. **Skip the algebra, knowingly.** ggplot2 offloaded `DATA`, `TRANS` and the algebra onto R's
    data frames and `reshape`; Gleam has neither, so callers reshape with stdlib list functions
    and dapper ships no algebra — accepting the same known cost, that nested and ragged facet
    layouts stay out of reach.

## Sources

- Wickham, H. (2010). "A Layered Grammar of Graphics." *JCGS* 19(1): 3–28 — read in full
  ([page](https://vita.had.co.nz/papers/layered-grammar.html),
  [PDF](https://byrneslab.net/classes/biol607/readings/wickham_layered-grammar.pdf)). Quotations
  from §3 (components), §4 (defaults), §5 (embedded grammar, the `+` admission), §6 (histograms,
  polar, transformations), §8 (limitations).
- Wilkinson, L. (2005). *The Grammar of Graphics*, 2nd ed., Springer — pipeline and algebra
  (cross/nest/blend over varsets); see also
  [Wikipedia](https://en.wikipedia.org/wiki/Wilkinson%27s_Grammar_of_Graphics) and the
  [pyG2 pipeline summary](https://pyg2.readthedocs.io/en/latest/grammar_of_graphics/pipeline.html).
- Wickham, Navarro & Pedersen, *ggplot2* (3e): ["The Grammar"](https://ggplot2-book.org/mastery.html)
  and ["Internals"](https://ggplot2-book.org/internals.html) — build/gtable split, ggproto as
  "historical accident".
- tidyverse blog, [ggplot2 3.5.0: Legends](https://tidyverse.org/blog/2024/02/ggplot2-3-5-0-legends/)
  (Feb 2024) — the guide-system rewrite.
- [tidyverse/ggplot2#5155](https://github.com/tidyverse/ggplot2/issues/5155) — `aes_string()`
  deprecation and the tidy-eval migration cost.
