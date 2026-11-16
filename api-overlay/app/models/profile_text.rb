require "uri"

# The text a person writes on their profile, cleaned before it is stored. Plain functions with no
# database, so every rule can be tested alone.
module ProfileText
  BIO_MAX = 160
  WEBSITE_MAX = 200
  GENDERS = %w[female male non_binary other prefer_not_to_say].freeze

  # A bio is plain text: no control characters, at most one blank line in a row, no spaces around it.
  # nil when nothing is left.
  def self.bio(value)
    text = value.to_s.gsub("\r\n", "\n").gsub(/[^\P{Cc}\n]/, "").gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip
    text.empty? ? nil : text
  end

  # "lixolivre.com" and "https://lixolivre.com/x" both become a full web address; nil when blank.
  # Only http and https are ever accepted (a "javascript:" link must never reach a page), so anything that
  # does not parse as one is returned unchanged for the model to refuse.
  def self.website(value)
    text = value.to_s.strip
    return nil if text.empty?

    text.match?(%r{\Ahttps?://}i) ? text.sub(%r{\A[^:]+}) { |scheme| scheme.downcase } : "https://#{text}"
  end

  # Is this normalized address something we are willing to link to?
  def self.web_address?(text)
    uri = URI.parse(text.to_s)
    uri.is_a?(URI::HTTP) && uri.host.to_s.include?(".") && !uri.host.to_s.end_with?(".") &&
      uri.userinfo.nil? && !text.match?(/\s/)
  rescue URI::InvalidURIError
    false
  end

  # nil when blank, otherwise as given (the model checks it is one of GENDERS).
  def self.gender(value)
    text = value.to_s.strip.downcase
    text.empty? ? nil : text
  end
end
