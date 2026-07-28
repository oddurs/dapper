# Typed-functional charting

## The vision (what this tradition believes a chart is)

A chart is a **value**, not a procedure — and its well-formedness should be a property the
compiler establishes before anything is drawn. Where the imperative tradition asks "what calls
do I make to produce pixels?", this one asks "what is the *denotation* of this picture, and
what is the smallest algebra that generates all the pictures I want?"

Two sub-traditions answer "a value of *what*" differently, and the split matters more than any
API detail:

- **Geometry-first** (Haskell `diagrams`, OCaml `Vg`, Scala `doodle`). A chart is a picture.
  Vg literally defines `image` as "maps from the infinite 2D euclidian space to colors";
  diagrams says users specify "what a diagram is, not how to draw it," and diagrams form a
  monoid under `atop`. Data is *outside* the model.
- **Encoding-first** (Swift Charts, `terezka/elm-charts`, `elm-vegalite`/`hvega`, Rust
  `plotters`, Haskell `hgg`). A chart is a **mapping from a row type to visual channels**, plus
  a scale that makes the mapping concrete. Apple's own framing: "A chart works by transforming
  abstract data, like sales value, into the properties of marks."

Both share one belief: rendering should be **total**. There is no "spec rejected" branch. That
is precisely dapper's wedge, and this lineage is the only one that has seriously attempted it.

## Core abstraction

**The channel is a typed accessor function, not a string field name.** This is the tradition's
single biggest divergence from the Vega-Lite lineage, and it is the thing to steal.

```elm
-- terezka/elm-charts
bar    : (data -> Float) -> List (Attribute CS.Bar)  -> Property data inter CS.Bar
series : (data -> Float) -> List (Property data CS.Interpolation CS.Dot) -> List data -> Element data msg
```

`data` is the *user's own record type*, threaded through every layer of the chart. There is no
schema, no field-name typo class, no `"encoding.x.field must be a string"` runtime error —
because there is no field name. Swift Charts does the same with a protocol:
`BarMark(x: .value("Day", d.day), y: .value("Sales", d.sales))`, where the value must conform
to `Plottable` (`Int`, `Double`, `String`, `Date`, `Decimal` by default).

The second load-bearing abstraction is **the scale as a closed record of functions**.
`gampleman/elm-visualization` — a typed d3-scale port, the closest existing analogue to
dapper's `Scale` module — does this without type classes:

```elm
type Scale scaleSpec = Scale scaleSpec

type alias ContinuousScale inp =
    Scale { domain : ( inp, inp ), range : ( Float, Float )
          , convert : ( inp, inp ) -> ( Float, Float ) -> inp -> Float
          , invert  : ( inp, inp ) -> ( Float, Float ) -> Float -> inp
          , ticks : ( inp, inp ) -> Int -> List inp, ... }
```

This is manual dictionary passing: `convert` works across linear/log/time because each
constructor packs its own implementation. It needs no HKTs, no type classes, no macros — it is
directly expressible in Gleam.

## Unique contributions

1. **Row-type parameterization.** `Element data msg` / `Mark<Row>` forces every layer of a chart
   to agree on the shape of its data, at zero runtime cost.
2. **Dictionary-passing scales** (elm-visualization): polymorphic `convert`/`ticks`/`invert`
   without a class system.
3. **Type-driven defaults** (Swift Charts): the *data type* selects the scale and even the mark
   geometry — swapping a quantitative and nominal axis rotates bars automatically. Inference in
   place of configuration.
4. **Monoidal layout with envelopes** (diagrams). Yorgey replaced bounding boxes with
   *envelopes* — support functions answering "how far in direction *v* until a perpendicular
   hyperplane encloses this?" — because envelopes are a monoid and bounding boxes compose badly
   under rotation. Chart layout (plot area, axes, legend, annotations) is the same problem.
