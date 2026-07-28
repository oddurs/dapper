# VizQL and the product tradition (Polaris → Tableau, Show Me, Power BI, Looker/Malloy)

## The vision (what this tradition believes a chart is)

A chart is **a table of query results, drawn**. Not a picture with data bound to it — a
*view onto a database* whose structure is the query's structure. The user never says
"make a bar chart"; the user says *what partitions what*, and the shape of the answer
determines the picture.

Hence the defining move: **one specification, two interpretations**. The same expression
compiles to a spatial layout *and* to SQL — Polaris is explicit that "the visual
specification also generates queries to the database," and the two must agree, because a
pane is literally a `SELECT … WHERE {Row(i) and Column(j) and Layer(k)}`. Where the
grammar-of-graphics tradition puts the data pipeline upstream of the picture, this one
makes them the same artifact read two ways. Mark type, aggregation, scales and legends are
all *derived*. Automation is not a convenience layer; it is the thesis.

## Core abstraction

**A table algebra over field names**, whose normalized form *is* the layout.

Operands are fields. Assignment of sets to operands encodes the type distinction that
drives everything:

```
A  =  domain(A) = {a₁,…,aₙ}          -- ordinal field: its ordered domain
P  =  {P}                            -- quantitative field: a singleton
```

Three operators, in precedence order — cross, nest, concatenation:

```
A + B  =  {a₁,…,aₙ, b₁,…,b_m}                        -- ordered union
A × B  =  {a₁b₁, …, aₙb_m}                           -- Cartesian product
A / B  =  {aᵢbⱼ | ∃r ∈ R. A(r)=aᵢ ∧ B(r)=bⱼ}         -- only inhabited combinations
```

Every expression reduces to a single set — the **normalized set form** — and *that set is
one axis of the table*: one entry ↔ one row (or column, or layer). Three expressions
(x, y, z) give the full table configuration. Each pane holds one graphic; each record in
the pane is one mark.

The mark type is then *inferred*, not chosen. The types of the innermost operands select a
family — ordinal-ordinal (text table), ordinal-quantitative (bar / dot / Gantt),
quantitative-quantitative (scatter / map) — refined by record cardinality and by which
variables are independent (dimensions) vs. dependent (measures). Show Me ships this as
concrete rules: dimensions innermost on both shelves → text; measures on both → shape;
dimension + measure → bar; **date** + measure → line. Unaggregated measures silently get
`SUM`.

## Unique contributions

1. **Structure first, mark last.** In a grammar of graphics the mark is primary and
   faceting is a modifier. Here the *layout algebra is primary* and the mark is a leaf
   detail. Small multiples are the base case; a single chart is a 1×1 table. This is a
   genuinely different decomposition and it scales better in one direction the GoG
   handles awkwardly.
2. **`nest` — a data-dependent layout operator.** `quarter/month` yields three months per
   quarter; `quarter × month` yields twelve, nine empty. Vega-Lite adopted exactly this
   as its default for ordinal facet scales, citing Polaris by name. It is the clearest
   case in visualization of a *layout decision that cannot be made without the data*.
3. **The dimension/measure type, taught to millions.** Blue vs. green pills; Power BI's
   column vs. measure; LookML/Malloy's `dimension:`/`measure:`. The most successful piece
   of type propaganda in the industry — non-programmers reliably reason about a
   two-element type lattice because the tool made it visible and consequential.
4. **Automatic presentation as a shipped product**, descending from Mackinlay's APT and
   its *expressiveness* (can the language say it?) and *effectiveness* (does it exploit
   the visual system?) criteria. Show Me is APT surviving contact with customers.
5. **The spec as a value.** Polaris gets unlimited undo/redo "trivially" — push the
   specification on a stack. Modern React charting libraries still do not have this.
6. **Malloy's inversion (Tabb, 2022).** The lineage self-corrected: composition in a
   *textual* language, nesting first-class in queries, and visualization as an
   **annotation on the model** (`# bar_chart`, `# currency`) so rendering intent travels
   with the field rather than being restated per chart.

## Where it struggles

- **Measures are second-class operands.** `P = {P}` is a singleton — only ordinal fields
  partition. So "plot sales and profit side by side" is inexpressible, and Tableau invents
  a pseudo-dimension, `Measure Names`, whose domain is the set of measure names. It looks
  like a dimension but is not a field: referencing it in a calculation errors with
  *"Reference to undefined field."* Twenty years of user pain traceable to one line of the
  algebra.
- **Interaction is outside the formalism.** Brushing, tooltips and dashboards are bolted
  on; dashboards use "a different mechanism, with each view backed by a separate
  specification." There is no algebra for combining differently shaped views. Vega-Lite's
  *view algebra* (layer / concat / facet / repeat) exists precisely because the table
  algebra could not do it.
- **Automation is opaque, and paternalistic when wrong.** Marks morph under the user when
  a pill is dropped; the rule is invisible, so users develop superstition rather than a
  model. Implicit `SUM` is worse: it silently sums averages, ratios, percentages and IDs.
- **A closed vocabulary at the edges.** Anything outside the Show Me menu (Sankey, waffle,
  radial, ribbon) becomes a data-doubling hack. Vega-Lite's critique — templates limit,
  composition generalizes — lands.
- **Structural query cost.** Polaris concedes "there is no standard SQL statement" for the
  pane partitioning, and `CUBE` cannot help because scatterplot matrices produce
  *overlapping* partitions. One query per pane.
- **Not a text language.** VizQL is proprietary and nobody writes it; `.twb` XML is not a
  source format. No diffs, no code review, no ecosystem. Malloy is the tradition
  conceding this point.

## Implications for dapper

