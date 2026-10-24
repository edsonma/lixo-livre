# Wrapper around the AI vision provider.
# Contract: analyze(photo) returns a Result the ValidateTrashJob understands.
class TrashVision
  Result = Struct.new(:is_trash, :severity, :types, :confidence, :raw, keyword_init: true)

  def self.analyze(photo)
    # Development and test get a fake result so the whole pipeline works end to end.
    return fake_result if Rails.env.local?

    # TODO: call your AI vision provider here. Send the image and ask for JSON with
    # is_trash (bool), severity (1-5), types (subset of Trash::TYPES), confidence (0-1).
    raise NotImplementedError, "Wire an AI vision provider into TrashVision.analyze"
  end

  def self.fake_result
    Result.new(
      is_trash: true,
      severity: rand(1..5),
      types: Trash::TYPES.sample(rand(1..2)),
      confidence: 0.9,
      raw: { provider: "fake" }
    )
  end
  private_class_method :fake_result
end
