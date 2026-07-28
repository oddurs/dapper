# 0001 — Positioning: what dapper actually claims

**Status:** Accepted, July 2026
**Supersedes:** the "The wedge" section of the kickoff README
**Evidence:** `docs/prior-art.md` and the nine briefs in `docs/research/`, especially
`typed-functional-charting.md` and `vega-lite-and-mosaic.md`

## The claim we made at kickoff

> Vega-Lite validates its grammar with a JSON Schema **at runtime** — you find out a channel
> is invalid for a mark when the chart fails to render. In Gleam the same grammar is checked
> by the compiler.

This was the project's headline differentiator. It does not survive the research.

## Why it is wrong

**Vega-Lite's grammar is already compile-time typed.** Vega-Lite is written in TypeScript. The
JSON Schema is a *derived artifact*, generated so that specs can cross a language boundary. The
maintainers' schema pain is schema-*encoding* pain — `additionalProperties: false` combined with
intersections producing unsatisfiable schemas, `A & (B | C)` blowing up exponentially, no
inheritance — not "we forgot to type the grammar." Altair and hvega users already have a typed
surface. The population that a compile-time grammar beats is people hand-writing JSON.

**The errors that actually bite are not structural.** A field name keyed against a dataset that
does not exist yet; `"filter": "datum.location === 'Seattle'"` as an unparsed string;
aggregate-plus-detail conflicts; `x2` without `x`; stacking under an independent scale. All of
these are schema-valid and all of them are wrong. Vega-Lite's own debugging guide makes schema
validity step one of four before sending you to runtime logs. A typed grammar buys **shape**, not
**semantics**, and not **data binding**.

**Nobody in the typed lineage has actually done the thing.** This is the uncomfortable finding:

- **Swift Charts** encodes nothing about which channels a mark accepts. Two quantitative axes
  compile fine and render badly. The documented one-quantitative-one-nominal rule is runtime
  behaviour, not a type.
- **elm-vegalite** makes every combination of `pName`/`pQuant`/`pTemporal` typecheck and delegates
  validity back to Vega-Lite's runtime schema. In practice the strong typing is an autocompleting
  spell-checker over JSON. **hvega** had to *retrofit* even crude newtype separation.
- **Rust `plotters`**, the one library that genuinely pushed structure into types, produced a users
  forum thread titled *"ChartContext extension: Lost in trait bound hell."* Type-level correctness
  bought error messages about type machinery instead of about charts.
- **elm-visualization's own documentation** concedes: "the cost is a certain ugliness and
  complexity of the type signatures… I recommend ignoring the types."

Wickham stands unamended: a grammar rules out *ungrammatical* charts, not *misleading* ones.

## What we claim instead

**Primary — the dual-target purity claim.**

> `render : Chart -> String` is pure and total on the BEAM. No DOM, no headless browser, no font
> engine. The same `Chart` value renders as an interactive Lustre component in the browser.

Nobody has this. It is the reason the JS ecosystem drags a headless Chrome around for
server-side images; nivo built an SSR HTTP *service* and ECharts a dedicated SSR mode to
approximate it. This was listed second at kickoff. It is first.

**Secondary — the typing claim, stated honestly.**

> No field names, no optional-field merge semantics, no forgotten cases, and mark constructors
> that state their channels.

We do **not** claim compiler-checked chart *validity*.

Where static checking genuinely pays, in descending order:

1. **Accessor functions instead of field names.** Barely "clever typing" — a change of
   representation that deletes an entire error class JSON Schema structurally cannot reach.
2. **Split scale types.** `bar` requiring a band scale turns Observable Plot's commonest runtime
   error into a compile error, in one signature, with a readable message.
3. **Exhaustiveness over closed ADTs.** Not "you cannot write a bad chart" but "the library
   cannot forget a case."
4. **Arity in constructors.** `bar(x: Discrete(row), y: Continuous(row), …)`. This is hvega's
   newtype separation, whose honest win was separation plus autocomplete — roughly 80% of the
   felt benefit for 5% of the type-system effort.
5. **Mandatory arguments.** No optional fields means no deep merge, no silent theme override, and
   a `Resolve` the caller must state. Gleam's poverty is the feature.

Where it does not pay, and which therefore belong in a total
`validate(Chart) -> List(Diagnostic)` beside a total `render`: domains, cardinality,
non-emptiness, log scales crossing zero, stack coherence, inhabited facets, and "is this chart
misleading."

## Consequences

**Accepted cost — no serialisable spec.** Accessor closures and JSON portability are an
either/or, and accessors win. This forfeits cross-language spec portability, machine
enumerability (you cannot write a Voyager over a closure), and "generate on the server, store in
a database, render anywhere." Mitigation: allow `Dict(String, Value)` as a legal `row`. This is
stated in the README rather than discovered at v0.3.

**The typing work is bounded.** Ship levels 1–4 above. Treat deeper type-level grammar as a v0.2
experiment, and prototype the hostile error message — a band scale passed where a linear one is
required, three pipeline stages deep — *before* committing to it.

**The architecture follows from the primary claim, not the secondary one.** A public `Scene` ADT
as the seam between grammar and output, and text metrics as an injected value defaulting to an
embedded advance table on both targets, are what make the purity claim true rather than
aspirational. They are no longer nice-to-haves.

## Resolved open questions

The kickoff README's three open questions are answered by this decision and by
`docs/prior-art.md`:

1. **Data shape** → row-oriented `List(row)` with accessor channels. Columnar storage forces
   string field names back into the API and throws away win #1 above.
2. **How typed is too typed** → encode compatibility as *arity*, not as a predicate. Per-mark
   constructors taking exactly their channels, so the error reads "expected `Continuous(row)`,
   found `Discrete(row)`" — about charts, not type machinery.
3. **Theming** → bake a palette, but as a typed `Scheme` whose variants encode
   categorical/sequential/diverging intent, CVD-safe by default, with colours as
   `Literal | CssVar` and a light/dark pair.
