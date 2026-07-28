# Statistical Python (matplotlib → seaborn → plotnine / Altair / HoloViews)

## The vision (what this tradition believes a chart is)

A chart is **an answer to a statistical question about a dataset**, not a drawing. This
lineage inherits Tukey's EDA stance: you are interrogating a dataframe, and the plot is a
rendered inference. Seaborn's paper states the goal as a "declarative, dataset-oriented API
that makes it easy to translate questions about data into graphics that can answer them."

Two beliefs follow:

1. **Aggregation is part of plotting, not a step before it.** A bar chart of `mass ~ species`
   *means* "mean with 95% bootstrap CI." The chart owns the estimator.
2. **Good defaults are a feature, not a cop-out.** The library should make a defensible
   statistical decision on behalf of a domain scientist who is not a viz expert. Seaborn
   shows 95% bootstrap CIs rather than standard errors because that "allows the user to
   perform 'inference by eye'" — a citation of psychology literature (Cumming & Finch 2005)
   inside a plotting library's rationale.

Grammar-of-graphics believes a chart is a *specification*; D3 believes it is *data-bound
DOM*; this tradition believes it is *an estimator plus its uncertainty, displayed*.

## Core abstraction

Two, and the split is the story of the lineage.

**matplotlib: an Artist scene graph (`Figure` → `Axes` → `Artist`) plus a global "current"
pointer.** matplotlib's own docs describe `pyplot` as an interface that "keeps track of the
last Figure and Axes created, and **adds Artists to the object it thinks the user wants**."

**seaborn.objects (2022–): `Plot` + `Mark` + `Stat` + `Move` + `Scale`** — a pipeline over
tidy long-form data:

```python
so.Plot(penguins, x="species", y="body_mass_g", color="sex")
  .add(so.Bar(), so.Agg(), so.Dodge())      # mark, stat, positional move
  .facet("island")
```

The load-bearing idea, and seaborn's genuine advance over ggplot2, is factoring **`Move`**
out of `Stat`. In ggplot2, `position_dodge`/`position_jitter` are a bolt-on argument to a
geom; seaborn promotes positional adjustment to a first-class stage running *after* the
statistic, so `Bar + Agg + Dodge` and `Dot + Jitter` share one pipeline shape. `Plot` methods
return clones, so a base spec derives variants.

## Unique contributions

- **Statistical transforms as first-class plot stages.** `Agg`, `Est`, `Hist`, `KDE`,
  `PolyFit`, `Perc` occupy the same slot. The chart's statistical claim is named in the spec
  rather than buried in a preprocessing script.
- **Uncertainty by default.** No other major tradition ships CIs unasked. Signature move,
  and the most contested one.
- **Faceting as a data operation.** `FacetGrid`/`.facet()`/`.pair()` make "split and lay out
  one panel per group" part of the grammar. Crucially a *layer* can opt out (`col=None`) —
  that is how you draw a grey "all data" reference series behind every panel, an idiom
  ggplot2 makes awkward.
- **Semantic mapping via type inference.** Seaborn "infers whether to use a qualitative or
  quantitative mapping based on whether the input data is categorical or numeric."
- **Theming on two orthogonal axes**: `style` (look) vs `context` (paper/notebook/talk
  scaling). Resizing for a slide deck is a separate knob from restyling. Nobody else models
  this.
- **Altair's proof:** a Python charting API can be a *pure specification emitter* — it
  "contains no actual visualization rendering code," only Vega-Lite JSON. HoloViews takes the
  extreme: "stop plotting your data — annotate your data and let it visualize itself."

## Where it struggles

**1. matplotlib's dual API — the cause was a compatibility promise, not stupidity.** `pyplot`
existed for a good reason: Hunter and Droettboom wrote that "the MATLAB design makes the
simple task of loading a data file and plotting very straightforward, where a full
object-oriented API would be too syntactically heavy." The failure was that it became the
*documented default* rather than a REPL shim, so twenty years of Stack Overflow answers mix
the two. Maintainers now say the stateful API "can lead to brittle code that depends on the
global state in confusing ways, particularly when used in library code" — and the remediation
is a *separate prototype package* (`mpl-gui`), because `pyplot` cannot be removed. Hunter's
own regret is API-shaped: they "did not spend enough effort determining whether this was the
right drawing API."

**The harm is not global state per se — it is two ways to say the same thing that leak into
each other.** `plt.xlabel()` vs `ax.set_xlabel()` forks every tutorial forever.

**2. Seaborn reproduced the schism one level up.** Axes-level functions (`scatterplot`) hook
into matplotlib's state machine; figure-level ones (`relplot`) create their own figure. The
FAQ concedes this is the "biggest source of confusing behavior," and Waskom admits the naming
was wrong: "calling the figure-level functions something like `relfig`, `catfig` would have
made more sense." The runner-up confusion — categorical axes silently remapping numbers to
indices 0..n — is a leaked matplotlib workaround from an era when matplotlib couldn't handle
strings.

**3. The escape hatch is a different library.** Seaborn's FAQ names this the **"two-library
problem"**; the 2021 paper is blunt that seaborn "does not implement the formal Grammar of
Graphics and cannot be used to produce arbitrary visualizations." `so.Plot` exists to
"alleviate the 'two-library problem' as it matures."

