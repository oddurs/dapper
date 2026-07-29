//// The extent of the data on one encoding role, before it meets a range.
////
//// `Domain` is a **monoid**: `Empty` is the identity and `union` is total and
//// associative, so training a domain across every layer of a chart is a fold
//// rather than a special case for the first layer (decision S4). Charts with
//// one layer and charts with five take the same code path, which is the only
//// reason the five-layer case is ever correct.
////
//// It is transparent (decision C6). Callers pattern-match on it — `validate`
//// has to see which variant it got in order to say anything useful about it.

import gleam/list

/// The trained extent of one role's values.
///
/// `Empty` is not an error. A layer with no rows contributes nothing to the
/// union, which is exactly what the identity of a monoid means.
pub type Domain {
  Empty
  Numeric(lo: Float, hi: Float)
  Categorical(values: List(String))
}

/// Combine two domains.
///
/// Mixing numeric and categorical data on one role keeps the categorical side.
/// That combination is a modelling error rather than an arithmetic one — the
/// caller has put labels and measurements on the same axis — and discarding
/// the numbers gives `validate` an intact category list to complain about,
/// where merging into some hybrid would leave nothing legible to report.
pub fn union(a: Domain, b: Domain) -> Domain {
  case a, b {
    Empty, other -> other
    other, Empty -> other

    Numeric(a_lo, a_hi), Numeric(b_lo, b_hi) ->
      Numeric(min(a_lo, b_lo), max(a_hi, b_hi))

    Categorical(a_values), Categorical(b_values) ->
      Categorical(append_unseen(a_values, b_values))

    Categorical(values), Numeric(_, _) -> Categorical(values)
    Numeric(_, _), Categorical(values) -> Categorical(values)
  }
}

/// Fold a list of domains into one. The training step, in full.
pub fn train(domains: List(Domain)) -> Domain {
  list.fold(domains, Empty, union)
}

/// The numeric extent of a column of values.
pub fn of_numbers(values: List(Float)) -> Domain {
  list.fold(values, Empty, fn(acc, v) { union(acc, Numeric(v, v)) })
}

/// The category list of a column of labels, in **first-appearance order**.
///
/// Order is an invariant, not an implementation detail: it decides which bar is
/// leftmost and which series gets which colour. Sorting would silently reorder
/// every bar chart whose categories are not alphabetical, which is most of them.
pub fn of_labels(values: List(String)) -> Domain {
  case values {
    [] -> Empty
    _ -> Categorical(append_unseen([], values))
  }
}

/// The numeric bounds a scale should use, with degenerate extents resolved.
///
/// Every case here is specified rather than merely non-crashing (decision P6),
/// because a chart of one datum is a real thing a user will draw and "it does
/// not crash" is not an answer to where the bar goes.
///
/// - `Empty` — no data at all — becomes `0.0` to `1.0`, so axes still draw.
/// - A single value, or any zero-width extent, is padded by half a unit in each
///   direction. Zero width would divide by zero when the scale converts.
///
/// Categorical domains have no numeric bounds; they get the same fallback, and
/// a caller holding one should be using a `BandScale` instead.
pub fn bounds(domain: Domain) -> #(Float, Float) {
  case domain {
    Numeric(lo, hi) if lo <. hi -> #(lo, hi)
    Numeric(v, _) -> #(v -. 0.5, v +. 0.5)
    Empty -> #(0.0, 1.0)
    Categorical(_) -> #(0.0, 1.0)
  }
}

/// The categories of a domain, empty for anything else.
pub fn categories(domain: Domain) -> List(String) {
  case domain {
    Categorical(values) -> values
    _ -> []
  }
}

// --- internals ------------------------------------------------------------

/// Append the values of `new` not already in `seen`, preserving order.
///
/// Quadratic, and deliberately so: a `Dict` would be faster and would make the
/// output order depend on dictionary iteration, which differs between Erlang
/// and JavaScript (decision P5). Category counts are small — a chart with a
/// thousand distinct categories has already failed as a chart.
fn append_unseen(seen: List(String), new: List(String)) -> List(String) {
  list.fold(new, seen, fn(acc, value) {
    case list.contains(acc, value) {
      True -> acc
      False -> list.append(acc, [value])
    }
  })
}

fn min(a: Float, b: Float) -> Float {
  case a <=. b {
    True -> a
    False -> b
  }
}

fn max(a: Float, b: Float) -> Float {
  case a >=. b {
    True -> a
    False -> b
  }
}
