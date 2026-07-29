//// Conformance table for `dapper/format`.
////
//// Every case here runs on both the Erlang and JavaScript targets. That is the
//// entire point: the module exists because `float.to_string` disagrees between
//// them, so a test suite that only ran on one target would prove nothing.

import dapper/format
import gleeunit/should

// --- coord ----------------------------------------------------------------

pub fn coord_rounds_to_two_places_test() {
  format.coord(12.345) |> should.equal("12.35")
  format.coord(12.344) |> should.equal("12.34")
  format.coord(0.5) |> should.equal("0.5")
  format.coord(100.0) |> should.equal("100")
}

pub fn coord_never_emits_negative_zero_test() {
  // -0.004 rounds to zero. Emitting "-0" would be valid SVG and would also
  // make two mathematically identical scenes produce different bytes.
  format.coord(-0.004) |> should.equal("0")
  format.coord(-0.0) |> should.equal("0")
}

pub fn coord_clamps_rather_than_using_exponent_notation_test() {
  // Exponent notation is legal in SVG but parsed inconsistently. Coordinates
  // saturate instead.
  format.coord(1.0e12) |> should.equal("1000000000")
  format.coord(-1.0e12) |> should.equal("-1000000000")
}

// There is deliberately no test that a non-finite value renders as "0". One
// cannot be constructed in pure Gleam: an out-of-range literal is a compile
// error, `/.` by zero is defined to return `0.0`, and Erlang raises on overflow
// rather than saturating. The guard in `is_finite` exists for values arriving
// through FFI, which core has none of, so it is unreachable from here.
//
// What *is* testable is that a finite value near the ceiling is not
// misclassified as non-finite — which an earlier bound of `1.0e308` got wrong.
pub fn largest_finite_float_is_treated_as_finite_test() {
  format.exponent10(1.797_693_134_862_315_7e308) |> should.equal(24)
}

// --- fixed ----------------------------------------------------------------

pub fn fixed_rounds_half_away_from_zero_on_both_signs_test() {
  // The case the whole module is built around. `erlang:round` rounds halves
  // away from zero and `Math.round` rounds them toward positive infinity, so
  // a naive implementation returns "-1" on Erlang and "-2" on JavaScript here.
  format.fixed(1.5, 0) |> should.equal("2")
  format.fixed(-1.5, 0) |> should.equal("-2")
  format.fixed(2.5, 0) |> should.equal("3")
  format.fixed(-2.5, 0) |> should.equal("-3")
  format.fixed(0.5, 0) |> should.equal("1")
  format.fixed(-0.5, 0) |> should.equal("-1")
}

pub fn fixed_pads_and_places_the_point_test() {
  format.fixed(0.125, 2) |> should.equal("0.13")
  format.fixed(0.005, 2) |> should.equal("0.01")
  format.fixed(1.0, 3) |> should.equal("1.000")
  format.fixed(0.0, 2) |> should.equal("0.00")
}

pub fn fixed_clamps_the_decimal_count_test() {
  // Total rather than partial: out-of-range precision saturates.
  format.fixed(1.23456789, 20) |> should.equal("1.234568")
  format.fixed(1.5, -3) |> should.equal("2")
}

pub fn fixed_saturates_beyond_exact_integer_range_test() {
  // Past 2^53 an Int is no longer exact on JavaScript, so the magnitude is
  // clamped. Deterministic, just saturated.
  format.fixed(1.0e300, 0) |> should.equal("9007199254740992")
}

// --- exponent10 -----------------------------------------------------------

pub fn exponent10_finds_the_decimal_exponent_test() {
  format.exponent10(1.0) |> should.equal(0)
  format.exponent10(9.999) |> should.equal(0)
  format.exponent10(10.0) |> should.equal(1)
  format.exponent10(999.0) |> should.equal(2)
  format.exponent10(1000.0) |> should.equal(3)
  format.exponent10(0.1) |> should.equal(-1)
  format.exponent10(0.05) |> should.equal(-2)
  format.exponent10(0.001) |> should.equal(-3)
}

pub fn exponent10_is_sign_independent_test() {
  format.exponent10(-1234.0) |> should.equal(3)
}

pub fn exponent10_is_total_test() {
  format.exponent10(0.0) |> should.equal(0)
}

pub fn exponent10_is_exact_at_the_powers_of_ten_test() {
  // The boundary values are where a `log10`-based implementation drifts: one
  // ulp of error flips the floor and changes a tick step. Comparison against
  // literals cannot.
  format.exponent10(100.0) |> should.equal(2)
  format.exponent10(1.0e9) |> should.equal(9)
  format.exponent10(1.0e-9) |> should.equal(-9)
}

// --- si -------------------------------------------------------------------

pub fn si_uses_suffixes_and_trims_test() {
  format.si(4_200_000_000.0, 1) |> should.equal("4.2G")
  format.si(1500.0, 1) |> should.equal("1.5k")
  format.si(1_000_000.0, 1) |> should.equal("1M")
  format.si(42.0, 1) |> should.equal("42")
}

pub fn si_handles_small_magnitudes_test() {
  format.si(0.0025, 1) |> should.equal("2.5m")
  format.si(0.0000042, 1) |> should.equal("4.2µ")
}

pub fn si_is_sign_correct_test() {
  format.si(-1500.0, 1) |> should.equal("-1.5k")
}

// --- scientific -----------------------------------------------------------

pub fn scientific_assembles_the_exponent_from_digits_test() {
  format.scientific(1234.0, 3) |> should.equal("1.23e3")
  format.scientific(-0.05, 2) |> should.equal("-5.0e-2")
  format.scientific(1.0, 1) |> should.equal("1e0")
}

pub fn scientific_renders_zero_plainly_test() {
  format.scientific(0.0, 3) |> should.equal("0")
}

// --- tick_format ----------------------------------------------------------

pub fn tick_format_takes_precision_from_the_step_test() {
  // Precision is a property of the axis, not of the individual label, so an
  // axis stepping by 0.1 shows one decimal on every tick including the round
  // ones.
  format.tick_format(0.2, 0.1) |> should.equal("0.2")
  format.tick_format(3.0, 1.0) |> should.equal("3")
  format.tick_format(0.25, 0.05) |> should.equal("0.25")
}

pub fn tick_format_switches_to_si_at_ten_thousand_test() {
  // Label width feeds directly into reserved axis space, so a revenue axis
  // must not render "4200000000". Below 10_000 the plain form is no wider and
  // reads better, so the switch is deliberately not earlier.
  format.tick_format(1500.0, 500.0) |> should.equal("1500")
  format.tick_format(15_000.0, 5000.0) |> should.equal("15k")
  format.tick_format(4_200_000_000.0, 100_000_000.0) |> should.equal("4.2G")
}
