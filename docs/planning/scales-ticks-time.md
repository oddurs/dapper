# Scales, ticks and time

Stream owner note: this is the largest hidden cost on the v0.1 list (`prior-art.md`, open question 4)
and it hardens first, because the mark layer, the axis layer and `validate` all key off its types.

## Decisions

**D1 — Erase the domain to `Float`/`String` at the scale boundary. Scales are not generic over their
domain type.** This is the load-bearing decision and everything below follows from it. Open question
7 already commits to erasure at `build` (scale-transform → stat → train → map → render), because
training must see values across layers of *different* row types. Take that seriously: a
`ContinuousScale` has `domain: #(Float, Float)`, full stop. "Time-ness" is a variant tag that changes
*ticks and format only*, never `convert`. This deletes the entire elm-visualization dictionary-passing
problem — the record of `convert`/`invert`/`ticks` closures exists *only* because `Scale inp` is
polymorphic in `inp`, and it is the exact thing whose author wrote "I recommend ignoring the types."
Typing stays at the constructor, where it is free: `scale.time(from: Timestamp, to: Timestamp)` takes
`Timestamp` and erases internally.

**D2 — Closed sum types, not records of functions.** The two briefs disagree (d3 brief §2 says closed
sum; typed-FP brief §3 says dictionary-passing); `prior-art.md` open question 3 picks closed sum and
that is right, for a reason neither brief states: **`validate` cannot inspect a closure.** Decision
0001 lists "log scales crossing zero" as validator territory. A validator can only see that if the
scale kind is data. Closures also destroy `echo`, structural equality and any hope of a debug print.
Closed sum wins, and the cost D3's brief names — no user-defined scale types — is already accepted.

**D3 — Three scale types, split by capability, opaque from day one.** `ContinuousScale`
(`convert`/`invert`/`ticks`/`nice`/`clamp`), `BandScale` (`convert`/`bandwidth`/`step`/`round`, **no
`invert`**), `OrdinalScale(a)` (`convert -> Result(a, Nil)`). `bar` requires a `BandScale` on its
categorical axis; that one signature converts Observable Plot's commonest runtime error ("barY
requires that the x scale is a band scale") into a compile error. Kinds inside `ContinuousScale`:
`Linear`, `Log(base)`, `Time(Zone)`. No `Sqrt`/`Pow` — they exist for the size channel, and v0.1 has
no size channel. No `Symlog`, `Threshold`, `Quantile`, `Sequential`.

**D4 — `point` is a `BandScale` constructor, not a fourth type.** d3 implements point as band with
`paddingInner = 1` and `bandwidth() == 0`; copy that. A fourth opaque type duplicating the closed-form
geometry to catch one mistake (a bar over a point scale) is not worth it when `validate` can emit
`ZeroBandwidth` for free. Naming: the scale types are `ContinuousScale`/`BandScale`, *not*
`Continuous`/`Band`, because the channel stream has already claimed `Continuous(row)`/`Discrete(row)`
for accessors. Cross-stream collision, flagged now.

**D5 — Categorical colour via `OrdinalScale`; continuous colour via `Quantize`, not interpolation.**
`Quantize` maps a `#(Float, Float)` domain onto `k` discrete outputs by uniform binning. This gives
the theming stream's sequential and diverging `Scheme` variants a home *without* dragging perceptual
colour-space interpolation (Lab/HCL) into v0.1. Interpolated colour is v0.2.

