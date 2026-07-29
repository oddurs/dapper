//// The one place a `Float` becomes a `String`.
////
//// `float.to_string` and `string.inspect` are banned in `src/` (decision S9)
//// because both diverge between the Erlang and JavaScript targets. Every float
//// that reaches output goes through this module instead, so that a chart
//// rendered on the BEAM and the same chart rendered in the browser produce the
//// same bytes.
////
//// Three rules make that true:
////
//// - **Rounding happens on a magnitude, never on a signed value.**
////   `erlang:round` rounds halves away from zero; `Math.round` rounds them
////   toward positive infinity. They disagree on `-0.5` and agree on every
////   non-negative value, so the sign is stripped first and reapplied last.
////   Rounding itself is `truncate(a +. 0.5)`, which uses only IEEE-754
////   addition and truncation — both bit-identical across targets.
////
//// - **No transcendental function is used to find a decimal exponent.**
////   `log10` may differ in the last ulp between targets, and one ulp flips a
////   floor, which changes a tick step. Exponents come from comparison against
////   exact literal powers of ten instead (decision S6). This is stronger than
////   S6 requires: rather than truncating `log10` and correcting the
////   off-by-one, there is no `log10` to correct.
////
//// - **Integer arithmetic stays below 2^53.** Gleam's `Int` is a bignum on
////   Erlang and a double on JavaScript, so the two agree only up to 2^53.
////   Every path that scales a float into an integer clamps first.
////
//// Exactness is guaranteed for `|x| * 10^decimals < 2^53`. Outside that the
//// magnitude is clamped and the result is still deterministic, just saturated.

import gleam/float
import gleam/int
import gleam/string

/// 2^53. Above this an `Int` is no longer exact on the JavaScript target.
const max_exact = 9_007_199_254_740_992.0

/// Coordinates are clamped to this magnitude. A chart coordinate outside it is
/// meaningless, and the bound keeps `coord` far away from the 2^53 ceiling.
const coord_limit = 1_000_000_000.0

const coord_limit_low = -1_000_000_000.0

// --- geometry -------------------------------------------------------------

/// Format a coordinate for SVG output: two decimal places, clamped to
/// ±1e9, never exponent notation, non-finite input rendered as `"0"`.
///
/// Exponent notation is banned here specifically. SVG path data and coordinate
/// attributes accept it, but renderers vary in how they parse it, and a
/// coordinate is never the place where the extra range is worth the risk.
///
/// ```gleam
/// coord(12.345)   // "12.35"
/// coord(-0.001)   // "0" — rounds to zero, and negative zero is normalised
/// coord(1.0e12)   // "1000000000" — clamped
/// ```
pub fn coord(x: Float) -> String {
  x |> clamp(coord_limit_low, coord_limit) |> fixed(2) |> trim_trailing_zeros
}

// --- fixed-point ----------------------------------------------------------

/// Format with a fixed number of decimal places, `0` to `6`.
///
/// Decimals outside that range are clamped rather than rejected, so this
/// function is total.
///
/// ```gleam
/// fixed(1.5, 0)     // "2"
/// fixed(-1.5, 0)    // "-2"  — magnitude rounds, then the sign is reapplied
/// fixed(0.125, 2)   // "0.13"
/// fixed(-0.004, 2)  // "0"   — never "-0"
/// ```
pub fn fixed(x: Float, decimals: Int) -> String {
  let d = clamp_int(decimals, 0, 6)
  case is_finite(x) {
    False -> zero(d)
    True -> {
      let negative = x <. 0.0
      let scale = pow10(d)
      // Clamp the magnitude so the scaled value cannot leave exact Int range.
      let magnitude = float.min(float.absolute_value(x), max_exact /. scale)
      let n = float.truncate(magnitude *. scale +. 0.5)
      let digits = pad_left(int.to_string(n), d + 1)
      let body = insert_point(digits, d)
      case negative && n != 0 {
        True -> "-" <> body
        False -> body
      }
    }
  }
}

// --- decimal exponent -----------------------------------------------------

/// The decimal exponent of `x`: the largest `e` with `10^e <= |x|`.
///
/// Returns `0` for zero and for non-finite input, so callers do not have to
/// unwrap a `Result` on a value they have usually already validated.
///
/// Computed by comparison against exact literal powers of ten, never by
/// `log10` — see the module documentation. Saturates at ±24.
///
/// ```gleam
/// exponent10(0.0)     // 0
/// exponent10(999.0)   // 2
/// exponent10(1000.0)  // 3
/// exponent10(0.05)    // -2
/// ```
pub fn exponent10(x: Float) -> Int {
  let a = float.absolute_value(x)
  case is_finite(x) && a >. 0.0 {
    False -> 0
    True ->
      case a >=. 1.0 {
        True -> climb(a, 0)
        False -> descend(a, 0)
      }
  }
}