5. **Denotation before API** (Vg): fix the meaning, then backends become homomorphisms into
   different rendering targets. dapper's SVG-string and Lustre-element emitters are exactly two
   interpretations of one AST.
6. **Cheap phantom separation** (hvega 0.5.0.0): they split one untyped `LabelledSpec` into
   distinct `EncodingSpec` / `TransformSpec` types "so that they can not be accidentally
   combined." Roughly 80% of the felt benefit of "compiler-checked grammar" for 5% of the
   type-system effort.

## Where it struggles

**Nobody has actually type-checked the mark × channel compatibility relation.** This is the
uncomfortable finding, and dapper should internalise it before writing a line of code.

- Swift Charts encodes *nothing* about which channels a mark accepts. `BarMark(x:y:)` is an
  overload set over `Plottable`; two quantitative axes compile fine and simply render badly.
  The documented rule — one axis quantitative, the other nominal or temporal — is a runtime
  behaviour, not a type.
- elm-vegalite's `position : Position -> List PositionChannel -> List LabelledSpec -> List LabelledSpec`
  makes every combination of `pName`, `pQuant`, `pTemporal` typecheck. Validity is still
  delegated to Vega-Lite's runtime JSON Schema. The strong typing is, in practice, an
  autocompleting spell-checker over JSON. hvega had to *retrofit* even the crude separation
  above.
- The one library that does push structure into types — Rust `plotters`, with
  `ChartContext<DB, Cartesian2d<RangedCoordf64, RangedCoordf64>>` — produced a users forum
  thread titled *"ChartContext extension: Lost in trait bound hell"* and a rustc issue about
  errors that "all boil down to `Ranged` isn't satisfied for `()`". Type-level correctness
  bought error messages about type machinery instead of about charts.
- Swift's result-builder DSL hits *"the compiler is unable to type-check this expression in
  reasonable time"* — the standard failure of an inference-heavy, overload-driven chart DSL.
- elm-visualization's own docs concede the price: "This API is highly polymorphic… the cost is a
  certain ugliness and complexity of the type signatures… I recommend ignoring the types."

**The closed-ADT fold explosion.** elm-charts' `Element data msg` has ~15 constructors, and
`definePlane`, `getItems`, `getLegends`, `getTickValues` each `case` over all of them, mostly
returning `acc` unchanged. Adding one mark means editing six functions. Gleam has exactly this
constraint.

**Geometry-first lost the data model.** diagrams and Vg are the most beautiful designs here and
neither produced a usable charting API — Vg's companion `Vz` never shipped; Haskell `Chart`
bolted a lens-heavy configuration layer on top of a diagrams backend. A picture algebra does not
generate a grammar of graphics.

**Rigidity is prescriptiveness in disguise.** Tereza Sokol abandoned her own opinionated
`elm-plot`/`line-charts` because "it's very difficult to predict what is a good chart," moving
to building blocks plus escape hatches. A type system that forbids the weird 5% chart loses the
same users.

## Implications for dapper

Concretely, given no HKTs, no type classes, no macros:

1. **Settle open question 1 as row-oriented.** `List(row)` plus accessor functions. Column-
   oriented storage forces string field names back into the API and throws the wedge away.
   Thread `row` everywhere: `Chart(row)`, `Mark(row)`, `Channel(row)`. Plain generics suffice.
2. **Encode the grammar as arity, not as a relation.** Don't build a compatibility predicate.
   Give each grammar position its own opaque type and let each mark constructor's *signature*
   state what it accepts:
   ```gleam
   pub fn bar(x: Discrete(row), y: Continuous(row), attrs: List(BarAttr)) -> Mark(row)
   pub fn line(x: Continuous(row), y: Continuous(row), attrs: List(LineAttr)) -> Mark(row)
   ```
   The error reads "expected `Continuous(row)`, found `Discrete(row)`" — about charts, not about
   traits. This is the honest, Gleam-shaped answer to README question 2, and it is strictly more
   than Swift Charts or elm-vegalite deliver.
