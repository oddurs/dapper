//// Mapping data values to positions.
////
//// Three types rather than one, split by **what they can actually do**
//// (decision S2):
////
//// - `Scale` is continuous. It converts, and it inverts, and it can produce
////   ticks and be extended to nice bounds.
//// - `BandScale` maps discrete categories to intervals. It has a `bandwidth`
////   and a `step`, and it has **no `invert`** — the inverse of a band scale is
////   a category, not a number, and pretending otherwise is how libraries end up
////   returning a plausible wrong answer.
//// - `OrdinalScale` maps categories to arbitrary values, which is how a colour
////   channel works.
////
//// Faking a uniform interface across these is the mistake `elm-visualization`
//// documented in its own README: "the cost is a certain ugliness and complexity
//// of the type signatures… I recommend ignoring the types." Splitting them
//// means `bar` can require a `BandScale` in its signature and Observable Plot's
//// commonest runtime error becomes a compile error.
////
//// Scales hold **parameters, never closures** (decision S1). A record of
//// functions cannot be printed, compared, or inspected by `validate`, and
//// snapshot debugging against an opaque closure is guesswork.
////
//// The band and point layouts are ports of d3-scale 4.0.2, checked case by case
//// against generated fixtures.

import dapper/format
import dapper/scale/domain.{type Domain}
import dapper/ticks
import gleam/float
import gleam/int
import gleam/list

// --- continuous -----------------------------------------------------------

/// What kind of continuous transform sits between domain and range.
///
/// Opaque, and holding `Time(Zone)` in reserve. Time scales are cut to v0.2
/// (decision S7); reserving the variant inside an opaque type is what makes
/// adding them a non-breaking change rather than a major version.
pub opaque type ContinuousKind {
  LinearKind
  LogKind(base: Float)
}

/// A continuous scale: a domain interval, a range interval, and a transform.
pub opaque type Scale {
  Scale(
    kind: ContinuousKind,
    d0: Float,
    d1: Float,
    r0: Float,
    r1: Float,
    clamp: Bool,
  )
}

/// A linear scale over the given domain and range.
///
/// Degenerate domains are resolved by `domain.bounds` before they arrive here,
/// so a zero-width domain cannot reach the division in `convert`.
pub fn linear(from: #(Float, Float), to: #(Float, Float)) -> Scale {
  let #(d0, d1) = from
  let #(r0, r1) = to
  Scale(LinearKind, d0, d1, r0, r1, False)
}

/// A logarithmic scale.
///
/// A log domain cannot contain zero, and a domain crossing zero has no
/// meaningful log scale at all. Rather than reject it — `render` is total —
/// non-positive values are clamped to the smallest positive value in the domain
/// when converting, and the condition is left for `validate` to report as
/// `LogDomainCrossesZero` (decision P6). A chart that silently renders wrong is
/// worse than one that renders oddly and says so.
pub fn log(from: #(Float, Float), to: #(Float, Float), base: Float) -> Scale {
  let #(d0, d1) = from
  let #(r0, r1) = to
  Scale(LogKind(base), d0, d1, r0, r1, False)
}

/// Restrict output to the range, so values outside the domain do not draw
/// outside the plot area.
pub fn clamp(scale: Scale, on: Bool) -> Scale {
  Scale(..scale, clamp: on)
}

pub fn domain_of(scale: Scale) -> #(Float, Float) {
  #(scale.d0, scale.d1)
}

pub fn range_of(scale: Scale) -> #(Float, Float) {
  #(scale.r0, scale.r1)
}

/// Map a data value to a position.
pub fn convert(scale: Scale, value: Float) -> Float {
  let t = normalise(scale, value)
  let t = case scale.clamp {
    True -> clamp_unit(t)
    False -> t
  }
  scale.r0 +. t *. { scale.r1 -. scale.r0 }
}

/// Map a position back to a data value.
///
/// The inverse is what makes an axis possible and what makes interaction
/// possible — Wickham's point that a legend is a scale read backwards, and
/// Bostock's that a brush is the same thing.
pub fn invert(scale: Scale, position: Float) -> Float {
  let span = scale.r1 -. scale.r0
  let t = case span == 0.0 {
    True -> 0.0
    False -> { position -. scale.r0 } /. span
  }
  let t = case scale.clamp {
    True -> clamp_unit(t)
    False -> t
  }
  case scale.kind {
    LinearKind -> scale.d0 +. t *. { scale.d1 -. scale.d0 }
    LogKind(base) -> {
      let l0 = log_of(scale.d0, base)
      let l1 = log_of(scale.d1, base)
      float.power(base, l0 +. t *. { l1 -. l0 })
      |> result_or(scale.d0)
    }
  }
}