**1. Make the pane grid the renderer's top level in v0.1, even with faceting out of
scope.** Render into a 1×1 table. Retrofitting facets onto a renderer that assumes one
plot region is the rewrite this lineage exists to warn you about.

**2. Model the algebra as a plain ADT and normalize it as a pure function.** No HKTs
needed — it is a recursive sum type:

```gleam
pub type Shelf {
  Field(name: String, kind: FieldKind)
  Cross(Shelf, Shelf)
  Nest(Shelf, Shelf)
  Concat(Shelf, Shelf)
}
```

`normalize: Shelf, Data -> List(PaneKey)` is deterministic and property-testable
(associativity of `Cross`, `Concat` distributing over `Cross`, `Nest ⊆ Cross`). Note the
`Data` argument: **`Nest` and ordinal domains are not knowable at compile time.** Draw
that line explicitly — `Chart` is a compiler-checked *shape*; `resolve(chart, data) ->
Result(Layout, DataError)` is where cardinality enters. Trying to type domains is how you
get the error messages your README's open question #2 is worried about.

**3. Put the type distinction on the field, not the channel.** `FieldKind { Nominal
Ordinal Quantitative Temporal }` is Polaris's ordinal/quantitative split plus Stevens'
scales, and it is a bare enum — exactly the kind of typing Gleam does well without type
classes. Let mark constructors demand kinds.

**4. On auto-selection: the strong-typing claim is half true, and the half that is true is
worth taking.** Gleam gives exhaustive matching over `(FieldKind, FieldKind)`, so Show
Me's rule table becomes a `case` the compiler proves total:

```gleam
pub fn suggest(x: FieldKind, y: FieldKind) -> Mark {
  case x, y {
    Temporal, Quantitative -> Line
    Nominal, Quantitative | Ordinal, Quantitative -> Bar
    Quantitative, Quantitative -> Point
    Nominal, Nominal -> Text
    // … compiler forces every pair
  }
}
```

The type system guarantees **totality of the rule table** — you cannot ship a combination
you forgot. It guarantees nothing about **effectiveness**, which needs cardinality,
distribution and zero-baseline facts that live in the data. So: expose it as an explicit,
greppable `dapper/suggest` returning a `Mark` the caller passes in — never as a default
that silently re-infers. Tableau's morphing marks are the failure mode; once the user
names a mark, never re-derive it.

**5. Refuse the implicit `SUM`.** Aggregation should be a required, visible field on the
encoding (`Option(Agg)` where `None` means raw). If a quantitative field lands on a
positional channel opposite a discrete axis with no aggregate, that is a compile error or
a `Result` error — this is precisely the class of runtime-schema failure the dapper wedge
claims to eliminate, and it is the product tradition's most-criticized default.

**6. Design the "multiple measures" case in from day one.** Allow `y: List(Encoding)`, or
a `Repeat` constructor that synthesizes an implicit nominal *series* field. Do not
discover `Measure Names` the hard way.

**7. Steal Malloy's annotation idea for v0.2 theming/format.** Field-level metadata
(`# currency`, `# percent`, preferred mark) is a record consulted by mark constructors —
no macros required — and it answers open question #3 more cleanly than a global palette.

## Sources

- Stolte, Tang, Hanrahan, *Polaris: A System for Query, Analysis, and Visualization of
  Multidimensional Relational Databases*, IEEE TVCG 8(1), 2002 — table algebra §4.1,
  graphic taxonomy §4.2, retinal mappings §4.3, SQL generation §6, CUBE limitation §8.
  <https://graphics.stanford.edu/papers/polaris_extended/>
- Hanrahan, *VizQL: a language for query, analysis and visualization*, SIGMOD 2006.
- Mackinlay, *Automating the Design of Graphical Presentations of Relational Information*,
  ACM TOG 5(2), 1986 — expressiveness/effectiveness criteria, composition algebra.
  <http://vis.arc.vt.edu/~npolys/projects/safas/p110-mackinlay.pdf>
- Mackinlay, Hanrahan, Stolte, *Show Me: Automatic Presentation for Visual Analysis*, IEEE
  TVCG 13(6), 2007.
  <https://www.tableau.com/whitepapers/show-me-automatic-presentation-visual-analysis>
- Tableau docs, *Change the Type of Mark in the View* (the automatic mark rules) and
  *Dimensions and Measures, Blue and Green*.
  <https://help.tableau.com/current/pro/desktop/en-us/viewparts_marks_marktypes.htm>
- Satyanarayan, Moritz, Wongsuphasawat, Heer, *Vega-Lite: A Grammar of Interactive
  Graphics*, IEEE InfoVis 2017 — §2.1 view algebra vs. table algebra; §3.2.3 citing
  Polaris's nest operator. <https://idl.cs.washington.edu/files/2017-VegaLite-InfoVis.pdf>
- Malloy documentation, *Visualizations overview* (tag-based rendering) and *Building a
  Semantic Model*. <https://docs.malloydata.dev/documentation/visualizations/overview>
- Tabb & Toy, *Composing with Queries*.
  <https://lloydtabb.substack.com/p/composing-with-queries>
- Flerlage Twins / Viz Zen Data, on `Measure Names` limitations in calculations.
  <https://www.flerlagetwins.com/2025/07/measure-names-values-overiew-with-some.html>
- InterWorks, *I Hate When Tableau Does That: Magical Morphing Mark Types*.
  <https://interworks.com/blog/skennedy/2015/11/20/i-hate-when-tableau-does-magical-morphing-mark-types/>
- Microsoft Learn, *Understand star schema and the importance for Power BI* (measures vs.
  columns, field wells as shelves).
