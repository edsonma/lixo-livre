require "test_helper"
require "tempfile"

class TrashVisionComparisonTest < ActiveSupport::TestCase
  def photo(name)
    dir = Dir.mktmpdir
    path = File.join(dir, name)
    File.binwrite(path, "\xFF\xD8x".b)
    path
  end

  test "every provider answers every photo and the table lines them up" do
    claude = ->(_image) { { is_trash: true, severity: 70, types: %w[plastic], confidence: 0.9 } }
    gemini = ->(_image) { { is_trash: false, confidence: 0.8 } }
    results = TrashVision::Comparison.new(providers: { "claude" => claude, "gemini" => gemini }).run([photo("a.jpg"), photo("b.png")])

    assert_equal %w[a.jpg b.png], results.keys
    assert_equal 70, results["a.jpg"]["claude"].severity
    assert_nil results["a.jpg"]["gemini"].severity
    table = TrashVision::Comparison.table(results)
    assert_includes table, "70 plastic"
    assert_includes table, "not trash"
    assert_equal 3, table.lines.size
  end

  test "one provider failing does not stop the others, and its cell shows why" do
    broken = ->(_image) { raise TrashVision::InvalidResponse, "no JSON" }
    fine = ->(_image) { { is_trash: true, severity: 30, types: [], confidence: 0.7 } }
    results = TrashVision::Comparison.new(providers: { "broken" => broken, "fine" => fine }).run([photo("a.jpg")])

    assert_includes results["a.jpg"]["broken"].error, "no JSON"
    assert_equal 30, results["a.jpg"]["fine"].severity
    assert_includes TrashVision::Comparison.table(results), "ERROR InvalidResponse: no JSON"
  end

  test "an answer outside 0-100 is shown as an error, not trusted" do
    wild = ->(_image) { { is_trash: true, severity: 900, types: [], confidence: 0.9 } }
    results = TrashVision::Comparison.new(providers: { "wild" => wild }).run([photo("a.jpg")])
    assert results["a.jpg"]["wild"].error
  end

  test "the provider receives the photo bytes and the right content type" do
    seen = nil
    spy = ->(image) { seen = image; { is_trash: false, confidence: 0.5 } }
    TrashVision::Comparison.new(providers: { "spy" => spy }).run([photo("x.webp")])
    assert_equal "image/webp", seen.content_type
    assert_equal "\xFF\xD8x".b, seen.bytes
  end

  test "an unsupported file type is refused with its name" do
    error = assert_raises(ArgumentError) { TrashVision::Comparison.new(providers: {}).run([photo("x.gif")]) }
    assert_includes error.message, "x.gif"
  end
end
