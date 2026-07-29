import dapper/geom
import gleeunit/should

pub fn rect_normalises_endpoint_order_test() {
  // The reason Rect stores endpoints at all: a negative SVG width does not
  // error, it silently drops the element.
  geom.rect(10.0, 0.0, 0.0, 5.0)
  |> should.equal(geom.Rect(0.0, 0.0, 10.0, 5.0))

  geom.rect(0.0, 5.0, 10.0, 0.0)
  |> should.equal(geom.Rect(0.0, 0.0, 10.0, 5.0))
}

pub fn width_and_height_are_non_negative_test() {
  let r = geom.rect(10.0, 8.0, 2.0, 1.0)
  geom.width(r) |> should.equal(8.0)
  geom.height(r) |> should.equal(7.0)
}

pub fn from_size_anchors_at_the_origin_test() {
  geom.from_size(geom.Size(640.0, 480.0))
  |> should.equal(geom.Rect(0.0, 0.0, 640.0, 480.0))
}

pub fn inset_shrinks_each_edge_test() {
  geom.from_size(geom.Size(100.0, 100.0))
  |> geom.inset(geom.Insets(10.0, 20.0, 30.0, 40.0))
  |> should.equal(geom.Rect(40.0, 10.0, 80.0, 70.0))
}

pub fn inset_collapses_rather_than_inverting_test() {
  // Reserved axis space can exceed the canvas on a small chart. A collapsed
  // plot area is a diagnostic; an inside-out rectangle is a silently corrupt
  // chart, so this clamps.
  let collapsed =
    geom.from_size(geom.Size(50.0, 50.0))
    |> geom.inset(geom.uniform_insets(40.0))

  geom.width(collapsed) |> should.equal(0.0)
  geom.height(collapsed) |> should.equal(0.0)
  geom.is_empty(collapsed) |> should.be_true
}

pub fn is_empty_detects_zero_extent_in_either_axis_test() {
  geom.rect(0.0, 0.0, 10.0, 10.0) |> geom.is_empty |> should.be_false
  geom.rect(0.0, 0.0, 0.0, 10.0) |> geom.is_empty |> should.be_true
  geom.rect(0.0, 0.0, 10.0, 0.0) |> geom.is_empty |> should.be_true
}

pub fn add_insets_accumulates_edge_wise_test() {
  // Axis titles, tick labels and legends each reserve independently and know
  // only their own edge.
  geom.add_insets(
    geom.Insets(1.0, 2.0, 3.0, 4.0),
    geom.Insets(10.0, 20.0, 30.0, 40.0),
  )
  |> should.equal(geom.Insets(11.0, 22.0, 33.0, 44.0))
}

pub fn no_insets_is_the_identity_for_add_test() {
  let some = geom.Insets(1.0, 2.0, 3.0, 4.0)
  geom.add_insets(some, geom.no_insets()) |> should.equal(some)
  geom.add_insets(geom.no_insets(), some) |> should.equal(some)
}

pub fn max_insets_takes_the_edge_wise_maximum_test() {
  // MarginPolicy.AtLeast is a floor under measured axis space, not an addition
  // to it.
  geom.max_insets(
    geom.Insets(10.0, 2.0, 30.0, 4.0),
    geom.Insets(1.0, 20.0, 3.0, 40.0),
  )
  |> should.equal(geom.Insets(10.0, 20.0, 30.0, 40.0))
}
