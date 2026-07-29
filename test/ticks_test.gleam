//// `dapper/ticks` asserted case by case against d3-array 3.2.4.
////
//// A port is only a port if it is checked against the original, so these tests
//// walk the generated fixtures rather than restating the algorithm's intent.
//// They run on both targets, which is what makes them worth having: the
//// substitutions for `Math.log10` and `Math.pow` exist precisely so that a
//// one-ulp difference cannot change a tick, and only running both proves it.

import d3_fixtures
import dapper/ticks
import gleam/list
import gleeunit/should

pub fn ticks_match_d3_test() {
  use case_ <- list.each(d3_fixtures.ticks_cases())
  ticks.ticks(case_.start, case_.stop, case_.count)
  |> should.equal(case_.ticks)
}

pub fn tick_increment_matches_d3_test() {
  use case_ <- list.each(d3_fixtures.increment_cases())
  ticks.tick_increment(case_.start, case_.stop, case_.count)
  |> should.equal(Ok(case_.increment))
}

pub fn nice_matches_d3_test() {
  use case_ <- list.each(d3_fixtures.nice_cases())
  ticks.nice(case_.start, case_.stop, case_.count)
  |> should.equal(#(case_.lo, case_.hi))
}

// --- the cases d3 cannot express ------------------------------------------

pub fn tick_increment_rejects_what_d3_returns_nan_for_test() {
  // These four are exactly the cases the fixture generator had to drop: d3
  // reaches `Math.log10` of zero or of a negative step and propagates NaN.
  // Gleam has no NaN and `render` must be total, so the impossible value
  // becomes an explicit absence.
  ticks.tick_increment(1.0, 1.0, 5) |> should.equal(Error(Nil))
  ticks.tick_increment(0.0, 0.0, 5) |> should.equal(Error(Nil))
  ticks.tick_increment(10.0, 0.0, 5) |> should.equal(Error(Nil))
  ticks.tick_increment(1.0, -1.0, 5) |> should.equal(Error(Nil))
}

pub fn ticks_is_total_where_tick_increment_is_not_test() {
  // `ticks` still answers for the degenerate cases, because it handles them
  // before consulting the spec.
  ticks.ticks(1.0, 1.0, 5) |> should.equal([1.0])
  ticks.ticks(0.0, 1.0, 0) |> should.equal([])
  ticks.ticks(0.0, 1.0, -3) |> should.equal([])
}

pub fn nice_is_total_on_degenerate_input_test() {
  ticks.nice(1.0, 1.0, 5) |> should.equal(#(1.0, 1.0))
  ticks.nice(0.0, 1.0, 0) |> should.equal(#(0.0, 1.0))
}

// --- tick_step ------------------------------------------------------------

pub fn tick_step_returns_a_real_step_not_a_reciprocal_test() {
  // `tick_increment` returns a negative reciprocal for sub-unit steps, which is
  // an implementation detail of the 1-2-5 search. `tick_step` is what a caller
  // formats against.
  ticks.tick_step(0.0, 1.0, 10) |> should.equal(Ok(0.1))
  ticks.tick_step(0.0, 100.0, 5) |> should.equal(Ok(20.0))
}

pub fn tick_step_is_negative_on_a_reversed_range_test() {
  ticks.tick_step(100.0, 0.0, 5) |> should.equal(Ok(-20.0))
}