/// Tick values across the domain, approximately `count` of them.
pub fn scale_ticks(scale: Scale, count: Int) -> List(Float) {
  case scale.kind {
    LinearKind -> ticks.ticks(scale.d0, scale.d1, count)
    LogKind(base) -> log_ticks(scale.d0, scale.d1, base, count)
  }
}

/// The step between this scale's ticks, for choosing label precision.
pub fn scale_tick_step(scale: Scale, count: Int) -> Result(Float, Nil) {
  ticks.tick_step(scale.d0, scale.d1, count)
}

/// Extend the domain outward to round values.
pub fn nice(scale: Scale, count: Int) -> Scale {
  case scale.kind {
    LogKind(_) -> scale
    LinearKind -> {
      let #(d0, d1) = ticks.nice(scale.d0, scale.d1, count)
      Scale(..scale, d0: d0, d1: d1)
    }
  }
}

// --- band -----------------------------------------------------------------

/// A scale from categories to equal-width intervals.
///
/// Has no `invert`, deliberately — see the module documentation.
pub opaque type BandScale {
  BandScale(
    categories: List(String),
    r0: Float,
    r1: Float,
    padding_inner: Float,
    padding_outer: Float,
    align: Float,
  )
}

/// A band scale over the given categories, filling the range.
pub fn band(categories: List(String), to: #(Float, Float)) -> BandScale {
  let #(r0, r1) = to
  BandScale(categories, r0, r1, 0.0, 0.0, 0.5)
}

/// A point scale: a band scale whose bands have collapsed to zero width.
///
/// This is not an analogy. d3 implements `scalePoint` as a band scale with
/// `paddingInner` pinned to 1, and so does this — one layout algorithm, not two
/// that must be kept in agreement.
pub fn point(categories: List(String), to: #(Float, Float)) -> BandScale {
  let #(r0, r1) = to
  BandScale(categories, r0, r1, 1.0, 0.0, 0.5)
}

/// Space between adjacent bands, as a fraction of the step. `0.0` to `1.0`.
pub fn padding_inner(scale: BandScale, amount: Float) -> BandScale {
  BandScale(..scale, padding_inner: clamp_unit(amount))
}

/// Space before the first band and after the last, as a fraction of the step.
pub fn padding_outer(scale: BandScale, amount: Float) -> BandScale {
  BandScale(..scale, padding_outer: amount)
}

/// Where to place leftover space: `0.0` before, `1.0` after, `0.5` centred.
pub fn align(scale: BandScale, amount: Float) -> BandScale {
  BandScale(..scale, align: clamp_unit(amount))
}

/// A band scale over a domain's categories.
pub fn band_of_domain(d: Domain, to: #(Float, Float)) -> BandScale {
  band(domain.categories(d), to)
}

/// The distance between the start of one band and the start of the next.
pub fn step(scale: BandScale) -> Float {
  let n = int.to_float(list.length(scale.categories))
  let #(start, stop) = ordered_range(scale)
  let divisor =
    float.max(1.0, n -. scale.padding_inner +. scale.padding_outer *. 2.0)
  { stop -. start } /. divisor
}

/// The width of a single band. Zero for a point scale.
pub fn bandwidth(scale: BandScale) -> Float {
  step(scale) *. { 1.0 -. scale.padding_inner }
}

/// The start position of a category's band, or `Error` if it is not in the
/// domain.
///
/// A `Result` rather than a default: an unknown category is a data problem, and
/// silently drawing it at zero is how a mislabelled bar ends up looking like a
/// real one.
pub fn band_convert(scale: BandScale, category: String) -> Result(Float, Nil) {
  case index_of(scale.categories, category, 0) {
    Error(Nil) -> Error(Nil)
    Ok(i) -> {
      let positions = band_positions(scale)
      list_at(positions, i)
    }
  }
}

/// Every band start, in domain order.
pub fn band_positions(scale: BandScale) -> List(Float) {
  let n = list.length(scale.categories)
  let n_float = int.to_float(n)
  let #(range_start, stop) = ordered_range(scale)
  let s = step(scale)
  let start =
    range_start
    +. { stop -. range_start -. s *. { n_float -. scale.padding_inner } }
    *. scale.align

  let values = build_positions(0, n, start, s, [])
  case scale.r1 <. scale.r0 {
    True -> list.reverse(values)
    False -> values
  }
}

