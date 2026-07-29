//// `dapper/scale` against d3-scale 4.0.2 fixtures, plus the behaviour the
//// fixtures cannot express: the degenerate cases decision P6 specifies, and the
//// operations that exist on one scale type and deliberately not on another.

import d3_fixtures
import dapper/scale
import dapper/scale/domain
import gleam/float
import gleam/int
import gleam/list
import gleeunit/should

fn categories(n: Int) -> List(String) {
  build_categories(0, n, [])
}

fn build_categories(i: Int, n: Int, acc: List(String)) -> List(String) {
  case i >= n {
    True -> list.reverse(acc)
    False -> build_categories(i + 1, n, ["c" <> int.to_string(i), ..acc])
  }
}

fn close(a: Float, b: Float) -> Bool {
  float.absolute_value(a -. b) <. 1.0e-9
}

// --- band and point, against d3 -------------------------------------------

pub fn band_layout_matches_d3_test() {
  use case_ <- list.each(d3_fixtures.band_cases())
  let s =
    scale.band(categories(case_.n), #(case_.lo, case_.hi))
    |> scale.padding_inner(case_.padding_inner)
    |> scale.padding_outer(case_.padding_outer)
    |> scale.align(case_.align)

  close(scale.bandwidth(s), case_.bandwidth) |> should.be_true
  close(scale.step(s), case_.step) |> should.be_true
  compare_positions(scale.band_positions(s), case_.positions)
}

/// `list.zip` truncates to the shorter list, so comparing zipped pairs alone
/// would pass vacuously if `band_positions` returned nothing at all. The length
/// check is what makes the comparison mean something.
fn compare_positions(actual: List(Float), expected: List(Float)) -> Nil {
  list.length(actual) |> should.equal(list.length(expected))
  list.zip(actual, expected)
  |> list.each(fn(pair) { close(pair.0, pair.1) |> should.be_true })
}

pub fn point_layout_matches_d3_test() {
  use case_ <- list.each(d3_fixtures.point_cases())
  let s =
    scale.point(categories(case_.n), #(case_.lo, case_.hi))
    |> scale.padding_outer(case_.padding)
    |> scale.align(case_.align)

  close(scale.step(s), case_.step) |> should.be_true
  compare_positions(scale.band_positions(s), case_.positions)
}

pub fn point_scales_have_no_bandwidth_test() {
  // Not an analogy: a point scale *is* a band scale with paddingInner pinned to
  // 1, so its bands have collapsed. One layout algorithm, not two that must be
  // kept in agreement.
  scale.point(categories(4), #(0.0, 90.0))
  |> scale.bandwidth
  |> should.equal(0.0)
}

// --- continuous -----------------------------------------------------------

pub fn linear_converts_and_inverts_test() {
  let s = scale.linear(#(0.0, 10.0), #(0.0, 100.0))
  scale.convert(s, 0.0) |> should.equal(0.0)
  scale.convert(s, 5.0) |> should.equal(50.0)
  scale.convert(s, 10.0) |> should.equal(100.0)
  scale.invert(s, 50.0) |> should.equal(5.0)
}

pub fn linear_extrapolates_unless_clamped_test() {
  let s = scale.linear(#(0.0, 10.0), #(0.0, 100.0))
  scale.convert(s, 20.0) |> should.equal(200.0)
  scale.convert(scale.clamp(s, True), 20.0) |> should.equal(100.0)
  scale.convert(scale.clamp(s, True), -5.0) |> should.equal(0.0)
}

pub fn linear_handles_a_reversed_range_test() {
  // The y axis is always reversed: data increases upward, pixels increase
  // downward.
  let s = scale.linear(#(0.0, 10.0), #(100.0, 0.0))
  scale.convert(s, 0.0) |> should.equal(100.0)
  scale.convert(s, 10.0) |> should.equal(0.0)
}

pub fn zero_width_domain_does_not_divide_by_zero_test() {
  let s = scale.linear(#(5.0, 5.0), #(0.0, 100.0))
  scale.convert(s, 5.0) |> should.equal(0.0)
}

pub fn log_converts_across_decades_test() {
  let s = scale.log(#(1.0, 100.0), #(0.0, 100.0), 10.0)
  close(scale.convert(s, 1.0), 0.0) |> should.be_true
  close(scale.convert(s, 10.0), 50.0) |> should.be_true
  close(scale.convert(s, 100.0), 100.0) |> should.be_true
}

pub fn log_clamps_non_positive_input_rather_than_failing_test() {
  // render is total, so a value a log scale cannot represent still has to
  // produce a position. The condition is validate's to report, not convert's
  // to crash on.
  let s = scale.log(#(1.0, 100.0), #(0.0, 100.0), 10.0)
  let at_zero = scale.convert(s, 0.0)
  { at_zero <=. 0.0 } |> should.be_true
}

pub fn log_ticks_are_powers_of_the_base_test() {
  scale.log(#(1.0, 1000.0), #(0.0, 100.0), 10.0)
  |> scale.scale_ticks(5)
  |> should.equal([1.0, 10.0, 100.0, 1000.0])
}

pub fn nice_extends_the_domain_outward_test() {
  scale.linear(#(0.3, 9.1), #(0.0, 100.0))
  |> scale.nice(5)
  |> scale.domain_of
  |> should.equal(#(0.0, 10.0))
}

// --- ordinal --------------------------------------------------------------

pub fn ordinal_maps_categories_to_values_test() {
  let s = scale.ordinal(["a", "b", "c"], ["red", "green", "blue"])
  scale.ordinal_convert(s, "a") |> should.equal(Ok("red"))
  scale.ordinal_convert(s, "c") |> should.equal(Ok("blue"))
  scale.ordinal_convert(s, "z") |> should.equal(Error(Nil))
}

pub fn ordinal_cycles_when_values_run_out_test() {
  let s = scale.ordinal(["a", "b", "c"], ["red", "green"])
  scale.ordinal_convert(s, "c") |> should.equal(Ok("red"))
}

pub fn ordinal_with_no_values_is_an_error_not_a_default_test() {
  scale.ordinal(["a"], [])
  |> scale.ordinal_convert("a")
  |> should.equal(Error(Nil))
}

pub fn unknown_category_is_an_error_not_position_zero_test() {
  // Drawing an unknown category at zero is how a mislabelled bar ends up
  // looking like a real one.
  scale.band(["a", "b"], #(0.0, 100.0))
  |> scale.band_convert("q")
  |> should.equal(Error(Nil))
}

// --- domain ---------------------------------------------------------------

pub fn domain_union_is_a_monoid_test() {
  let a = domain.Numeric(1.0, 5.0)
  domain.union(domain.Empty, a) |> should.equal(a)
  domain.union(a, domain.Empty) |> should.equal(a)
  domain.union(a, domain.Numeric(3.0, 9.0))
  |> should.equal(domain.Numeric(1.0, 9.0))
}

pub fn training_is_a_fold_over_layers_test() {
  [domain.Numeric(2.0, 4.0), domain.Empty, domain.Numeric(-1.0, 3.0)]
  |> domain.train
  |> should.equal(domain.Numeric(-1.0, 4.0))
}

pub fn categories_keep_first_appearance_order_test() {
  // Order decides which bar is leftmost and which series gets which colour.
  // Sorting would silently reorder every chart whose categories are not
  // alphabetical, which is most of them.
  domain.of_labels(["pear", "apple", "pear", "fig"])
  |> should.equal(domain.Categorical(["pear", "apple", "fig"]))
}

pub fn categorical_union_appends_only_unseen_test() {
  domain.union(domain.Categorical(["a", "b"]), domain.Categorical(["b", "c"]))
  |> should.equal(domain.Categorical(["a", "b", "c"]))
}

pub fn empty_domain_still_yields_drawable_bounds_test() {
  // P6: a chart with no data draws axes rather than nothing.
  domain.bounds(domain.Empty) |> should.equal(#(0.0, 1.0))
}

pub fn a_single_datum_is_padded_by_half_a_unit_test() {
  // P6, and it is also what stops convert dividing by zero.
  domain.bounds(domain.Numeric(5.0, 5.0)) |> should.equal(#(4.5, 5.5))
  domain.bounds(domain.of_numbers([5.0])) |> should.equal(#(4.5, 5.5))
}

pub fn of_numbers_takes_the_extent_test() {
  domain.of_numbers([3.0, -1.0, 7.0, 2.0])
  |> should.equal(domain.Numeric(-1.0, 7.0))
}
