//// Rectangles, sizes and insets.
////
//// These are transparent records, deliberately. `Frame` is transparent
//// (decision C6) and carries rectangles, and `custom` marks receive a `Frame`
//// and need to destructure it — a seam you cannot pattern-match on is not a
//// seam.
////
//// The one non-obvious choice is that a `Rect` stores its **interval
//// endpoints**, `x0 x1 y0 y1`, and never an origin plus a width and height
//// (decision R2). Two reasons:
////
//// - A negative `width` on an SVG `<rect>` is not an error, it silently drops
////   the element. Storing endpoints and deriving a width that is non-negative
////   by construction makes that unrepresentable rather than merely unlikely.
//// - Endpoints are what bar geometry composes over. A stacked or dodged bar is
////   an interval operation; expressing it against an origin and a length means
////   converting back and forth at every step, and each conversion is a place
////   to get a sign wrong.

/// A width and a height, in user-space units.
pub type Size {
  Size(width: Float, height: Float)
}

/// An axis-aligned rectangle, stored as the endpoints of its two intervals.
///
/// Construct with `rect`, which normalises the ordering. The constructor is
/// exposed for pattern matching, so a caller *can* build one directly — doing
/// so with `x1 <. x0` produces a rectangle whose `width` is negative, which is
/// exactly what `rect` exists to prevent.
pub type Rect {
  Rect(x0: Float, y0: Float, x1: Float, y1: Float)
}

/// Space reserved on each edge of a rectangle.
///
/// Axis space is reserved per edge rather than as a single margin because the
/// pane grid reserves on outer edges only (decision L9), and because the left
/// inset depends on tick label width while the bottom inset depends on tick
/// label height — different quantities that happen to share a type.
pub type Insets {
  Insets(top: Float, right: Float, bottom: Float, left: Float)
}

// --- construction ---------------------------------------------------------

/// Build a rectangle, ordering each pair of endpoints so that `width` and
/// `height` are non-negative.
///
/// ```gleam
/// rect(10.0, 0.0, 0.0, 5.0)  // Rect(0.0, 0.0, 10.0, 5.0)
/// ```
pub fn rect(x0: Float, y0: Float, x1: Float, y1: Float) -> Rect {
  let #(lo_x, hi_x) = order(x0, x1)
  let #(lo_y, hi_y) = order(y0, y1)
  Rect(lo_x, lo_y, hi_x, hi_y)
}

/// The rectangle covering a size, anchored at the origin.
pub fn from_size(size: Size) -> Rect {
  Rect(0.0, 0.0, size.width, size.height)
}

/// Insets of zero on every edge. The identity for `add_insets`.
pub fn no_insets() -> Insets {
  Insets(0.0, 0.0, 0.0, 0.0)
}

/// The same inset on all four edges.
pub fn uniform_insets(amount: Float) -> Insets {
  Insets(amount, amount, amount, amount)
}

// --- measurement ----------------------------------------------------------

/// Non-negative for any rectangle built with `rect`.
pub fn width(r: Rect) -> Float {
  r.x1 -. r.x0
}

/// Non-negative for any rectangle built with `rect`.
pub fn height(r: Rect) -> Float {
  r.y1 -. r.y0
}

pub fn size(r: Rect) -> Size {
  Size(width(r), height(r))
}

/// True when the rectangle has no area.
///
/// Layout has to answer this: a plot area can collapse when the reserved axis
/// space exceeds the canvas, and drawing into a collapsed area is not an error
/// so much as a diagnostic.
pub fn is_empty(r: Rect) -> Bool {
  width(r) <=. 0.0 || height(r) <=. 0.0
}

// --- derivation -----------------------------------------------------------

/// Shrink a rectangle by insets on each edge.
///
/// This is how the plot area is derived from the canvas once axis space is
/// known. It clamps rather than inverting: insets larger than the rectangle
/// produce an empty rectangle at the top-left of the remaining space, never one
/// with negative extent. A collapsed plot area is a diagnostic; a rectangle
/// that renders inside-out is a silently corrupt chart.
pub fn inset(r: Rect, by: Insets) -> Rect {
  let x0 = r.x0 +. by.left
  let y0 = r.y0 +. by.top
  Rect(
    x0,
    y0,
    float_max(x0, r.x1 -. by.right),
    float_max(y0, r.y1 -. by.bottom),
  )
}

/// Combine insets edge-wise.
///
/// Layout accumulates reservations from independent sources — axis titles, tick
/// labels, the legend — and each knows only its own edge.
pub fn add_insets(a: Insets, b: Insets) -> Insets {
  Insets(
    a.top +. b.top,
    a.right +. b.right,
    a.bottom +. b.bottom,
    a.left +. b.left,
  )
}

/// Edge-wise maximum.
///
/// This is what `MarginPolicy.AtLeast` needs (decision L10): a floor under
/// measured axis space, not an addition to it.
pub fn max_insets(a: Insets, b: Insets) -> Insets {
  Insets(
    float_max(a.top, b.top),
    float_max(a.right, b.right),
    float_max(a.bottom, b.bottom),
    float_max(a.left, b.left),
  )
}

// --- internals ------------------------------------------------------------

fn order(a: Float, b: Float) -> #(Float, Float) {
  case a <=. b {
    True -> #(a, b)
    False -> #(b, a)
  }
}

fn float_max(a: Float, b: Float) -> Float {
  case a >=. b {
    True -> a
    False -> b
  }
}