**D6 — `Domain` is a monoid; training across layers is a fold.** `NumericDomain | CategoricalDomain |
EmptyDomain`, with `EmptyDomain` as identity and a total `union`. `prior-art.md` §9 ("train scales
across all layers even with one layer") becomes `list.fold(layer_domains, domain.empty, domain.union)`
— three lines that make faceting and multi-layer charts non-breaking later. Categorical domains take
**first-appearance order**, not sorted; `domain.sorted` is opt-in. Sorting silently reorders bar
charts, which is the surprise Plot's inference is criticised for.

**D7 — `nice` is on by default for *inferred* scales, off for *constructed* ones.** Gleam has no
default arguments, so this is expressed as: `scale.linear(domain, range)` is verbatim; the chart
builder calls `scale.nice(s, count)` when it infers a scale from trained data. Port d3's `nice`
including its 10-iteration bound. Continuous **padding is not in v0.1** — padding in domain units
requires an inverse round-trip that fights `nice`; use range inset instead, owned by the layout
stream. Band padding (`padding_inner`, `padding_outer`, `align`) is closed-form and ships:
`step = (stop - start) / max(1, n - padding_inner + padding_outer * 2.0)`,
`bandwidth = step * (1.0 - padding_inner)`.

**D8 — Clamping is a field, not a wrapper.** `clamp: Bool` on `ContinuousScale`, default `False`,
clamping both `convert` (to range) and `invert` (to domain). Port d3.

**D9 — Ship D3's 1–2–5 as the v0.1 default. Ship extended-Wilkinson *without* the legibility term as
an opt-in strategy. Defer the legibility term to v0.2.** This is the assessment the brief asks for.
The rendering brief calls extended-Wilkinson "highest quality-per-line"; that is true of
simplicity + coverage + density, and *not* of legibility. Three reasons for the split. (a) The
legibility term scores format, font size and orientation simultaneously — it needs `Metrics`, which
this stream would then depend on, and a wrong legibility weight is invisible rather than wrong-looking.
(b) The density term is a function of the *pixel* range, so extended-Wilkinson makes tick selection
layout-dependent — and layout is bounded at two passes (`prior-art.md`: "do not iterate to a
fixpoint"). Ticks feeding layout feeding ticks needs to be entered deliberately, not by accident in
week two. (c) D3's 1–2–5 with `e10 = √50, e5 = √10, e2 = √2` is what essentially every professional
chart in the wild actually uses, and it is forty lines. Port `tick_increment`'s negative-return trick
verbatim (negative step signals a fractional increment, so tick values are computed as `i /. -.step`
rather than `i *. step` — this is what keeps tick values exactly representable and snapshots stable).

**D10 — Time: closed `Unit` sum plus a `Zone` parameter, replacing d3's two parallel interval
families.** d3 ships `timeDay` and `utcDay` as separate objects because JS `Date` has two method
families. We have neither constraint. One `Unit`, one `Step(unit, count)`, and `Zone` threaded as an
argument, is strictly better and is the reason to port the *algebra* rather than the API.
`floor`/`offset`/`count` are primitive; `ceil`/`round`/`range`/`every` are derived, exactly as in
d3-time. Below Day, `floor` is integer arithmetic on epoch seconds; at Day and above it goes through
`gleam/time/calendar`, which is where leap years and month lengths live.

**D11 — Timezones: UTC and fixed offsets only in v0.1. Say so loudly.** `gleam_time` already models a
zone as a fixed `Duration` offset (`calendar.utc_offset`, `calendar.local_offset()`); it has no named
zones. The BEAM has no bundled IANA database and JS has a complete one via `Intl` — supporting named
zones means either an FFI split in the single place we can least afford one (the purity claim is
"pure and total on the BEAM"), or vendoring tzdata and owning its freshness as a solo maintainer.
Fixed offsets are *correct* for a server-rendered report pinned to one offset and *visibly wrong*
only across a DST boundary, where a day tick lands at 23 or 25 hours. Declare that error budget the
way the metrics decision declares its own. Make `Zone` **opaque** with `zone.utc()` /
`zone.fixed_offset(d)` constructors so `Iana(String)` is a non-breaking v0.2 addition.

**D12 — Time ticks are chosen in `Timestamp` space, never in `Float` space.** The scale's `Float`
domain is *seconds* since the Unix epoch (not milliseconds — seconds keeps the whole plausible range
inside 40 bits of a 53-bit mantissa). Tick generation converts the domain back to `Timestamp`, walks
d3's duration ladder (1s, 5s, 15s, 30s, 1m, 5m, 15m, 30m, 1h, 3h, 6h, 12h, 1d, 2d, 1w, 1mo, 3mo, 1y),
falls back to 1–2–5 on years outside it, and converts the resulting exact `Timestamp`s forward. No
tick ever lands on a float-rounded instant.

**D13 — Pin our own number formatter. Never call `float.to_string` in a render path.** Both targets
are IEEE-754 so *arithmetic* agrees, but Erlang's and JavaScript's shortest-round-trip digit
generation and exponent spelling do not, and neither is specified to us. The accepted architecture
depends on "one snapshot suite covers both targets"; a single `1.0e21` vs `1e+21` divergence
falsifies it silently on the target CI does not run. `dapper/format` builds strings from integer
arithmetic only. Tick labels take a *shared* format derived from the tick step (d3's `tickFormat`
behaviour: every label on an axis gets the same decimal count) — cheap, and it is most of why D3 axes
look tidy. The same module owns SVG coordinate formatting; flagged to the render stream as a hard
dependency, because path data has the identical divergence problem.

## Concrete shapes

```gleam
// dapper/scale.gleam
pub opaque type ContinuousScale {
  ContinuousScale(
    kind: ContinuousKind,
    domain: #(Float, Float),
    range: #(Float, Float),
    clamp: Bool,
  )
}

pub type ContinuousKind {
  Linear
  Log(base: Float)
  Time(zone: Zone)
}

pub fn linear(domain: #(Float, Float), range: #(Float, Float)) -> ContinuousScale
pub fn log(domain: #(Float, Float), range: #(Float, Float), base: Float) -> ContinuousScale
pub fn time(
  from: Timestamp, to: Timestamp, range: #(Float, Float), zone: Zone,
) -> ContinuousScale

pub fn convert(s: ContinuousScale, value: Float) -> Float          // total
pub fn invert(s: ContinuousScale, pixel: Float) -> Float           // total
pub fn clamped(s: ContinuousScale, clamp: Bool) -> ContinuousScale
pub fn nice(s: ContinuousScale, count: Int) -> ContinuousScale
pub fn ticks(s: ContinuousScale, count: Int, strategy: TickStrategy) -> List(Float)
pub fn tick_labels(s: ContinuousScale, values: List(Float)) -> List(String)

pub opaque type BandScale {
  BandScale(
    domain: List(String),
    range: #(Float, Float),
    padding_inner: Float,
    padding_outer: Float,
    align: Float,
    round: Bool,
  )
}

pub fn band(domain: List(String), range: #(Float, Float)) -> BandScale
pub fn point(domain: List(String), range: #(Float, Float)) -> BandScale  // padding_inner = 1.0
pub fn band_convert(s: BandScale, value: String) -> Result(Float, Nil)
pub fn bandwidth(s: BandScale) -> Float
pub fn step(s: BandScale) -> Float
// deliberately absent: band_invert

pub opaque type OrdinalScale(a) {
  OrdinalScale(domain: List(String), range: List(a))    // recycles modulo len(range)
}
pub fn ordinal_convert(s: OrdinalScale(a), value: String) -> Result(a, Nil)

pub opaque type QuantizeScale(a) {
  QuantizeScale(domain: #(Float, Float), range: List(a))
}
pub fn quantize_convert(s: QuantizeScale(a), value: Float) -> Result(a, Nil)
pub fn quantize_thresholds(s: QuantizeScale(a)) -> List(Float)
```

```gleam
// dapper/scale/domain.gleam
pub type Domain {
  EmptyDomain
  NumericDomain(min: Float, max: Float)
  CategoricalDomain(values: List(String))   // first-appearance order
}

pub const empty: Domain = EmptyDomain
pub fn union(a: Domain, b: Domain) -> Domain          // monoid; EmptyDomain is identity
pub fn train_numeric(values: List(Float)) -> Domain   // skips NaN/infinite
pub fn train_categorical(values: List(String)) -> Domain
pub fn sorted(d: Domain) -> Domain
pub fn include_zero(d: Domain) -> Domain
```

```gleam
// dapper/ticks.gleam
pub type TickStrategy {
  D3                       // 1-2-5, the v0.1 default
  Extended                 // Talbot/Lin/Hanrahan, legibility term fixed at 1.0
}

pub fn tick_increment(start: Float, stop: Float, count: Int) -> Float  // negative == fractional
pub fn ticks(start: Float, stop: Float, count: Int, strategy: TickStrategy) -> List(Float)
pub fn nice_bounds(start: Float, stop: Float, count: Int) -> #(Float, Float)
pub fn log_ticks(start: Float, stop: Float, base: Float, count: Int) -> List(Float)
```

```gleam
// dapper/time/zone.gleam
pub opaque type Zone {                 // opaque so Iana(String) is non-breaking in v0.2
  Utc
  FixedOffset(offset: Duration)
}
pub fn utc() -> Zone
pub fn fixed_offset(offset: Duration) -> Zone

// dapper/time/interval.gleam  — d3-time's algebra, one family instead of two
pub type Unit {
  Millisecond
  Second
  Minute
  Hour
  Day
  Week(start: Weekday)
  Month
  Year
}

pub type Step { Step(unit: Unit, count: Int) }

pub fn floor(step: Step, zone: Zone, t: Timestamp) -> Timestamp        // primitive
pub fn offset(step: Step, zone: Zone, t: Timestamp, n: Int) -> Timestamp  // primitive
pub fn count(step: Step, zone: Zone, from: Timestamp, to: Timestamp) -> Int  // primitive
pub fn ceil(step: Step, zone: Zone, t: Timestamp) -> Timestamp         // derived
pub fn round(step: Step, zone: Zone, t: Timestamp) -> Timestamp        // derived
pub fn range(step: Step, zone: Zone, from: Timestamp, to: Timestamp) -> List(Timestamp)

pub fn tick_step(from: Timestamp, to: Timestamp, count: Int) -> Step   // the duration ladder
pub fn time_ticks(
  from: Timestamp, to: Timestamp, count: Int, zone: Zone,
) -> List(Timestamp)
```

```gleam
// dapper/format.gleam  — integer arithmetic only; float.to_string is banned in render paths
pub type NumberFormat {
  Fixed(decimals: Int)
  Significant(digits: Int)
  SiPrefix(decimals: Int)
  Grouped(decimals: Int, group: String, decimal_point: String)
  Percent(decimals: Int)
}

pub fn number(f: NumberFormat, value: Float) -> String
pub fn tick_format(domain: #(Float, Float), count: Int) -> NumberFormat  // one format per axis
pub fn coord(value: Float) -> String            // SVG path/attr coordinates, fixed precision

pub opaque type Locale                          // opaque: month/day names extensible without breaking
pub fn english() -> Locale
pub fn time_label(t: Timestamp, unit: Unit, zone: Zone, locale: Locale) -> String
```

Diagnostics this stream contributes to `validate`: `EmptyDomain(channel)`,
`LogDomainCrossesZero(channel)`, `DegenerateDomain(channel)` (min == max),
`ZeroBandwidth(channel)` (a bar over a point scale), `OrdinalRangeExhausted(channel, needed, have)`,
`TimeSpanBelowResolution`.

## Task breakdown

Ordered. Sizes assume a solo maintainer, evenings.

1. **`dapper/format` number formatting + dual-target CI.** (M) Integer-arithmetic decimal formatter,
   `coord`, `tick_format`. Run `gleam test --target erlang` *and* `--target javascript` from task one.
   Unblocks: literally every snapshot, and the render stream's path emission.
2. **d3 fixture harness.** (S) A one-off Node script generating expected values for `ticks`,
   `tickIncrement`, `nice`, band geometry, `d3.timeTicks` into checked-in JSON. Unblocks: every
   subsequent task's verification, and turns "port d3 verbatim" into a goal with a pass/fail test.
3. **`dapper/ticks`, 1–2–5.** (M) `tick_increment` (negative-return trick), `ticks`, `nice_bounds`.
   Unblocks: continuous scales, axes.
4. **`dapper/scale` `ContinuousScale` linear.** (M) convert/invert/clamp/nice/ticks/labels. Unblocks:
   the whole mark and axis layer; this is the first thing that makes a chart possible.
5. **`BandScale`, closed-form.** (M) padding/align/round/step/bandwidth, plus `point`. Unblocks: `bar`,
   and the arity claim (`bar` requiring a band scale is the wedge's cheapest demonstration).
6. **`Domain` monoid and training.** (M) Unblocks: inferred scales, multi-layer charts, faceting later.
7. **`Log` kind + log ticks + diagnostics.** (S) Unblocks: nothing structural; do it before the API
   hardens because it is the test that `ContinuousKind` is the right shape.
8. **`OrdinalScale` and `QuantizeScale`.** (S) Unblocks: the colour channel and the theming stream.
9. **`dapper/time/zone` and `dapper/time/interval`.** (L) The big one. `Unit`/`Step`,
   `floor`/`offset`/`count` over `Zone`, derived `ceil`/`round`/`range`. Sub-Day is arithmetic;
   Day-and-above goes through `gleam/time/calendar`. Unblocks: every time axis.
10. **Time tick ladder + cascading time labels.** (M) `tick_step`, `time_ticks`, English `Locale`.
    Unblocks: usable time charts — which is most real dashboards.
11. **`Time` kind wired into `ContinuousScale`.** (S) Erasure at the constructor, ticks routed to task
    10. Unblocks: nothing; it is the seam closing.
12. **Extended-Wilkinson behind `TickStrategy.Extended`.** (M) Simplicity, coverage, density; legibility
    pinned at 1.0. Unblocks: nothing in v0.1 — ship it last, cut it without regret if time runs out.

Tasks 1–6 are the critical path to a rendered bar chart. Task 9 is the one that will overrun.

## Risks and unknowns

- **Transcendental functions are not bit-identical across targets.** The accepted line "both targets
  are IEEE-754 so arithmetic agrees" is false for `log`/`pow`/`exp` — correct rounding is not
  required, and Erlang's `math:log10` and JS's `Math.log10` may differ in the last ulp. This bites
  exactly where it hurts: `tick_increment` takes `log10` of a span, and one ulp flips a `floor` and
  changes the tick step. **Mitigation: never trust the log directly** — take `float.truncate` of it,
  then verify with an integer-exponent power comparison and correct off-by-one, in one shared helper.
  Same for log-scale ticks. This is the single most likely source of a silent cross-target snapshot
  divergence and it must be fixed in task 3, not discovered in task 12.
- **`gleam_time` is young.** Its API may churn inside v0.1's window, and it is a new dependency
  (`gleam.toml` currently has only `gleam_stdlib`). Confine every call to it inside
  `dapper/time/interval`.
- **DST.** Fixed offsets mean a day boundary is wrong by an hour across a transition and a
  "24 hours" tick range can be 23 or 25 real hours. Declared, budgeted, documented — not fixed.
- **`band_convert` returning `Result`** pushes `Result` handling into every mark that uses a band
  scale. The alternative (a total `convert` with a sentinel) is worse. Expect this to feel heavy in
  the mark stream and resist the temptation to unwrap with a default.
- **Extended-Wilkinson couples ticks to pixel width** via the density term. If it ships, the two-pass
  layout bound must be re-examined.
- **The `Continuous`/`ContinuousScale` naming collision** with the channel stream will confuse
  readers of the docs even after the compiler is satisfied.

## Explicitly not in v0.1

Sqrt/pow/symlog/threshold/quantile/sequential-interpolated/diverging scales. Colour interpolation in
any perceptual space. User-defined scale types. IANA named timezones and DST. Any locale but English.
Date *parsing* (d3-time-format's strptime side). Tick label rotation, multi-line labels, and the
legibility term of extended-Wilkinson. Tick *filtering* for overlap — that is `LabelOverlap`, owned by
the axis stream. `invert` for band scales (hit-testing a bar). Continuous-scale padding in domain
units. d3's `unknown`-value handling with implicit domain extension. `scale-chromatic` palettes —
those are the theming stream's `Scheme`.

## Open questions needing a human call

1. **Is fixed-offset-only acceptable as a shipped v0.1 story?** "Server-rendered dashboards on the
   BEAM" may imply named timezones are table stakes for the target user, in which case task 9 grows a
   vendored tzdata sub-project and the timeline changes materially. I recommend fixed-offset; this
   needs a yes.
2. **Does the public time API give back `Timestamp` or `Float` seconds from `invert`?** Uniformity
   (Float) keeps `ContinuousScale` monomorphic; a `dapper/scale/time.invert -> Timestamp` wrapper is
   friendlier but re-opens the door to per-kind APIs. I lean uniform-plus-wrapper.
3. **`point` as a `BandScale` constructor (D4) — accepted, or is a fourth opaque type worth it** to
   make "bar over a point scale" a compile error rather than a diagnostic?
4. **Who owns `include_zero` for bar baselines** — the domain trainer, or the `bar` mark declaring
   that its continuous scale must contain zero? It affects whether `Domain` needs mark-awareness.
5. **Are d3's ISC-licensed test fixtures acceptable to vendor** into the repo (task 2), or must
   expected values be hand-derived?