pub fn categories_of(scale: BandScale) -> List(String) {
  scale.categories
}

// --- ordinal --------------------------------------------------------------

/// A mapping from categories to arbitrary values, cycling when the values run
/// out. This is how a colour channel assigns colours to series.
pub opaque type OrdinalScale(a) {
  OrdinalScale(categories: List(String), values: List(a))
}

pub fn ordinal(categories: List(String), values: List(a)) -> OrdinalScale(a) {
  OrdinalScale(categories, values)
}

/// The value for a category.
///
/// `Error` when the category is unknown, or when there are no values to cycle
/// through at all — a palette of zero colours is not a colour.
pub fn ordinal_convert(
  scale: OrdinalScale(a),
  category: String,
) -> Result(a, Nil) {
  case index_of(scale.categories, category, 0), list.length(scale.values) {
    _, 0 -> Error(Nil)
    Error(Nil), _ -> Error(Nil)
    Ok(i), n -> list_at(scale.values, i % n)
  }
}

// --- internals ------------------------------------------------------------

/// Position within the domain as a fraction, before the range is applied.
fn normalise(scale: Scale, value: Float) -> Float {
  case scale.kind {
    LinearKind -> {
      let span = scale.d1 -. scale.d0
      case span == 0.0 {
        True -> 0.0
        False -> { value -. scale.d0 } /. span
      }
    }
    LogKind(base) -> {
      let l0 = log_of(scale.d0, base)
      let l1 = log_of(scale.d1, base)
      let span = l1 -. l0
      case span == 0.0 {
        True -> 0.0
        False -> { log_of(value, base) -. l0 } /. span
      }
    }
  }
}

/// Logarithm, with non-positive input clamped to the smallest positive value in
/// the domain rather than producing an error `render` cannot propagate.
fn log_of(value: Float, base: Float) -> Float {
  let safe = case value >. 0.0 {
    True -> value
    False -> smallest_positive
  }
  case float.logarithm(safe), float.logarithm(base) {
    Ok(a), Ok(b) if b != 0.0 -> a /. b
    _, _ -> 0.0
  }
}

const smallest_positive = 1.0e-10

/// Log ticks are the powers of the base within the domain. Where fewer than two
/// powers fit, the linear algorithm gives a more useful axis than a single tick.
fn log_ticks(d0: Float, d1: Float, base: Float, count: Int) -> List(Float) {
  let lo = format.exponent10(d0)
  let hi = format.exponent10(d1)
  case hi - lo >= 1 && base == 10.0 {
    False -> ticks.ticks(d0, d1, count)
    True -> powers_from(hi, lo, [])
  }
}

fn powers_from(e: Int, limit: Int, acc: List(Float)) -> List(Float) {
  case e < limit {
    True -> acc
    False -> powers_from(e - 1, limit, [format.power_of_ten(e), ..acc])
  }
}

fn ordered_range(scale: BandScale) -> #(Float, Float) {
  case scale.r1 <. scale.r0 {
    True -> #(scale.r1, scale.r0)
    False -> #(scale.r0, scale.r1)
  }
}

fn build_positions(
  i: Int,
  n: Int,
  start: Float,
  step_size: Float,
  acc: List(Float),
) -> List(Float) {
  case i >= n {
    True -> list.reverse(acc)
    False ->
      build_positions(i + 1, n, start, step_size, [
        start +. step_size *. int.to_float(i),
        ..acc
      ])
  }
}

fn index_of(items: List(String), target: String, i: Int) -> Result(Int, Nil) {
  case items {
    [] -> Error(Nil)
    [first, ..rest] ->
      case first == target {
        True -> Ok(i)
        False -> index_of(rest, target, i + 1)
      }
  }
}

fn list_at(items: List(a), index: Int) -> Result(a, Nil) {
  case items, index {
    [], _ -> Error(Nil)
    [first, ..], 0 -> Ok(first)
    [_, ..rest], n -> list_at(rest, n - 1)
  }
}

fn clamp_unit(t: Float) -> Float {
  float.min(float.max(t, 0.0), 1.0)
}

fn result_or(r: Result(a, e), fallback: a) -> a {
  case r {
    Ok(v) -> v
    Error(_) -> fallback
  }
}
