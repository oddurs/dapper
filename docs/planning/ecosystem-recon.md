# Ecosystem reconnaissance

Grounded against Hex and the Gleam package index on 2026-07-28, with every claim below either read
out of the package's own source (tarballs pulled from `repo.hex.pm`) or executed on both targets
under Gleam 1.17.0. Nothing here is inferred from documentation.

The README's premise still holds: searching the index for chart-adjacent packages returns
`fishgirl` (Mermaid in a Lustre component) and `sparklinekit 0.3.0` (344 downloads, Unicode/SVG/PNG
sparklines, dual-target). Nobody has taken the ground.

## Decisions

**1. `dapper` core depends on `gleam_stdlib` and `houdini`. Nothing else. Lustre lives in a separate
package, `dapper_lustre`.** Lustre 5.7.1 pulls `exception`, `gleam_erlang`, `gleam_json`,
`gleam_otp` and `houdini` — a seven-package manifest for what dapper needs from it (a `Element(msg)`
constructor). Gleam has no optional dependencies and no feature flags, so a core dependency on
Lustre is a tax on every server-only user and couples dapper's release cadence to a framework
currently shipping minor versions monthly. Prior art already told us not to build a `Backend` record
of functions until a third target exists (`diagrams`, the cautionary tale); the same logic says
don't build a *dependency* on the second target either. Two packages, one `Scene` ADT between them.

**2. Write dapper's own SVG string writer. Do not route the BEAM path through
`lustre/element.to_string` — use it as the differential oracle instead.** I ran the same
`Element` through `element.to_string` on both targets and got byte-identical output, including
correct `&amp;`/`&lt;`/`&quot;` escaping. That is a real and slightly surprising result, and it is
tempting: one renderer, purity for free. Reject it for three reasons. Lustre sorts attributes
alphabetically, so dapper loses control of output ordering; it emits `<rect ...></rect>` rather than
`<rect/>`, which is 7 wasted bytes per mark and ~70 KB on a 10k-mark chart; and it makes the primary
claim contingent on a third party's serialiser staying pure. But the byte-identity means
`canonicalise(dapper_svg.to_string(scene)) == canonicalise(element.to_string(dapper_lustre.view(scene)))`
is a cheap, mechanical answer to the rendering brief's "two render paths drift" failure mode.

**3. Refuse `string_width`. It is terminal-cell-width only and useless here.** Its widths are
`Int` cell counts from wcwidth / UAX#11 / mode-2027 tables (`line("안녕하세요") == 10`). There is no
notion of an advance width, let alone a proportional one. Its one arguably reusable part — grapheme
segmentation via `fold`/`Piece` — is already in stdlib: I verified `string.to_graphemes("aé😊👩‍👩‍👦")`
returns the identical 4-element list on Erlang and JavaScript. Keep the package in mind only if
dapper ever grows an ASCII/terminal renderer, where it would be exactly right.

**4. The embedded advance table is a generated `fn advance_units(codepoint: Int) -> Float` with one
`case` arm per glyph.** A `Dict` is wrong: Gleam constants cannot hold a `Dict`, so it would be
rebuilt on every measurement. `glearray` would work but adds an FFI dependency. I generated a
1400-arm `case` and compiled it: 0.3 s on Erlang, 0.03 s on JavaScript, identical results, zero
allocation, zero dependencies. This is matplotlib's bundled-DejaVu/pinned-FreeType strategy —
determinism over fidelity — expressed as a jump table.

**5. Pin dapper's own number formatter and ban `float.to_string` and `string.inspect` from every
output path.** Measured divergence on identical inputs:

| expression | Erlang | JavaScript |
|---|---|---|
| `float.to_string(0.000001)` | `1.0e-6` | `0.000001` |
| `float.to_string(-0.0)` | `-0.0` | `0.0` |
| `float.to_string(9007199254740993.0)` | `9.007199254740992e15` | `9007199254740992.0` |
| `string.inspect(1.0)` | `1.0` | `1` |
| `string.inspect(1.0e21)` | `1.0e21` | `1e+21` |