3. **Scales: separate opaque types, dictionary-passing, no faked uniformity.**
   `Scale(a)` carrying `convert`/`invert`/`ticks`/`format`; `BandScale(a)` *separately*, because
   band has `bandwidth` and has no `invert`. elm-visualization's admitted ugliness comes from
   pretending one type covers operations that don't exist for all members.
4. **Compiler for shape, a total validator for semantics.** Log domains crossing zero, empty
   domains, colour channel with 200 categories — these are not type errors. Ship
   `validate(Chart(row)) -> List(Diagnostic)` and keep `render(Chart(row)) -> String` total.
5. **One eliminator per sum type.** Give `Mark(row)` a single `to_geometry` returning a record
   (extent, required scales, legend entries, nodes). Adding a mark touches one function, not
   six.
6. **Two backends, one AST** (Vg). A tiny `Node` IR emitted to both an SVG string and Lustre
   elements means birdie snapshots on Erlang genuinely cover the JS path.
7. **Ship the escape hatch in v0.1.** A `custom(fn(Plane) -> Node)` mark. Sokol's lesson is the
   most expensive one in this lineage to relearn.
8. **Do not oversell.** hvega's real-world win was newtype separation and autocomplete. Deliver
   that first; treat deeper type-level grammar as a v0.2 experiment with a prototype of the
   hostile error message before committing.

## Sources

- [Yorgey, *Monoids: Theme and Variations* (Haskell Symposium 2012)](http://ozark.hendrix.edu/~yorgey/pub/monoid-pearl.pdf) — diagrams' monoid/envelope design
- [diagrams user manual](https://diagrams.github.io/doc/manual.html) — envelopes, traces, `atop`, local origin
- [Apple, *Swift Charts: Raise the bar* (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10137/) — marks/properties/scales rationale
- [Swift `Plottable` / `PlottableValue`](https://developer.apple.com/documentation/charts/plottablevalue)
- ["The compiler is unable to type-check this expression in reasonable time"](https://developer.apple.com/forums/thread/720808); [Hooper, *Why Swift's Type Checker Is So Slow*](https://danielchasehooper.com/posts/why-swift-is-slow/)
- [Elm Radio ep. 39, Tereza Sokol on elm-charts](https://elm-radio.com/episode/elm-charts/) — building blocks over prescription
- [terezka/elm-charts `Chart.elm`](https://github.com/terezka/elm-charts/blob/master/src/Chart.elm) — `Element data msg`, accessor channels
- [gampleman/elm-visualization `Scale.elm`](https://github.com/gampleman/elm-visualization/blob/master/src/Scale.elm) — dictionary-passing scales; author's own caveat on signature ugliness
- [gicentre/elm-vegalite](https://github.com/gicentre/elm-vegalite) and [Wood et al., *Design Exposition with Literate Visualization* (TVCG 2018)](https://openaccess.city.ac.uk/20081/1/wood_literate_2018.pdf)
- [hvega changelog (0.5.0.0 type-safety retrofit)](https://hackage.haskell.org/package/hvega-0.11.0.0/changelog)
- [Rust users: *ChartContext extension: Lost in trait bound hell*](https://users.rust-lang.org/t/chartcontext-extension-lost-in-trait-bound-hell/122100); [rust-lang/rust#89973](https://github.com/rust-lang/rust/issues/89973)
- [Bünzli, *Vg* semantics](https://erratique.ch/software/vg/doc/semantics.html) and [Vg talk, 2013](https://erratique.ch/talks/vg-talk-2013.pdf)
- [creativescala/doodle](https://github.com/creativescala/doodle) — tagless-final graphics algebras (needs HKTs; unavailable in Gleam)
- [ANN: hgg, a Haskell-native grammar of graphics](https://discourse.haskell.org/t/ann-hgg-a-haskell-native-grammar-of-graphics/14432)