fn climb(a: Float, e: Int) -> Int {
  case e >= 24 || a <. pow10_wide(e + 1) {
    True -> e
    False -> climb(a, e + 1)
  }
}

fn descend(a: Float, e: Int) -> Int {
  case e <= -24 || a >=. pow10_wide(e - 1) {
    True -> e - 1
    False -> descend(a, e - 1)
  }
}

/// Ten raised to an integer power, from a table of exact literals.
///
/// Public because `dapper/ticks` needs the same guarantee `exponent10` gives:
/// two targets must not disagree about a power of ten. `float.power` would work
/// and is the obvious choice, which is exactly why this exists — a transcendental
/// implementation is free to differ in the last ulp, and one ulp here changes a
/// tick step.
///
/// Falls back to repeated multiplication outside the table, which is still
/// deterministic because it is plain IEEE multiplication in a fixed order.
pub fn power_of_ten(e: Int) -> Float {
  pow10_wide(e)
}

/// `Math.round` semantics: round half toward positive infinity.
///
/// Deliberately *not* the rounding used by `fixed`, which rounds magnitudes so
/// that the two targets agree. This one agrees with **JavaScript**, which is
/// what `dapper/ticks` needs: d3 is a JavaScript library, the tick fixtures were
/// generated by running it, and a port that rounds differently from the original
/// is not a port. `erlang:round` would round `-1.5` to `-2` where d3 gets `-1`.
///
/// `floor(x + 0.5)` is exactly `Math.round` for every finite input, using only
/// IEEE addition and floor.
pub fn round_toward_positive(x: Float) -> Int {
  float.truncate(float.floor(x +. 0.5))
}

// --- SI and scientific ----------------------------------------------------

/// Format with an SI suffix, trimming trailing zeros.
///
/// This is what makes a revenue axis read `4.2G` rather than
/// `4200000000`. Values outside the covered range (10^-9 to 10^12) fall back
/// to plain fixed-point.
///
/// ```gleam
/// si(4_200_000_000.0, 1)  // "4.2G"
/// si(1500.0, 1)           // "1.5k"
/// si(0.0025, 1)           // "2.5m"
/// si(42.0, 1)             // "42"
/// ```
pub fn si(x: Float, decimals: Int) -> String {
  case is_finite(x) {
    False -> "0"
    True -> {
      let group = si_group(exponent10(x))
      case suffix(group) {
        Error(Nil) -> trim_trailing_zeros(fixed(x, decimals))
        Ok(unit) ->
          trim_trailing_zeros(fixed(x /. pow10_wide(group), decimals)) <> unit
      }
    }
  }
}

/// Format in scientific notation with `significant` significant digits.
///
/// The exponent is assembled from digits rather than produced by scaling an
/// `Int`, so it is identical on both targets regardless of magnitude.
///
/// ```gleam
/// scientific(1234.0, 3)  // "1.23e3"
/// scientific(-0.05, 2)   // "-5.0e-2"
/// scientific(0.0, 3)     // "0"
/// ```
pub fn scientific(x: Float, significant: Int) -> String {
  case is_finite(x) && x != 0.0 {
    False -> "0"
    True -> {
      let e = exponent10(x)
      let mantissa = x /. pow10_wide(e)
      let places = clamp_int(significant - 1, 0, 6)
      fixed(mantissa, places) <> "e" <> int.to_string(e)
    }
  }
}

// --- tick labels ----------------------------------------------------------

/// Format a tick value at a precision implied by the step between ticks.
///
/// Taking the precision from the step rather than from the value is what stops
/// an axis reading `0`, `0.1`, `0.2` as `0`, `0.1`, `0.2` in one place and
/// `0.00`, `0.10`, `0.20` in another — the precision is a property of the axis,
/// not of the individual label.
///
/// Values of 10_000 or more switch to SI so that axis labels stay narrow, which
/// matters because label width feeds directly into reserved axis space. Below
/// that the plain form is no wider and reads better — `1500` beats `1.5k`.
///
/// ```gleam
/// tick_format(0.2, 0.1)             // "0.2"
/// tick_format(3.0, 1.0)             // "3"
/// tick_format(1500.0, 500.0)        // "1500"
/// tick_format(15_000.0, 5000.0)     // "15k"
/// ```
pub fn tick_format(value: Float, step: Float) -> String {
  let step_exponent = exponent10(step)
  case exponent10(value) >= 4 {
    True -> si(value, int.max(0, si_group(exponent10(value)) - step_exponent))
    False -> trim_trailing_zeros(fixed(value, int.max(0, -step_exponent)))
  }
}

// --- internals ------------------------------------------------------------

