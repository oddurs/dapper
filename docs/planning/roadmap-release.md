# Roadmap and release

Sequencing, scope control and shipping for dapper 0.1.0. Builds on
[decision 0001](../decisions/0001-positioning.md) and [prior art](../prior-art.md); revisits
nothing they settled.

## Decisions

**1. The walking skeleton is one bar chart end to end — but not with hardcoded data.**
The kickoff instinct is right about the *shape* and wrong about one word. Bar is the correct
first mark because `bar` requiring a `Band` scale is the cheapest honest demonstration of the
typing claim (prior art, "what to steal" #4), and because it exercises the band/continuous split
that a line chart lets you skip. But "hardcoded data" would let the skeleton dodge the one
decision prior art calls *unfixable later*: where channel erasure happens
(open question 7 — scale-transform → stat → train across layers → map → render). The skeleton
must therefore go over a real `List(row)` with accessor channels, a band x, a linear y, generated
ticks, embedded metrics, a public `Scene`, and a birdie snapshot of **both** the `Scene` and the
SVG string. Ugly internals are fine; wrong seams are not. Everything unretrofittable —
`Scene` public, `(facet, series, datum_index)` keys, 1×1 pane grid, `Metrics` as an injected
value, pinned float formatting — lands in the skeleton or it does not land.

**2. Ship 0.0.x from the primitives layer onward; 0.1.0 is the first version with a promise.**
Publishing `0.0.1` once `dapper/scale` and `dapper/ticks` are real gets the name onto Hex, gets
hexdocs rendering, and shakes out the release pipeline while nothing depends on it. The
alternative — a silent six months then a 0.1.0 — front-loads all the packaging risk onto the day
you least want it. 0.1.0 means "a bar/line/point chart renders on both targets and I will not
break you inside 0.1.x".

**3. Pre-1.0 policy: minor may break, patch may not; no 1.0 until faceting has shipped.**
Standard Gleam/Hex practice, stated explicitly in the README rather than assumed. Consumers pin
`>= 0.1.0 and < 0.2.0`. 1.0 is gated on faceting because faceting is the change most likely to
force `Chart`, `Scene` and per-channel `ScaleResolve` to change shape, and a 1.0 that has not
survived it is a promise made in ignorance.

**4. Reserved slots are cheap only if they are *opaque* and have an eliminator.**
Gleam's real hazard is not the record field — an `opaque` record can grow fields freely — it is
public *sum types* leaking into signatures, because a user's `case` over `Stat` breaks the day
you add `Bin`. So every reserved slot ships as an opaque type with exactly one constructor
function and one eliminator in its own module: `stat.identity()` / `stat.apply(...)`. Adding a
variant then costs nothing. What is genuinely not free later is the *pipeline stage* the slot
implies: `stat` and `move` must be threaded through `build` from day one even as identities,
because inserting a stage into a settled pipeline silently changes every existing chart.
Reserve the stages, not just the fields.

**5. Packaging: one package for the two public layers, a second package for Lustre.**
Prior art #10 settles the primitives/batteries question — `dapper/scale`, `dapper/ticks`,
`dapper/shape`, `dapper/metrics` usable standalone inside one `dapper` package, with a
one-way import rule (below) so a later extraction is mechanical. It does not answer the Lustre
question, and Gleam has **no optional dependencies**. `lustre` 5.7.1 pulls `gleam_otp`,
`gleam_erlang`, `gleam_json`, `houdini` and `exception`. Making a Wisp server that wants a pure
SVG string depend on an OTP supervision tree contradicts the headline claim in spirit. So:
`dapper` depends on `gleam_stdlib` only, and `dapper_lustre` (a thin `Scene -> Element(msg)`
fold, pinned `>= 0.1.0 and < 0.2.0` on `dapper`) is a second package and repo. The prefix is
justified under the naming system's own `lattice_*` exception — these compose into one system,
so the prefix carries technical meaning.

**6. Documentation is a milestone, not a tail.** The naming system's known cost is that nobody
searching "gleam charting library" finds `dapper` by name, and the named mitigations —
`gleam.toml` `description`, a literal README first line, a plain-language org index — are
mandatory, not optional. Both are already correct in this repo; the release checklist must keep
them correct. Beyond that: the gallery **is** the snapshot suite. Each example is a test that
renders to `docs/gallery/*.svg` and is asserted with birdie, so examples cannot rot and the
README can embed real output — free, because the output is a string with no runtime.

## Concrete shapes

Module DAG, one-way, enforced by a test that greps imports:

```
dapper/format, dapper/metrics        (no dapper imports)
  -> dapper/scale, dapper/ticks, dapper/shape
    -> dapper/scene                  (public Scene ADT + to_svg_string)
      -> dapper/chart, dapper/mark, dapper/stat, dapper/move, dapper/validate
        -> dapper                    (batteries)
```

```gleam
// dapper/chart — opaque from commit one; reserved slots present and inert.
pub opaque type Chart(row) {
  Chart(
    data: List(row),
    layers: List(Layer(row)),
    frame: Frame,
    metrics: metrics.Metrics,
    title: Title,                 // reserved
    legend: Legend,               // reserved
    tooltip: Tooltip,             // reserved
    annotations: List(Annotation),// reserved, always []
    label_overlap: LabelOverlap,  // reserved beyond ShowAll
  )
}

pub opaque type Layer(row) {
  Layer(mark: Mark(row), stat: Stat, move: Move, resolve: ScaleResolve)
}

pub fn new(data: List(row), metrics: metrics.Metrics) -> Chart(row)
pub fn layer(Chart(row), Mark(row)) -> Chart(row)   // stat/move/resolve defaulted
pub fn render(Chart(row)) -> String                  // total
pub fn build(Chart(row)) -> scene.Scene              // total, public seam
```

```gleam
// dapper/stat — the reservation pattern, repeated for move, title, legend,
// tooltip, annotation, scale_resolve, label_overlap.
pub opaque type Stat { Identity }
pub fn identity() -> Stat { Identity }
pub fn apply(stat: Stat, rows: List(Datum)) -> List(Datum) {
  case stat { Identity -> rows }
}
```

```gleam
// dapper_lustre — the entire second package's public surface at 0.1.0.
pub fn to_element(scene: dapper/scene.Scene) -> lustre/element.Element(msg)
```

## Task breakdown

**M0 — walking skeleton (L, ~30h).** Unblocks everything.
1. `dapper/format`: pinned float→string, property-tested identically on both targets (S). Unblocks
   every snapshot.
2. Font advance-table extraction script (non-Gleam, one-off) + `dapper/metrics/embedded`, upem
   1000, tabular digits, per-class fallback (M). Unblocks all layout.
3. End-to-end bar spike: accessors → erase → train → map → `Scene` → SVG string, birdie on both
   (L). Unblocks the pipeline-order commitment.

**M1 — the standalone layer (M/L, ~50h).** Publish `0.0.1` at the end of it.
4. `dapper/scale`: `Continuous` (linear, log, time) and `Band`, split by capability, d3-scale
   semantics ported verbatim (L).
5. `dapper/ticks`: 1–2–5 floor then extended-Wilkinson scoring over `Metrics` (M).
6. `dapper/shape`: line/area path emission, `(x0,y0,x1,y1)` rectangles (S).
7. Import-DAG test + hexdocs on every public function in the layer (S). Unblocks a future split.

**M2 — the grammar (L, ~50h).**
8. `Chart`/`Layer` opaque, all reserved slots and their eliminators (M).
9. `bar` / `line` / `point` constructors with channel arity; x, y, color (M).
10. `build`: erase → stat → train over all layers → move → map, into a 1×1 pane grid (L).
11. Axes: two-pass layout (ticks → format → measure → reserve → re-range → re-tick → stop) (L).
12. `validate(Chart) -> List(Diagnostic)`, total (S).

**M3 — the second target and the polish that is unretrofittable (M, ~35h).**
13. `dapper_lustre` repo, `to_element`, one shared snapshot suite across both targets (M).
14. `Scheme`/`Theme` with `Literal | CssVar` light/dark pairs (M).
15. Accessibility L1 at string-construction time: `role="img"`, `<title>`, derived `<desc>` (S).
16. `custom(fn(Frame) -> Scene)` escape hatch, one-way and terminal (S).

**M4 — ship (M, ~35h).**
17. Gallery-as-snapshot-tests, ~8 charts, SVG committed to `docs/gallery/` (M).
18. `docs/guide.md` — one narrative from `new` to `render`, plus a "scales only" section (M).
19. README rewrite around the two working targets; CHANGELOG; CI matrix (Erlang × JS) (S).
20. Release checklist, tag, `gleam publish` both packages (S).

**Effort: ~200 hours ± 30%, or five to seven months at 8–10 h/week.** The two estimates most
likely to be wrong are the metrics table (task 2 — needs font parsing outside Gleam) and time
scales inside task 4, which prior art already flags as the largest hidden cost on the list.

## Definition of done for 0.1.0

- `gleam test` green on both targets; the same birdie snapshots pass on both.
- Bar, line and point render; x, y and color channels; linear, log, time and band scales.
- `render` and `validate` are total — no `panic`, no `let assert`, no partial function in `src/`.
- Every public module and function has a doc comment; `gleam docs build` warning-free.
- Eight gallery charts, each an executed test.
- README first line is a literal description; `gleam.toml` `description` unchanged in meaning.
- CHANGELOG has a real `## [0.1.0]` section naming the compatibility promise.
- `dapper` depends on `gleam_stdlib` only.

## Risks and unknowns

- **Two render paths drift.** Mitigated structurally: `Scene` is the seam and both folds are
  snapshotted from the same fixtures. If `dapper_lustre` ever needs its own layout, the design
  has failed and it should be found in M3, not M5.
- **The embedded metrics table is the schedule's long pole** and the only task requiring
  non-Gleam tooling. If it slips, ship the per-class fallback table alone and refine later — the
  error budget is already declared as "fine for axis labels, not for long titles".
- **Float formatting divergence between BEAM and JS** breaks snapshots silently. Task 1 exists to
  fail loudly and early instead.
- **Lustre 5.x churn.** Pinning `dapper_lustre` to a lustre major is a bet; the separate package
  is precisely what keeps that bet off the core.
- **No users means the layering is unvalidated.** The one-way import test is cheap insurance; the
  decision to extract `dapper_scale` should wait for someone asking.
- **Scope creep into faceting.** It is the biggest post-0.1 chunk and the most tempting. The
  reserved `ScaleResolve` exists so that saying no now costs nothing.

## What is explicitly NOT in v0.1

Faceting and the pane algebra beyond a 1×1 grid. `repeat`. Stats (`bin`, `aggregate`) and moves
(`dodge`, `stack`) as anything but identity. Tooltips, legends, titles and annotations as
anything but reserved slots. Interaction state, animation, keyed diffs. Geo projections. Canvas,
WebGL, headless anything. Large-data reduction (M4/LTTB). A serialisable spec. `dapper/suggest`.
Accessibility levels 2–4. User-defined scale types. A `Backend` record of functions — not until a
third target exists.

## Open questions needing a human call

1. **Which font family ships in `dapper/metrics/embedded`?** It determines the emitted
   `font-family` stack and is effectively permanent. A metrically-compatible open family is the
   safe answer; the decision is licence-shaped as much as technical.
2. **Publish `0.0.1` from M1, or stay dark until 0.1.0?** Recommended above, but it does put a
   half-library on Hex under a name the family cares about.
3. **Does `dapper_lustre` get a trait name instead of a prefix?** The naming system tolerates the
   prefix for composing packages; a human should confirm rather than infer.
4. **Is a 200-hour, six-month solo budget acceptable for a library with no committed users?** If
   not, the honest cut is M3 — ship server-side SVG only at 0.1.0 and make the dual-target claim
   at 0.2.0 — which costs the headline claim its proof for one release.
5. **Repository owner is `dillydale` in `gleam.toml`; is that org created and is `dapper`
   reserved on Hex?** The naming doc says re-check before use.
