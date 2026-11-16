require "test_helper"

# The rules for what a person may write on their profile. No database needed.
class ProfileTextTest < ActiveSupport::TestCase
  test "a website without a scheme gets https, and a blank one becomes nil" do
    assert_equal "https://lixolivre.com", ProfileText.website("lixolivre.com")
    assert_equal "https://lixolivre.com", ProfileText.website("  lixolivre.com ")
    assert_equal "http://exemplo.com.br/a", ProfileText.website("http://exemplo.com.br/a")
    assert_equal "https://exemplo.com", ProfileText.website("HTTPS://exemplo.com")
    assert_nil ProfileText.website("   ")
    assert_nil ProfileText.website(nil)
  end

  test "only real http and https addresses count as a web address" do
    good = ["https://lixolivre.com", "http://exemplo.com.br/a?b=1", "https://sub.exemplo.com:8443/x"]
    good.each { |url| assert ProfileText.web_address?(url), url }

    bad = ["javascript:alert(1)", "https://javascript:alert(1)", "ftp://exemplo.com", "https://localhost", "https://exemplo.",
           "https://user:pass@exemplo.com", "https://exem plo.com", "https://", "data:text/html,hi", "//exemplo.com"]
    bad.each { |url| assert_not ProfileText.web_address?(ProfileText.website(url)), url }
  end

  test "a bio is plain text: no control characters, no runs of blank lines, trimmed" do
    assert_equal "Cuido do bairro.\n\nAbraços", ProfileText.bio("  Cuido do bairro.  \r\n\r\n\r\n\r\nAbraços \n")
    assert_equal "ab", ProfileText.bio("a\u0000b\u0007")
    assert_equal "a b", ProfileText.bio("a b")
    assert_nil ProfileText.bio(" \n\t ")
    assert_nil ProfileText.bio(nil)
  end

  test "a gender is lower-cased, and blank becomes nil" do
    assert_equal "female", ProfileText.gender(" Female ")
    assert_nil ProfileText.gender("")
    assert_nil ProfileText.gender(nil)
  end
end
