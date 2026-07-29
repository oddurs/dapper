//// Properties of scales, over generated inputs.
////
//// The fixture tests prove dapper agrees with d3 on the cases someone thought
//// to list. These prove the invariants hold everywhere else — which is the part
//// that matters when a real domain arrives, because real domains are not the
//// round numbers anyone writes into a fixture table.
////
//// Every property runs on both targets. A property that held on one and not the
//// other would be the most expensive kind of bug this project can have, since it
//// would mean a chart rendered on the server and the same chart rendered in the
//// browser disagree.

import dapper/format
import dapper/scale
import dapper/scale/domain
import dapper/ticks
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import qcheck

/// Domains and ranges a chart might plausibly carry: spanning several orders of
/// magnitude, both signs, and never so extreme that the comparison tolerance
/// stops meaning anything.
fn reasonable_float() -> qcheck.Generator(Float) {
  qcheck.bounded_float(-100_000.0, 100_000.0)
}

fn close(a: Float, b: Float, tolerance: Float) -> Bool {
  float.absolute_value(a -. b) <=. tolerance
}

// --- continuous scales ----------------------------------------------------

pub fn invert_undoes_convert_test() {
  // The round trip is the property the whole axis-and-interaction story rests
  // on: an axis is a scale read backwards, and so is a brush.
  use #(d0, span, value) <- qcheck.given(qcheck.tuple3(
    reasonable_float(),
    qcheck.bounded_float(1.0, 10_000.0),
    reasonable_float(),
  ))
  let s = scale.linear(#(d0, d0 +. span), #(0.0, 600.0))
  let round_tripped = scale.invert(s, scale.convert(s, value))
  // Tolerance scales with magnitude: a fixed epsilon would be vacuous for tiny
  // values and unachievable for large ones.
  let tolerance = float.absolute_value(value) *. 1.0e-9 +. 1.0e-6
  close(round_tripped, value, tolerance) |> should.be_true
}

pub fn convert_is_monotonic_test() {
  use #(d0, span, a, b) <- qcheck.given(qcheck.tuple4(
    reasonable_float(),
    qcheck.bounded_float(1.0, 10_000.0),
    reasonable_float(),
    reasonable_float(),
  ))
  let s = scale.linear(#(d0, d0 +. span), #(0.0, 600.0))
  case a <. b {
    True -> { scale.convert(s, a) <=. scale.convert(s, b) } |> should.be_true
    False -> True |> should.be_true
  }
}

pub fn endpoints_map_exactly_test() {
  // Approximately-right endpoints are how a bar ends up one pixel outside the
  // plot area, so this is exact equality rather than a tolerance.
  use #(d0, span) <- qcheck.given(qcheck.tuple2(
    reasonable_float(),
    qcheck.bounded_float(1.0, 10_000.0),
  ))
  let s = scale.linear(#(d0, d0 +. span), #(0.0, 600.0))
  scale.convert(s, d0) |> should.equal(0.0)
  scale.convert(s, d0 +. span) |> should.equal(600.0)
}

pub fn clamping_keeps_output_within_the_range_test() {
  use #(d0, span, value) <- qcheck.given(qcheck.tuple3(
    reasonable_float(),
    qcheck.bounded_float(1.0, 10_000.0),
    reasonable_float(),
  ))
  let s =
    scale.linear(#(d0, d0 +. span), #(0.0, 600.0))
    |> scale.clamp(True)
  let y = scale.convert(s, value)
  { y >=. 0.0 && y <=. 600.0 } |> should.be_true
}

// --- ticks ----------------------------------------------------------------

pub fn ticks_fall_within_the_domain_test() {
  // A tick outside the domain draws a label outside the plot area.
  use #(d0, span, count) <- qcheck.given(qcheck.tuple3(
    reasonable_float(),
    qcheck.bounded_float(1.0, 10_000.0),
    qcheck.bounded_int(1, 20),
  ))
  let d1 = d0 +. span
  ticks.ticks(d0, d1, count)
  |> list.each(fn(t) { { t >=. d0 && t <=. d1 } |> should.be_true })
}

pub fn ticks_are_strictly_ascending_test() {
  use #(d0, span, count) <- qcheck.given(qcheck.tuple3(
    reasonable_float(),
    qcheck.bounded_float(1.0, 10_000.0),
    qcheck.bounded_int(1, 20),
  ))
  let values = ticks.ticks(d0, d0 +. span, count)
  ascending(values) |> should.be_true
}