`string.inspect` is the worse offender, which kills the obvious "snapshot the `Scene` with
`string.inspect`" shortcut — dapper needs its own `Scene` pretty-printer built on its own formatter.
The scaled-integer fixed-decimal approach agrees across targets *and blows up past 2^53 on JS*
(`fixed(1.0e21, 3)` gave `999999999999999983222.784` on Erlang and `1e+21.784` on JavaScript), so
the formatter must be guarded by magnitude and route large values through a digit-assembled
scientific form. Note that `svg_path`'s `number_format.System` mode has exactly this latent bug.

**6. Never iterate a `Dict` to produce ordered output.** `dict.keys(dict.from_list([#("z",1),
#("a",2), #("m",3), #("b",4), #("qq",5)]))` returns `["a","b","m","qq","z"]` on Erlang and
`["z","m","b","a","qq"]` on JavaScript. Series order, legend order and colour assignment must come
from an explicitly ordered `List`. The shadcn-style `Dict(String, SeriesMeta)` from prior art item
11 is a *lookup*, never an ordering.

**7. Time is `gleam_time`'s `Timestamp` plus an explicit `Duration` offset. No time zones in v0.1,
stated loudly.** `gleam_time` 1.8.0 is the right base: `Timestamp` is opaque and stores
`#(seconds, nanoseconds)` specifically to dodge JS integer precision (I confirmed `Int` loses
9007199254740993 → …992 on JS), and it is pure apart from two FFI calls (`system_time`,
`local_time_offset_seconds`) that dapper will never make. But there is **no timezone story at all**:
`calendar` offers only `utc_offset` and an impure `local_offset()`. The one provider, `gtz 0.4.0`
(1346 downloads, pre-1.0), reads `/usr/share/zoneinfo` via `tzif` on Erlang and calls `Intl` on
JavaScript — a filesystem read and a browser ICU lookup, which can disagree and can fail. That is
incompatible with a pure, total, dual-target `render`. So d3-time's local-day and DST-aware
intervals are out of reach; ship UTC intervals parameterised by a caller-supplied fixed offset.

**8. Refuse `gleam_community_colour` at runtime; take it as a dev dependency.** It is RGB/HSL only
(no Lab, no Oklch, no CVD simulation), it drags `gleam_json` in for its `encode`/`decoder`, and its
opaque `Colour` structurally cannot represent the accepted `Literal | CssVar` variant. Bake the
`Scheme` palettes as literal sRGB strings. Then use `gleam_community/colour/accessibility.contrast_ratio`
in a *test* to assert every baked palette clears WCAG against both the light and dark backgrounds —
turning a claim in the README into a CI gate.

**9. Refuse `svg_path`, `gleam_community_maths`, `gleam_json`, `glearray`, `glychee`.** `svg_path`
0.21.0 is pre-1.0, ~24 modules of CSG/offset/convex-hull/boolean-ops, and depends on `vec` and
`gleam_community_maths`; dapper needs to *emit* `d` strings for lines and areas, which is under 100
lines, not parse and intersect them. `gleam_community_maths` is 124 functions for the three
(`logarithm`, `exponential`, `round_to_nearest`) that `gleam/float` already covers. `gleam_json` has
no role once the serialisable spec is refused. `glychee` wraps Elixir's benchee and is Erlang-only —
it would put an Elixir toolchain in the build of a library whose whole thesis is dual-target parity.

**10. Test with `gleeunit` + `birdie` 2.0.2 + `qcheck` 1.0.4; benchmark with `gleamy_bench`.**
`birdie`'s surface is one function, `snap(content: String, title: String) -> Nil`, reviewed with
`gleam run -m birdie`; I confirmed it runs under both `--target erlang` and `--target javascript`
and writes into a *single shared* `test/birdie_snapshots/` directory. That is the whole dual-target
guarantee for free: one accepted snapshot, two targets, and CI fails if either drifts. `qcheck`
gives integrated shrinking with a `Generator(a)` monad (`map`/`bind`/`map2`…`map6`) — exactly what
the scale round-trip laws need. `gleamy_bench` is pure Gleam, stdlib-only, with `now()` externed on
both targets.

