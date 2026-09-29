require "test_helper"
require "template"

# Guards the contract between templates/full.liquid and templates/shared.liquid.
# Rendering itself is covered by template_test.rb, which uses TRMNL's own engine.
class SharedTemplatesTest < Minitest::Test
  SHARED = File.read(Template::SHARED_PATH)
  LAYOUT = File.read(Template::PATH)
  DEFINED = SHARED.scan(/\{%\s*template\s+([\w\/]+)\s*%\}/).flatten
  RENDERED = LAYOUT.scan(/\{%\s*render\s+"([\w\/]+)"/).flatten.uniq

  def test_defines_every_template_the_layout_renders
    assert_empty RENDERED - DEFINED
  end

  def test_the_layout_uses_every_template_that_is_defined
    assert_empty DEFINED - RENDERED
  end

  def test_names_are_unique
    assert_equal DEFINED.uniq, DEFINED
  end

  # TRMNL's template tag stops only at exactly "{% endtemplate %}", so a
  # whitespace-control dash on either tag makes it swallow the templates that
  # follow, and they come up as "Template not found".
  def test_template_tags_use_the_exact_syntax_trmnl_parses
    dashed = SHARED.scan(/\{%-?\s*(?:end)?template\b[^%]*%\}/).grep(/\{%-|-%\}/)

    assert_empty dashed
  end

  def test_every_template_is_closed_with_the_exact_end_tag
    assert_equal DEFINED.size, SHARED.scan("{% endtemplate %}").size
  end

  # TRMNL's docs don't say whether one shared template may call another, so
  # the layout is the only caller. This keeps us off that unknown.
  def test_no_shared_template_renders_another
    bodies = SHARED.scan(/\{% template .*?\{% endtemplate %\}/m)

    assert_empty bodies.grep(/\{%-?\s*render\b/)
  end
end
