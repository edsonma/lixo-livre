# The author's side of a report: putting it on the map, changing their mind, taking it back.
module Trash::Publishing
  extend ActiveSupport::Concern

  class NotPublishable < StandardError; end

  class_methods do
    # A report goes to the map as soon as the AI validates it (the AI's confidence decides how much it
    # weighs, see HeatScore). AUTO_PUBLISH=false brings back the manual "Publicar" step for the author.
    def auto_publish?
      !%w[false 0 no off].include?(ENV["AUTO_PUBLISH"].to_s.strip.downcase)
    end
  end

  def published?
    published_at.present?
  end

  # Scored, photo sanitized, still private: the author may publish it.
  def publishable?
    validated? && sanitized_at.present? && hidden_at.nil? && !published?
  end

  def publish!
    raise NotPublishable, "report #{id} cannot be published (status #{ai_status}, published: #{published?})" unless publishable?

    update!(published_at: Time.current)
  end

  # The author changed their mind. Only an unpublished report can be thrown away this way.
  def discard_draft!
    raise NotPublishable, "report #{id} is already published" if published?

    destroy!
  end

  # The author takes a report back, published or not. A published one leaves the map and the cell is re-scored.
  def withdraw!
    destroy!
  end
end
