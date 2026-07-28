# Lustre integration

Scope: the browser half of the primary claim — *the same `Chart` renders as a Lustre component*.
Researched against Lustre **v5.7.1** source (hex tarball), not memory.

## Decisions

**L1 — v0.1 ships both renderers and zero interaction.** The wedge is a *comparative-static* claim:
one `Chart` value, two outputs. Demonstrating it requires `Scene -> Element(msg)` to exist, and it
is ~150 lines of fold with no new concepts. Interaction is a different animal — hit-testing, resize,
tooltip anchoring — and is where API mistakes become breaking changes. So v0.1 ships
`svg.render : Scene -> String` and `dapper_lustre.static : Scene -> Element(msg)`, and the README's
existing non-goal ("interactivity/tooltips") stands. Interaction is v0.2, designed now so the seams
are cut correctly.

**L2 — two packages: `dapper` (no Lustre dependency) and `dapper_lustre`.** Lustre pulls
`gleam_otp`, `gleam_erlang`, `exception`, `gleam_json`, `houdini`. A BEAM report generator that
emits an SVG string into a PDF should not acquire an OTP supervision tree. `Scene` is already the
accepted public seam (prior-art #2), so a second package costs almost nothing — and it insulates
the purity claim from Lustre's cadence (eight minors since 5.0). Lustre goes in `dapper_lustre`'s
dependencies and *nowhere* in core.

**L3 — the SVG string is the reference output; the Lustre tree is tested against it.** The
rendering brief names the failure directly: "two render paths drift — testing one and shipping two."
The fix is a test, not an abstraction (`diagrams`' `Backend` class is the warning; do not build one
until a third target exists). `dapper_lustre` depends on both packages, so its test suite can assert
`element.to_string(dapper_lustre.static(scene)) == dapper.svg.render(scene)` over the birdie corpus,
on both targets. Two facts make exact equality achievable rather than aspirational: every Lustre SVG
attribute value is a `String` (`attribute.attribute(name, value)`), so dapper's own pinned float
formatter is the *only* number-to-string path on either target; and Lustre emits attributes in list
order. Byte equality is the goal; a documented normalisation is the fallback.

**L4 — hydration is DOM-level and it actually works.** This was the load-bearing unknown and the
source settles it. `lustre/runtime/client/runtime.ffi.mjs` constructs the runtime by calling
`virtualise(this.root)` — it builds a vdom *from the existing DOM*, including namespaced elements
via `node.namespaceURI` and keys via `data-lustre-key` — and only then diffs the first `view(model)`
against it. So ECharts' split works literally: the BEAM emits `svg.render(scene)` into `<div
id="chart">`, the client calls `lustre.start(app, "#chart", flags)`, and a matching tree produces an
empty patch. **A mismatch degrades to a re-patch, not a crash** — a far better safety profile than
React hydration, and worth stating in the README. Consequence: emit stable keys as
`data-lustre-key="<facet>:<series>:<index>"` from the string renderer and use
`lustre/element/keyed.namespaced` in the Lustre renderer, so the trees line up. Prior-art #13 pays
for itself immediately rather than "later".

**L5 — the no-serialisable-spec decision surfaces here, and it must be written down.** Hydration
cannot ship the `Chart`; it contains closures. The client must *rebuild* the same `Chart` from data
it decodes itself. The honest pattern is: server sends SVG + the row data as JSON (the user already
owns that decoder), client constructs the identical `Chart`, `build`s it, and hydrates onto a
matching tree. This is the real cost of decision 0001's accepted tradeoff, showing up in the one
place it bites. Say it in the guide, not at v0.3.

**L6 — `Chart(row)` stays free of `msg`; the message parameter enters exactly once, at `view`.**
The react-components brief sketches `Chart(msg)` with `on: List(Interaction(msg))`. Reject it. If
`msg` is in `Chart`, then "the same `Chart` value renders both ways" becomes false — the BEAM value
would carry a phantom the string renderer ignores, and users would reach for `element.map`.
Interaction is supplied at the view boundary instead: `view(scene, handlers, state)`. This also
keeps `Scene` monomorphic, which the snapshot suite needs.

**L7 — hit-testing is by key, not by geometry.** One delegated `pointerover` listener on the root
`<svg>`, decoding `["target", "dataset", "dapperKey"]`. No quadtree, no voronoi, no second copy of
layout in the browser — the browser's own hit-testing is the spatial index, and the key is already
on the node for hydration. This covers `Item` trigger for bars and points. Lines are one `<path>`
per series, so per-point hover needs `Axis` trigger: a transparent overlay `<rect>` over the plot
area, `pointermove`, `offsetX`, invert the x scale, nearest datum. That requires `Scene` to expose
the resolved plot `Frame` and the x `Scale` — a concrete requirement for the scene stream, not an
afterthought. Take ECharts' vocabulary (`Item | Axis`) verbatim.

**L8 — TEA collapses most of the React lineage's architecture.** Recharts v3 rebuilt Redux
(`createRechartsStore`, registration components dispatching in `useEffect`) because hooks cannot
lift chart state out without prop drilling. The user's `update` *is* that store. dapper therefore
ships a plain `State` value and a pure `update(State, Event) -> State` that the user embeds in
their own model — **a reducer, not a runtime**. That distinction is what "ship no store" means; it
does not mean making users hand-roll hover state. Second-order win: because the hover key is in the
*user's* model, the tooltip can be any Lustre element anywhere on the page, including outside the
SVG. dapper ships the positioned anchor, never the tooltip chrome.

**L9 — never measure in the pure path; size arrives as a message.** `layout(chart, metrics, Size)`
is total and takes `Size` as input. On the server that is a declared width. In the browser, Lustre
has no `ResizeObserver` helper (confirmed: zero hits in the source), but `effect.after_paint(fn(dispatch,
root) -> Nil)` hands you the root element, which is exactly enough for a ~20-line FFI in
`dapper_lustre/resize`. So: SSR emits a chart correct at the declared width with `viewBox` +
`preserveAspectRatio` (which scales the type — say so, per the rendering brief); the first resize
message upgrades it to a chart correct at the *actual* width via genuine re-layout. One message. No
render-prop, no zero-height first pass, no `min-h-*` folklore, no `getBoundingClientRect` in a
function that must also run on the BEAM.

**L10 — server components: document compatibility, ship no code.** They are real (WebSocket / SSE /
polling, ~10KB client runtime, `lustre.start_server_component`, `supervised`, `factory`) and a
dapper chart works inside one for free, because it is only an `Element(msg)`. That is a claim no JS
charting library can make. Two caveats to document: every hover becomes a round trip, so `Item`
handlers must be `event.throttle`d and must declare `server_component.include("pointerover",
["target.dataset.dapperKey"])` or the payload arrives empty; and `event.advanced`'s conditional
`prevent_default` does not work there.

**L11 — no custom element in v0.1 or v0.2.** `component.prerender` (declarative shadow DOM) is
genuinely nice, but registering `<dapper-chart>` forces configuration through
`on_attribute_change : fn(String) -> Result(msg, Nil)` — stringly-typed props, i.e. runtime
validation re-added, i.e. the exact thing dapper deletes. Ship a `view` function.

**L12 — the interaction layer is testable on the BEAM.** `lustre/dev/simulate` (`start`, `event`,
`view`, `model`) plus `lustre/dev/query` drive an app headlessly. So even v0.2 keeps the
no-headless-browser property in CI. This is what makes interaction tractable for a solo maintainer.

## Concrete shapes

```gleam
// dapper/key.gleam  (core — required by BOTH renderers)
pub type Key {
  Key(facet: Int, series: String, datum: Int)
}

pub fn to_string(key: Key) -> String        // "0:revenue:12"
pub fn parse(raw: String) -> Result(Key, Nil)
```

```gleam
// dapper/scene.gleam  (core) — what this stream needs from the Scene stream
pub fn frame(scene: Scene) -> Frame                    // resolved plot rect, px
pub fn x_scale(scene: Scene) -> scale.Scale            // for Axis-trigger inversion
pub fn anchor(scene: Scene, key: Key) -> Result(Point, Nil)
pub fn series(scene: Scene) -> List(#(String, SeriesMeta))
```

```gleam
// dapper/svg.gleam  (core)
pub fn render(scene: Scene) -> String
// emits data-lustre-key on every mark, role="img", <title>, level-1 <desc>
```

```gleam
// dapper_lustre.gleam            v0.1
import lustre/element.{type Element}

pub fn static(scene: Scene) -> Element(msg)
```

```gleam
// dapper_lustre.gleam            v0.2
pub type Trigger {
  ItemTrigger
  AxisTrigger
}

pub type Handlers(msg) {
  Handlers(
    trigger: Trigger,
    on_point: fn(Option(Key)) -> msg,
    on_activate: fn(Key) -> msg,
    on_legend_toggle: fn(String) -> msg,
  )
}

pub fn view(
  scene: Scene,
  handlers: Handlers(msg),
  state: state.State,
) -> Element(msg)
```

All four `Handlers` fields are mandatory — no optional arguments, no deep merge, per decision 0001.
Callers who want no interaction call `static` instead. Two total functions; no partial record.

```gleam
// dapper_lustre/state.gleam      v0.2 — a value in the USER's model, not a store
pub opaque type State

pub type Event {
  Pointed(Option(Key))
  Activated(Key)
  LegendToggled(series: String)
  Resized(width: Float, height: Float)
}

pub fn init() -> State
pub fn update(state: State, event: Event) -> State      // pure, total
pub fn hovered(state: State) -> Option(Key)
pub fn hidden(state: State) -> Set(String)
pub fn size(state: State) -> Option(#(Float, Float))
```

```gleam
// dapper_lustre/resize.gleam     v0.2
import lustre/effect.{type Effect}

pub fn observe(on_resize: fn(Float, Float) -> msg) -> Effect(msg)
// effect.after_paint(fn(dispatch, root) { ffi_observe(root, ...) })
```

```gleam
// internal: the whole of hit-testing
fn item_handler(handlers: Handlers(msg)) -> Attribute(msg) {
  event.on("pointerover", {
    use raw <- decode.subfield(["target", "dataset", "dapperKey"], decode.string)
    case key.parse(raw) {
      Ok(k) -> decode.success(handlers.on_point(Some(k)))
      Error(_) -> decode.failure(handlers.on_point(None), "Key")
    }
  })
  |> event.throttle(16)
}
```

## Task breakdown

1. **S — `dapper/key`: `Key`, `to_string`, `parse`, round-trip test.** Unblocks both renderers and
   all of v0.2. Do it before the string renderer emits a single tag.
2. **M — `dapper/svg.render`**, emitting `data-lustre-key`, `role="img"`, `<title>`, L1 `<desc>`.
   The v0.1 deliverable. Unblocks birdie snapshots.
3. **S — scaffold `dapper_lustre`** (repo, `gleam.toml`, CI on both targets, path dep on core).
   Unblocks 4.
4. **M — `dapper_lustre.static`**, a keyed mirror of the string fold using
   `element/keyed.namespaced`. Unblocks 5.
5. **M — the drift test**: `element.to_string(static(scene)) == svg.render(scene)` over the whole
   birdie corpus, both targets. This is the task that makes L3 true rather than intended. Nothing
   after this is safe without it.
6. **S — hydration example app**: mist server renders SVG + row JSON, client rebuilds `Chart` and
   `lustre.start`s onto it. Proves L4/L5 end-to-end and is the README's demo. **v0.1 ends here.**
7. **M — `dapper_lustre/state`** + `Event`/`update`, tested with `lustre/dev/simulate`. Unblocks
   8–10.
8. **M — `Item` trigger** (delegated `pointerover`, throttled, key decoder) and legend toggle.
   Unblocks tooltips.
9. **L — `Axis` trigger**: overlay rect, `offsetX`, scale inversion, nearest-datum search. Needs
   `Frame` + `x_scale` on `Scene`; the browser-behaviour risk lives here.
10. **S — `dapper_lustre/resize`** FFI + `Resized` handling. Unblocks real responsiveness.
11. **S — server-component compatibility guide**, `include` + `throttle` documented, one worked
    example.

## Risks and unknowns

- **`offsetX` on SVG differs across engines** (historically Firefox vs Chromium on nested SVG
  targets). Task 9 must be tested in three browsers or fall back to `clientX` minus a cached rect
  supplied by the resize observer — which is measurement, but on the *impure* side of the line.
- **`element.to_string` output is not a stability contract.** Task 5 could start failing on a Lustre
  patch release. Mitigation: normalise before comparing, and pin Lustre with a tight range in
  `dapper_lustre` only.
- **`dataset` camel-casing.** `data-dapper-key` decodes as `dataset.dapperKey`; get it wrong and the
  decoder silently fails and every hover is a no-op. Test it in `simulate`.
- **Two packages, one release.** Version skew between `dapper` and `dapper_lustre` is a real solo-
  maintainer tax. Lockstep versioning, released together, no exceptions.
- **Hydration mismatch is invisible.** A silently-repatching chart looks correct. Ship a dev-only
  assertion or a documented "check for a non-empty first patch" recipe.

## What is explicitly NOT in v0.1

Interaction of any kind; `State`/`update`; tooltips (chrome or anchor); legend toggling; the resize
observer; a registered custom element; anything server-component-specific; keyed animation;
brush/zoom/pan; canvas fallback; `element.memo`-based render skipping.

## Open questions needing a human call

1. **One package or two?** L2 says two. The counter-case — Gleam has no optional dependencies, so
   one package with a `dapper/lustre` module is simpler to release and impossible to skew — is
   respectable, and hinges on whether a BEAM-only user acquiring `gleam_otp` actually bothers you.
2. **Does the drift test target byte equality or normalised equality?** Byte equality is a much
   stronger guarantee and a much more brittle test. Decide before task 4 fixes attribute order.
3. **Is `Axis` trigger v0.2 or v0.3?** It is the largest single item here and the one users will ask
   for first (it is what makes line charts feel finished).
4. **Should `dapper_lustre.view` be allowed to re-`build` on resize, or does the user own that?**
   Re-building means `view` needs the `Chart`, not the `Scene` — a different signature and a
   different story about where `Size` lives.