**4. The grammar rewrite never landed.** `seaborn.objects` shipped September 2022 after
"several years of design and 16 months of implementation," labeled experimental — and
seaborn's last PyPI release is **0.13.2, January 2024**. Two and a half years on it is still
experimental, still missing features (no CI band on `PolyFit`, a regression from the old
`regplot`), still not the documented default. The old function API is now permanent. A
grammar rewrite bolted onto a successful non-grammar library, by one maintainer, empirically
does not finish.

**5. Good defaults cut both ways.** Bootstrap CIs by default meant a decade of published
figures whose error bars nobody chose. The 0.12 fix replaced the overloaded `ci` argument
with explicit `errorbar=("ci", 95)` / `("se", 1)` / `("pi", 50)` — the remedy for a bad
default was **making the choice nameable**, not removing it.

## Implications for dapper

**Have exactly one API.** No convenience module that mutates hidden state. If ergonomics
demand shortcuts, make them functions returning the *same value* (`dapper.bar(data, x:, y:)`
→ `Chart`, identical to the long form) — never a second execution model. Nearly free in
Gleam: no globals, `Chart` is data. dapper's structural advantage over this whole lineage is
that pyplot is unrepresentable.

**Steal `Stat` and `Move` as separate first-class stages, in the type.**

```gleam
pub type Stat  { Identity  Agg(Estimator)  Bin(BinSpec) }
pub type Move  { NoMove  Dodge(gap: Float)  Stack  Jitter(width: Float) }
pub opaque type Layer {
  Layer(mark: Mark, stat: Stat, move: Move, encoding: Encoding)
}
```

Do not fold dodging into `Bar`. Both are closed ADTs — exactly what Gleam does well and what
Vega-Lite's runtime JSON Schema cannot check.

**Model uncertainty as an explicit ADT, never an implicit default.** Take the insight (a
summarized chart without uncertainty is a lie) with the v0.12 remedy (the choice must be
named). Don't ship bootstrap in v0.1, but reserve the constructor so adding it isn't
breaking: `pub type ErrorBar { NoError StdDev(Float) StdErr(Float) Percentile(Float) }`.

**Enforce stat/mark/channel compatibility with types, not docs.** This is dapper's wedge, and
where seaborn concretely fails: `Hist` "requires only x *or* y, generating the missing
coordinate" — a rule that lives only in prose. Without HKTs or type classes, make the
constructor the gate: `layer.binned(mark:, on: X, bins:)` returns a `Layer` whose y-channel
is already `Count`, so no user y can be attached. Smart constructors over opaque types are
dapper's substitute for type classes.

**Facet is a chart operation, not a render flag.** `facet(chart, by: Field, wrap: Int) ->
Chart`, shared scales by default — plus the `col=None` escape as a per-layer
`facet_scope: AllPanels | OwnPanel`, which is what makes reference-layer small multiples
possible.

**Ship style × context theming as plain records.** `Theme(style: Style, context: Context)`
where `Context` scales fonts/strokes. Server-rendered SVG in a report vs a Lustre component
in a dashboard *is* the paper-vs-notebook case. Snapshot tests become meaningful: one
`Chart`, two contexts.

**Infer the scale from the column type, totally.** `Float` → linear, `String` → band +
categorical palette, `Time` → time. Seaborn sniffs dtypes at runtime; dapper can decide at
compile time because the type is already there. Allow overrides, but the default must be
inferable — the "good defaults" contribution, delivered better.

**No escape hatch into a lower library.** The two-library problem is what killed seaborn's
coherence. If dapper can't express a customization, extend the grammar or accept the limit.
A `to_svg_nodes` is acceptable only if one-way and terminal.

**Ship the grammar first.** Do not plan a "simple v0.1, grammar in v0.5." That is precisely
seaborn's failure mode; convenience wrappers must be thin and obviously derived.

## Sources

- Waskom, M. L. (2021). *seaborn: statistical data visualization*. JOSS 6(60), 3021.
  https://doi.org/10.21105/joss.03021 — dataset-oriented API; opinionated mappings; bootstrap
  CI default; "does not implement the formal Grammar of Graphics."
- matplotlib, *Matplotlib Application Interfaces (APIs)*.
  https://matplotlib.org/stable/users/explain/figure/api_interfaces.html
- Hunter, J. & Droettboom, M., *matplotlib*, in *The Architecture of Open Source
  Applications* v2. https://aosabook.org/en/v2/matplotlib.html — why pyplot exists; regrets.
- matplotlib/mpl-gui. https://github.com/matplotlib/mpl-gui — pyplot's "two critical, but
  unrelated functions."
- Waskom, *Announcing the release of seaborn 0.12* (Medium, 2022).
- seaborn, *The seaborn.objects interface*.
  https://seaborn.pydata.org/tutorial/objects_interface.html — Plot/Mark/Stat/Move/Scale;
  deliberate ggplot2 deviations ("less complex default behavior").
- seaborn FAQ. https://seaborn.pydata.org/faq.html — the "two-library problem."
- Waskom, *Three common seaborn difficulties* (Medium) — the `relfig`/`catfig` admission.
- seaborn, *Statistical estimation and error bars*.
  https://seaborn.pydata.org/tutorial/error_bars.html — the 0.12 `errorbar` API.
- Vega-Altair. https://github.com/vega/altair — "no actual visualization rendering code."
- HoloViews 1.4 announcement, "Stop plotting your data."
  https://mail.python.org/pipermail/numpy-discussion/2016-February/075075.html
- plotnine. https://plotnine.org/
- PyPI JSON API: seaborn's latest release is 0.13.2, 2024-01-25 (checked 2026-07-28).