**11. dapper core ships zero FFI, and that is a hard rule, not an aspiration.** The idiomatic
dual-target pattern in this ecosystem is `@external(erlang, …)` and `@external(javascript, …)`
stacked on one declaration with an optional pure-Gleam fallback body (`lustre.is_browser` does this
— JS external, Gleam body returning `False`), with `@target(erlang)` / `@target(javascript)`
reserved for whole declarations that cannot exist on the other side (Lustre uses it only for its OTP
server-component runtime). dapper needs neither. Every FFI need would have to work on both targets
or the primary claim breaks; the cleanest way to guarantee that is to have none.

## Concrete shapes

```gleam
// gleam.toml — dapper
[dependencies]
gleam_stdlib = ">= 1.0.0 and < 2.0.0"
houdini     = ">= 1.2.0 and < 2.0.0"

[dev-dependencies]
gleeunit               = ">= 1.0.0 and < 2.0.0"
birdie                 = ">= 2.0.0 and < 3.0.0"
qcheck                 = ">= 1.0.0 and < 2.0.0"
gleamy_bench           = ">= 0.6.0 and < 1.0.0"
gleam_community_colour = ">= 2.0.0 and < 3.0.0"  # palette contrast assertions only
lustre                 = ">= 5.0.0 and < 6.0.0"  # differential oracle only

// gleam.toml — dapper_lustre
[dependencies]
dapper = ">= 0.1.0 and < 1.0.0"
lustre = ">= 5.0.0 and < 6.0.0"
```

```gleam
// dapper/num.gleam — the pinned formatter. Total; no float.to_string anywhere.
pub opaque type Decimals
pub fn decimals(n: Int) -> Decimals            // clamped to 0..6

pub fn coord(x: Float) -> String               // 3 dp, |x| guarded < 1.0e9, "-0" -> "0"
pub fn label(x: Float, dp: Decimals) -> String // fixed decimal, trailing zeros trimmed
pub fn scientific(x: Float, dp: Decimals) -> String // digits assembled, never via Int scaling
```

```gleam
// dapper/metrics.gleam — injected value, public signature frozen at v0.1
pub type Family { Sans Mono }
pub type Weight { Regular Medium Bold }
pub type Font { Font(family: Family, size_px: Float, weight: Weight) }

pub opaque type Metrics
pub fn embedded() -> Metrics
pub fn custom(
  advance: fn(String, Font) -> Float,
  ascent: fn(Font) -> Float,
  descent: fn(Font) -> Float,
) -> Metrics
pub fn advance(metrics: Metrics, text: String, font: Font) -> Float

// dapper/internal/metrics/sans.gleam — GENERATED, not hand-written
fn advance_units(codepoint: Int) -> Float {
  case codepoint {
    32 -> 260.0
    48 -> 570.0  // tabular digits: 48..57 all identical
    // ...
    _ -> fallback_class(codepoint)
  }
}
```

```gleam
// dapper/svg.gleam — the BEAM path, pure and total
pub fn to_string(scene: Scene) -> String
pub fn to_string_tree(scene: Scene) -> StringTree   // iolist on BEAM, concat on JS

// dapper/scene.gleam — the snapshot surface; NOT string.inspect
pub fn to_debug_string(scene: Scene) -> String
```

```gleam
// dapper_lustre.gleam — the browser path
pub fn view(scene: Scene) -> Element(msg)
```

```gleam
// dapper/time.gleam — d3-time's Interval, UTC-only, offset explicit
pub opaque type Interval
pub fn utc_second() -> Interval
pub fn utc_day(offset: duration.Duration) -> Interval
pub fn every(interval: Interval, step: Int) -> Result(Interval, Nil)
pub fn floor(interval: Interval, at: Timestamp) -> Timestamp
pub fn range(interval: Interval, from: Timestamp, to: Timestamp) -> List(Timestamp)
```

```gleam
// test/differential_test.gleam — the anti-drift gate
pub fn renderers_agree_test() {
  use scene <- qcheck.given(scene_generator())
  assert canonical(svg.to_string(scene))
      == canonical(element.to_string(dapper_lustre.view(scene)))
}
```

## Task breakdown

1. **S — Scaffold two packages.** `dapper` (stdlib + houdini) and `dapper_lustre`; wire `gleam test`
   for both targets in CI as separate matrix jobs sharing one snapshot directory. *Unblocks
   everything; makes every later divergence visible on the commit that causes it.*
