//// Oracle tests pinning Lustre's serialiser behaviour.
////
//// dapper's SVG emitter (M2) must agree with `dapper_lustre`'s fold byte-for-byte
//// under decision R8's one-rule `canonical/1`. That is only achievable if we know
//// exactly what Lustre does, and only stays achievable if we find out when it
//// changes. These tests are the tripwire — they assert nothing about dapper.
////
//// Measured against lustre 5.7.1 on both targets.

import lustre/attribute.{attribute}
import lustre/element

const svg_ns = "http://www.w3.org/2000/svg"

/// Attributes are emitted in alphabetical order, NOT in list order.
///
/// This settles review blocker B4: the `lustre` stream claimed list order, the
/// `ecosystem` stream measured alphabetical. Alphabetical is correct, so dapper's
/// own emitter sorts too and the two agree by construction rather than by test.
pub fn attributes_are_sorted_alphabetically_test() {
  let out =
    element.namespaced(
      svg_ns,
      "rect",
      [
        attribute("width", "10"),
        attribute("fill", "#4e79a7"),
        attribute("x", "1"),
        attribute("height", "20"),
        attribute("y", "2"),
        attribute("stroke", "none"),
      ],
      [],
    )
    |> element.to_string

  assert out
    == "<rect xmlns=\"http://www.w3.org/2000/svg\" fill=\"#4e79a7\" height=\"20\" stroke=\"none\" width=\"10\" x=\"1\" y=\"2\"></rect>"
}

/// Void-style elements are expanded, never self-closed.
///
/// This is the single rewrite `canonical/1` is permitted to perform. It must
/// never grow a second rule.
pub fn empty_elements_are_expanded_not_self_closed_test() {
  let out =
    element.namespaced(svg_ns, "circle", [attribute("r", "3")], [])
    |> element.to_string

  assert out == "<circle xmlns=\"http://www.w3.org/2000/svg\" r=\"3\"></circle>"
}

/// `xmlns` is emitted on the outermost namespaced element only; children in the
/// same namespace inherit it.
///
/// Not predicted by any stream. dapper's emitter must do the same, or every
/// nested mark carries a redundant xmlns and the two renderers disagree on
/// every non-trivial scene.
pub fn xmlns_is_emitted_on_the_root_only_test() {
  let out =
    element.namespaced(svg_ns, "g", [attribute("class", "marks")], [
      element.namespaced(svg_ns, "circle", [attribute("r", "3")], []),
    ])
    |> element.to_string

  assert out
    == "<g xmlns=\"http://www.w3.org/2000/svg\" class=\"marks\"><circle r=\"3\"></circle></g>"
}

/// The escaper handles `&`, `<`, `>` and `"`, in both attribute values and text
/// content. Decision R9 has dapper hand-rolling its own escaper to keep core at
/// `gleam_stdlib` only; this is what it has to match.
pub fn escaping_covers_ampersand_angles_and_quote_test() {
  let out =
    element.namespaced(
      svg_ns,
      "text",
      [attribute("data-label", "a&b<c>\"d\"")],
      [
        element.text("a&b<c>\"d\""),
      ],
    )
    |> element.to_string

  assert out
    == "<text xmlns=\"http://www.w3.org/2000/svg\" data-label=\"a&amp;b&lt;c&gt;&quot;d&quot;\">a&amp;b&lt;c&gt;&quot;d&quot;</text>"
}

/// The apostrophe is escaped as the NUMERIC entity `&#39;`, not as `&apos;`.
///
/// Pinned separately because it is the one an implementer gets wrong. "The five
/// XML entities" is the natural way to describe an escaper, and four of them
/// have obvious named forms — so `&apos;` is the natural fifth choice, and it is
/// wrong. Emitting it would make dapper disagree with Lustre on any label
/// containing an apostrophe, surfacing as a drift-test diff on a real-world
/// category name long after the escaper was written.
pub fn apostrophe_is_escaped_as_a_numeric_entity_test() {
  let out =
    element.namespaced(svg_ns, "text", [attribute("data-label", "it's")], [
      element.text("it's"),
    ])
    |> element.to_string

  assert out
    == "<text xmlns=\"http://www.w3.org/2000/svg\" data-label=\"it&#39;s\">it&#39;s</text>"
}