pub fn nice_never_narrows_a_domain_test() {
  // `nice` extends outward. Narrowing would clip data the user gave us.
  use #(d0, span, count) <- qcheck.given(qcheck.tuple3(
    reasonable_float(),
    qcheck.bounded_float(1.0, 10_000.0),
    qcheck.bounded_int(2, 20),
  ))
  let d1 = d0 +. span
  let #(lo, hi) = ticks.nice(d0, d1, count)
  { lo <=. d0 && hi >=. d1 } |> should.be_true
}

// --- band scales ----------------------------------------------------------

pub fn bands_partition_the_range_without_overlap_test() {
  // Overlapping bands mean overlapping bars, which is a chart that lies.
  use #(n, width) <- qcheck.given(qcheck.tuple2(
    qcheck.bounded_int(1, 12),
    qcheck.bounded_float(50.0, 2000.0),
  ))
  let s = scale.band(labels(n), #(0.0, width)) |> scale.padding_inner(0.1)
  let starts = scale.band_positions(s)
  let w = scale.bandwidth(s)
  ordered_pairs(starts)
  |> list.each(fn(pair) {
    let #(earlier, later) = pair
    { earlier +. w <=. later +. 1.0e-9 } |> should.be_true
  })
}

pub fn bands_stay_inside_the_range_test() {
  use #(n, width) <- qcheck.given(qcheck.tuple2(
    qcheck.bounded_int(1, 12),
    qcheck.bounded_float(50.0, 2000.0),
  ))
  let s = scale.band(labels(n), #(0.0, width))
  let w = scale.bandwidth(s)
  scale.band_positions(s)
  |> list.each(fn(start) {
    { start >=. -1.0e-9 && start +. w <=. width +. 1.0e-9 } |> should.be_true
  })
}

pub fn every_category_resolves_to_a_position_test() {
  use n <- qcheck.given(qcheck.bounded_int(1, 12))
  let names = labels(n)
  let s = scale.band(names, #(0.0, 600.0))
  names
  |> list.each(fn(name) {
    case scale.band_convert(s, name) {
      Ok(_) -> True |> should.be_true
      Error(Nil) -> False |> should.be_true
    }
  })
}

// --- domain ---------------------------------------------------------------

pub fn domain_bounds_are_never_zero_width_test() {
  // Zero width would divide by zero the moment a scale converted anything.
  use #(a, b) <- qcheck.given(qcheck.tuple2(
    reasonable_float(),
    reasonable_float(),
  ))
  let #(lo, hi) = domain.bounds(domain.of_numbers([a, b]))
  { hi >. lo } |> should.be_true
}

pub fn domain_union_is_associative_test() {
  // Associativity is what lets training be a fold. Without it, the order layers
  // are combined in would change the axis.
  use #(a, b, c) <- qcheck.given(qcheck.tuple3(
    reasonable_float(),
    reasonable_float(),
    reasonable_float(),
  ))
  let x = domain.Numeric(a, a)
  let y = domain.Numeric(b, b)
  let z = domain.Numeric(c, c)
  domain.union(domain.union(x, y), z)
  |> should.equal(domain.union(x, domain.union(y, z)))
}

// --- format ---------------------------------------------------------------

pub fn coord_never_produces_exponent_notation_test() {
  // SVG accepts exponent notation and renderers disagree about parsing it.
  use x <- qcheck.given(reasonable_float())
  format.coord(x) |> string.contains("e") |> should.be_false
}

pub fn coord_never_produces_negative_zero_test() {
  use x <- qcheck.given(qcheck.bounded_float(-0.004, 0.004))
  case format.coord(x) {
    "-0" -> False |> should.be_true
    "-0.0" -> False |> should.be_true
    _ -> True |> should.be_true
  }
}

// --- helpers --------------------------------------------------------------

fn labels(n: Int) -> List(String) {
  build_labels(0, n, [])
}

fn build_labels(i: Int, n: Int, acc: List(String)) -> List(String) {
  case i >= n {
    True -> list.reverse(acc)
    False -> build_labels(i + 1, n, ["c" <> int.to_string(i), ..acc])
  }
}

fn ascending(values: List(Float)) -> Bool {
  case values {
    [] | [_] -> True
    [a, b, ..rest] ->
      case a <. b {
        True -> ascending([b, ..rest])
        False -> False
      }
  }
}

fn ordered_pairs(values: List(Float)) -> List(#(Float, Float)) {
  list.zip(values, list.drop(values, 1))
}