2. **S — `dapper/num`.** The pinned formatter plus a `qcheck` property asserting output is
   digits/`.`/`-`/`e` only, and a birdie snapshot of a fixed 200-value table. *Unblocks any code that
   emits a coordinate.*
3. **M — `Scene` ADT + `dapper/svg` writer + `to_debug_string`.** Bars as `(x0,y0,x1,y1)`, stable
   `(facet, series, datum_index)` keys, `role="img"`/`<title>`/L1 `<desc>` from the start. *Unblocks
   the whole render path and every snapshot.*
4. **S — `dapper_lustre.view` + the differential test.** Do it now, while `Scene` has four variants,
   not at v0.3 when it has twenty. *Unblocks the primary claim being testable rather than asserted.*
5. **M — Font table generator.** An offline script (not shipped, not a dependency) that reads a
   `.ttf` and emits the `case` module for one sans and one mono at upem 1000, tabular digits, with a
   per-class fallback. *Unblocks metrics, therefore axis layout, therefore everything.*
6. **S — `dapper/metrics`** over the generated table. *Unblocks tick layout.*
7. **L — `dapper/scale`.** Split `Continuous` / `Band`, d3-scale semantics ported verbatim, `qcheck`
   round-trip laws (`invert(scale(x)) ≈ x`). *Unblocks marks and axes.*
8. **M — `dapper/ticks`.** D3's 1–2–5 first, extended-Wilkinson second, consuming `Metrics` for the
   legibility term. *Unblocks axes.*
9. **M — Axes and the two-pass layout cycle.** Bounded at two passes. Never a fixpoint.
10. **M — `bar`, `line`, `point` over the 1×1 pane grid**, plus the baked `Scheme` and its
    contrast-ratio test.
11. **S — `dapper/validate`.** Total, returns `List(Diagnostic)`, empty at v0.1 apart from empty
    domain, log-crossing-zero and colour cardinality.
12. **S — `gleamy_bench` harness**, run manually, not a CI gate.

## Risks and unknowns

- **Lustre 5.x churn.** Six minor releases in the window I sampled. The separate-package split
  contains the blast radius, but `dapper_lustre` will need releases dapper core does not.
- **Attribute-order canonicalisation in the differential test** could quietly become permissive
  enough to stop catching real drift. Keep `canonical/1` to sorting attributes and normalising
  self-closing tags — nothing else, ever.
- **The generated font table is a licensing surface.** Advance widths are arguably not copyrightable,
  but the source font's licence still needs reading before anything ships.
- **`birdie` 2.0.2 depends on `glance` to parse test sources.** A Gleam syntax change could break the
  review CLI ahead of a `glance` release. Dev-only, so survivable.
- **Erlang float→string is used by `float.to_string` inside stdlib helpers** that dapper may reach
  transitively. Add a grep-based CI check banning `float.to_string`/`string.inspect` in `src/`.

## What is explicitly NOT in v0.1

Time zones of any kind (`gtz`, `gtempo`). Colour-space conversion (Lab/Oklch, `niji`). Any runtime
dependency on `gleam_json`, `svg_path`, `gleam_community_maths`, `string_width`, `glearray`.
Canvas-backed `Metrics` (the signature exists; the implementation does not). A terminal renderer.
Benchmarks as a CI gate. Any FFI in core.

## Open questions needing a human call

1. **Which font do we ship metrics for, and under what licence?** Inter and Source Sans 3 are the
   obvious candidates; matplotlib's precedent is to bundle rather than detect. This blocks task 5,
   which blocks most of the plan.
2. **Two packages or one?** I have recommended `dapper` + `dapper_lustre` on dependency-weight
   grounds. The counter-argument is real: Lustre is where the users are, a second package is a
   second release process for a solo maintainer, and "just add dapper" is a better first experience.
   If you would rather ship one package, say so now — merging later is easy, splitting later is a
   breaking change for everyone.
3. **Does `dapper_lustre` get published at v0.1 or v0.2?** The primary claim only needs the BEAM
   path plus the differential test to be *demonstrably* true. Publishing the Lustre package can lag
   by one release without weakening the claim.
