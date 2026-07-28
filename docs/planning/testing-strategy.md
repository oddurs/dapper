# Testing

Verification for a library whose correctness is geometric, whose headline claim is
*cross-target identity*, and whose maintainer is one person. The strategy is four layers,
ordered so that the cheapest layer fires first on any given bug.

## Decisions

**1. Cross-target equivalence is tested by construction, not by diffing.** There is no
"run on Erlang, run on JS, diff the outputs" harness. There is one committed set of golden
files, and the *same* suite runs twice — `gleam test --target erlang` and
`gleam test --target javascript` — against it. Divergence is a test failure on whichever
target drifted, with no bespoke infrastructure to maintain. This is only sound because two
upstream decisions make it sound: embedded text metrics default on *both* targets
(`rendering-and-output.md` §3 — matplotlib's pinned-FreeType lesson), and dapper's own
pinned float formatter (`d3-and-observable-plot.md` §5: "the cross-target risk is not float
math… but float-to-string formatting"). Those two decisions are what the golden corpus is
really auditing.

**2. Snapshot the `Scene` *and* the SVG, as separate artifacts.** `grammar-of-graphics.md`
line 126 says snapshot `build`, not only the SVG, and it is right for a diagnostic reason:
a Scene diff means the *geometry* changed; an SVG-only diff means *serialisation or
formatting* changed. Two snapshots localise the bug before you read a line of it. A single
SVG snapshot conflates a scale bug with an attribute-ordering change.

**3. Different mechanisms for the two, deliberately.** Scene snapshots go through `birdie`
(text, line-oriented, terminal-reviewable). SVG goldens are committed as **real `.svg`
files** under `test/golden/svg/`, compared by a ~30-line helper over `simplifile`. This is
the answer to "how do you review a 400-line path-data diff": you open the file in a
browser or in GitHub's file view and *look at the chart*. Birdie's own snapshot format
carries a metadata header, so a birdie snapshot cannot also be a viewable SVG — that is
the whole justification for hand-rolling one small golden helper rather than using birdie
for everything. It has a second payoff: the helper is plain Gleam + simplifile and works
identically on both targets, so the cross-target-critical suite does not depend on birdie
supporting `--target javascript`.

**4. The two render paths are proved equal, not tested twice.** `rendering-and-output.md`
line 83 names the risk: "an SVG-string path plus a DOM path means testing one and shipping
two." Mitigation: both renderers consume the same `Scene` and share one
`attributes(Node) -> List(#(String, String))` function, so
`scene.to_svg_string(s)` and `element.to_string(scene.to_lustre(s))` must be *byte
equal*. One property over the whole fixture corpus retires the drift risk.

**5. Property tests own correctness; goldens only detect change.** Goldens cannot tell you
a chart is *right*, only that it is the same as yesterday. The invariants that assert
rightness are properties, via `qcheck`: round-trip, monotonicity, endpoint exactness, tick
containment and 1–2–5 form, band partitioning, and finiteness. Prior art backs the
round-trip specifically — `prior-art.md` "What every serious library converges on" #1:
invertible scales, where the inverse *is* the axis and the interaction primitive.

**6. Generators are domain-restricted, and degeneracy is unit-tested.** Naive `qcheck`
float generators emit infinities, NaN and zero-width domains, which will drown the suite in
false failures. Property inputs come from a `test/gen` module (`finite_float`,
`nondegenerate_domain`, `positive_domain`). Degenerate cases — empty data, single datum,
all-values-equal, log domain crossing zero, domain of `[5.0, 5.0]` — are *named unit
tests with exact expectations*, because each has a specific correct behaviour that
`validate` must diagnose. Never leave those to a random generator.

**7. Finiteness is a first-class invariant.** `scene.is_finite(Scene) -> Bool` asserted
over every fixture and every generated chart. `NaN` in path data is the single most common
geometric failure in this class of library, and catching it at the Scene layer beats
finding `d="M NaN,12 L…"` in a snapshot.

**8. No pixel-diff visual regression in v0.1 — but a renderability smoke test.** Golden
PNGs demand a pinned rasteriser and break on every version bump (matplotlib pins FreeType
precisely because of this). The value they add over a Scene snapshot plus a human looking
at the `.svg` is low. What *is* worth 30 lines of CI: pipe each golden `.svg` through a
pinned `resvg` binary and assert exit 0 and a non-blank PNG (>1% non-background pixels).
That catches "the string is malformed and browsers render nothing" — the one failure a
text snapshot cannot see — with no goldens to churn. `resvg` is a rasteriser, not a
browser; the library still ships no headless anything.

**9. v0.1 commits to asymptotics, not milliseconds.** Wall-clock in CI is noise, and a
solo maintainer cannot babysit a flaky perf gate. The committed budget is: string building
is O(n) in mark count (`string_tree`, never `<>` accumulation), asserted by a scaling test
(10× the marks must cost < 15× the time), plus a hand-measured reference table in
`docs/benchmarks.md` refreshed at each release. Benchmarks run on demand via `glychee`,
never as a gate. `prior-art.md` sets the design ceiling — ~10k marks of SVG is fine, past
that the answer is a transform — so the number that matters is that 10k marks stays
comfortably interactive on the BEAM, and that is a release-time measurement, not a CI
assertion.

## Concrete shapes

```gleam
// test/support/golden.gleam — the SVG golden helper (both targets)
pub fn assert_svg(name: String, actual: String) -> Nil
// reads test/golden/svg/<name>.svg; on mismatch writes <name>.svg.new and fails
// with a first-differing-line report. GOLDEN_ACCEPT=1 rewrites in place.

// test/support/approx.gleam
pub fn approx(a: Float, b: Float, rel: Float) -> Bool

// test/gen/floats.gleam — qcheck generators, degeneracy excluded on purpose
pub fn finite_float() -> qcheck.Generator(Float)          // |x| in [1e-6, 1e9]
pub fn nondegenerate_domain() -> qcheck.Generator(#(Float, Float))
pub fn positive_domain() -> qcheck.Generator(#(Float, Float))
pub fn band_case() -> qcheck.Generator(#(List(String), #(Float, Float), Float))
```

Gleam has no existentials, so a heterogeneous list of `Chart(row)` is not expressible.
The fixture corpus therefore stores *thunks that have already erased `row`*:

```gleam
// test/fixtures/charts.gleam
pub type Fixture {
  Fixture(name: String, scene: fn() -> Scene, svg: fn() -> String)
}
pub fn all() -> List(Fixture)
```

Snapshotting requires a deterministic printer. `string.inspect` is **banned** in snapshots —
its float rendering is target-dependent, which would manufacture exactly the divergence the
suite exists to detect. Instead, public API (users snapshot-testing their own charts need it
too, so it is semver'd from day one):

```gleam
// src/dapper/scene.gleam
pub fn to_debug_string(scene: Scene) -> String
// one node per line, one PathCommand per line, attributes in a fixed order,
// all floats through fmt.round_to(3) — so a diff is line-oriented and sub-pixel
// noise never churns.
pub fn is_finite(scene: Scene) -> Bool
```

Representative properties:

```gleam
pub fn linear_round_trips_test() {
  use #(domain, range, x) <- qcheck.given(gen.linear_case())
  let s = scale.linear(domain, range)
  assert approx.approx(scale.invert(s, scale.convert(s, x)), x, 1.0e-9)
}

pub fn ticks_lie_within_domain_test() {
  use #(lo, hi) <- qcheck.given(gen.nondegenerate_domain())
  let ts = ticks.of(scale.linear(#(lo, hi), #(0.0, 100.0)), 5)
  assert list.all(ts, fn(t) { t >=. lo && t <=. hi })
  assert ticks.is_sorted_strictly(ts)
  assert list.length(ts) >= 3 && list.length(ts) <= 11   // requested 5, ±
}

pub fn band_positions_partition_the_range_test() {
  use #(cats, range, pad) <- qcheck.given(gen.band_case())
  let s = scale.band(cats, range, pad)
  let xs = list.map(cats, scale.band_convert(s, _))
  assert list.all(list.window_by_2(xs), fn(p) {
    p.0 +. scale.bandwidth(s) <=. p.1 +. 1.0e-9        // no overlap
  })
  assert list.first(xs) |> result.unwrap(0.0) >=. range.0
}

pub fn renderers_agree_test() {
  use f <- list.each(fixtures.all())
  assert scene.to_svg_string(f.scene()) == element.to_string(scene.to_lustre(f.scene()))
}
```

Float-formatter conformance is a flat table, run on both targets, and is the tripwire that
must fire *before* any snapshot does:

```gleam
// test/unit/fmt_test.gleam
const cases: List(#(Float, String)) = [
  #(0.1, "0.1"), #(1.0, "1"), #(1.0e21, "1e21"), #(-0.0, "0"),
  #(0.30000000000000004, "0.3"), #(1.5e-7, "0.00000015"),
]
```

## Task breakdown

1. **S — CI matrix and test skeleton.** Add `--target javascript` (Node LTS) job alongside
   Erlang; `gleam format --check`; dev-deps `qcheck`, `birdie`, `simplifile`.
   *Unblocks everything.*
2. **S — `dapper/internal/fmt` + conformance table.** The pinned formatter and its
   two-target test. *Unblocks every golden and every snapshot.*
3. **S — Spike: does `birdie` run under `--target javascript`?** Timeboxed. If no, Scene
   snapshots become Erlang-only and the `.svg` goldens carry the cross-target claim alone —
   which decision 3 already makes survivable. *Unblocks task 7.*
4. **M — `test/gen` + `approx`.** Generators with degeneracy excluded. *Unblocks all
   properties.*
5. **M — Scale property suite** (linear, log, time, band): round-trip, monotonicity,
   endpoint exactness, `nice` containment, band partitioning. *Unblocks scale sign-off.*
6. **S — Tick property suite**: containment, strict ordering, 1–2–5 step form, count within
   [n/2, 2n]. *Unblocks axis work.*
7. **M — Golden harness** (`test/support/golden.gleam`, `.new` files, `GOLDEN_ACCEPT=1`).
   *Unblocks SVG goldens.*
8. **M — Fixture corpus**: 15–20 deliberately minimal charts (one axis; three bars; a
   two-point line; a single-category band; negative domain; log decade) plus 3 kitchen-sink
   ones. Minimal-and-many beats few-and-realistic, because a minimal fixture's diff is
   readable. *Unblocks 9, 10, 12.*
9. **S — `scene.to_debug_string` + birdie Scene snapshots** over the corpus.
10. **S — Renderer agreement test** (string vs `element.to_string`).
11. **S — Finiteness and totality properties**: no `NaN`/`Infinity` in any Scene or output;
    `render` and `validate` never panic on hostile input.
12. **S — `resvg` renderability smoke job.** Pinned version, exit-code + non-blank check.
13. **M — `glychee` benches, `docs/benchmarks.md`, and the O(n) scaling test.**
14. **S — CONTRIBUTING: "how to review a golden diff."** Written procedure: read the Scene
    diff first, then open the `.svg`; never accept a corpus-wide rewrite without naming the
    default that changed.

## Risks and unknowns

- **Snapshot-review fatigue is the number-one failure mode.** Any change to a default
  (padding, tick count, margin) rewrites the whole corpus, and a solo maintainer will
  rubber-stamp it. Mitigations: defaults live in one module; fixtures that are not *about*
  a default pass it explicitly; and CONTRIBUTING requires naming the cause of a mass rewrite
  in the commit message.
- **`birdie` on the JavaScript target is unverified** (task 3). Contingency is already
  designed in.
- **`glychee` wraps Benchee, which needs an Elixir toolchain.** Acceptable locally,
  unacceptable in CI — which is fine, since benchmarks are not a gate.
- **`qcheck` shrinking quality on `Float` is unknown.** If counterexamples shrink poorly,
  property failures become undiagnosable; fallback is to log the full derived case
  (domain, range, input, convert, invert) on failure rather than rely on the shrunk value.
- **Node is the only JS runtime tested.** Bun (JSC) and Deno are unverified. Float printing
  is spec-exact in ECMAScript so divergence is unlikely, but `simplifile` behaviour is not.
- **Time-scale properties depend on the unsettled `gleam_time` decision**; the tick and
  round-trip properties for `Time` cannot be written until that lands.
- **Goldens cannot detect a chart that is consistently, correctly wrong.** Only the property
  invariants and human eyes do. Do not let a green suite imply visual correctness.

## What is explicitly NOT in v0.1

Pixel-diff visual regression and golden PNGs. Headless browsers, Playwright, jsdom, or any
DOM-dependent test. Mutation testing. Coverage measurement (there is no trustworthy Gleam
tooling; a fabricated number is worse than none). Property-based generation of whole
`Chart(row)` values — a chart generator is an L-sized project and belongs in v0.2 once the
grammar has settled. Performance regression gating in CI. XML-parser validation of the SVG
(the `resvg` smoke test subsumes the useful part). Testing on Deno or Bun. Accessibility
output testing beyond asserting that `role`, `<title>` and the L1 `<desc>` are present in
every golden.

## Open questions needing a human call

1. **Is a pinned `resvg` binary in CI compatible with the project's "no headless browser"
   stance?** I say yes — it is a static rasteriser with no JS engine and no DOM, and it
   never touches the shipped library — but it is a positioning call, and the README makes a
   strong claim that deserves an explicit sign-off rather than a quiet exception.
2. **What relative epsilon does `log` round-tripping actually need?** `1e-9` is the opening
   bid for linear; log over many decades may need looser, and the honest answer is
   empirical. Settle it once the scale lands, and *document the number in the public docs* —
   it is part of the contract.
3. **Do users get the golden helper too?** `scene.to_debug_string` is public. Shipping a
   `dapper/testing` module with `assert_svg` would make dapper's own strategy available to
   dashboard authors — genuinely differentiating, but it is public surface to support
   forever. My inclination is to defer to v0.2 and keep the helper in `test/`.
4. **Does the SVG golden corpus get committed at full precision or rounded?** Rounding
   geometry to 3 dp in the *output* (not just the debug printer) would make goldens
   maximally stable and shrink the payload, but it is a rendering decision with visual
   consequences, not a testing one, and it belongs to the rendering stream.