/// One bound catches NaN and both infinities, because every IEEE-754 ordering
/// comparison against NaN is false — so `NaN <=. max_float` is already `False`.
/// The bound is `<=.` against the largest finite double rather than `<.`
/// against a round number, so that genuinely finite values just below the
/// ceiling are not misclassified.
///
/// The obvious `x == x` NaN test does not work in Gleam: the compiler proves it
/// always `True` and warns, so it cannot be relied on to survive.
///
/// Note that a non-finite `Float` cannot be *constructed* in pure Gleam —
/// out-of-range literals are a compile error, `/.` by zero is defined to return
/// `0.0`, and Erlang raises on overflow rather than saturating. This guard is
/// therefore for values arriving through FFI or from JavaScript interop, and is
/// deliberately kept rather than removed as unreachable.
fn is_finite(x: Float) -> Bool {
  float.absolute_value(x) <=. 1.797_693_134_862_315_7e308
}

fn clamp(x: Float, low: Float, high: Float) -> Float {
  float.min(float.max(x, low), high)
}

fn clamp_int(x: Int, low: Int, high: Int) -> Int {
  int.min(int.max(x, low), high)
}

fn zero(decimals: Int) -> String {
  case decimals {
    0 -> "0"
    d -> "0." <> string.repeat("0", d)
  }
}

/// Exact literals rather than repeated multiplication, which accumulates error.
fn pow10(d: Int) -> Float {
  case d {
    0 -> 1.0
    1 -> 10.0
    2 -> 100.0
    3 -> 1000.0
    4 -> 10_000.0
    5 -> 100_000.0
    _ -> 1_000_000.0
  }
}

/// The wide table, for exponents rather than decimal places. Every value is a
/// literal so that no two targets can disagree about it.
fn pow10_wide(e: Int) -> Float {
  case e {
    24 -> 1.0e24
    21 -> 1.0e21
    18 -> 1.0e18
    15 -> 1.0e15
    12 -> 1.0e12
    11 -> 1.0e11
    10 -> 1.0e10
    9 -> 1.0e9
    8 -> 1.0e8
    7 -> 1.0e7
    6 -> 1.0e6
    5 -> 1.0e5
    4 -> 1.0e4
    3 -> 1.0e3
    2 -> 1.0e2
    1 -> 1.0e1
    0 -> 1.0
    -1 -> 1.0e-1
    -2 -> 1.0e-2
    -3 -> 1.0e-3
    -4 -> 1.0e-4
    -5 -> 1.0e-5
    -6 -> 1.0e-6
    -7 -> 1.0e-7
    -8 -> 1.0e-8
    -9 -> 1.0e-9
    -12 -> 1.0e-12
    -15 -> 1.0e-15
    -18 -> 1.0e-18
    -21 -> 1.0e-21
    -24 -> 1.0e-24
    _ -> slow_pow10(e)
  }
}

/// Only reached for exponents the literal table omits. Deterministic because
/// it is plain IEEE multiplication in a fixed order.
fn slow_pow10(e: Int) -> Float {
  case e {
    0 -> 1.0
    _ ->
      case e > 0 {
        True -> 10.0 *. slow_pow10(e - 1)
        False -> slow_pow10(e + 1) /. 10.0
      }
  }
}

/// Round an exponent down to the nearest multiple of three, toward negative
/// infinity so that 10^-1 groups with 10^-3 rather than with 10^0.
fn si_group(e: Int) -> Int {
  case e >= 0 {
    True -> e / 3 * 3
    False -> { e - 2 } / 3 * 3
  }
}

fn suffix(group: Int) -> Result(String, Nil) {
  case group {
    12 -> Ok("T")
    9 -> Ok("G")
    6 -> Ok("M")
    3 -> Ok("k")
    0 -> Ok("")
    -3 -> Ok("m")
    -6 -> Ok("µ")
    -9 -> Ok("n")
    _ -> Error(Nil)
  }
}

fn pad_left(s: String, width: Int) -> String {
  case string.length(s) >= width {
    True -> s
    False -> string.repeat("0", width - string.length(s)) <> s
  }
}

fn insert_point(digits: String, decimals: Int) -> String {
  case decimals {
    0 -> digits
    d -> {
      let cut = string.length(digits) - d
      string.slice(digits, 0, cut) <> "." <> string.slice(digits, cut, d)
    }
  }
}

/// `"1.50"` becomes `"1.5"`, `"3.00"` becomes `"3"`. Only touches strings that
/// contain a point, so integers pass through untouched.
fn trim_trailing_zeros(s: String) -> String {
  case string.contains(s, ".") {
    False -> s
    True ->
      case drop_zeros(s) {
        stripped ->
          case string.ends_with(stripped, ".") {
            True -> string.drop_end(stripped, 1)
            False -> stripped
          }
      }
  }
}

fn drop_zeros(s: String) -> String {
  case string.ends_with(s, "0") {
    True -> drop_zeros(string.drop_end(s, 1))
    False -> s
  }
}
