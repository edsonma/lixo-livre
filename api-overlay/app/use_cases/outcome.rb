# What a use case hands back when failing is an expected result (a wrong password, terms not accepted)
# and not a bug. `error` is a symbol; the controller turns it into the API's error code and status.
# Real bugs and invalid records still raise, and the controllers' rescue_from answer for them.
class Outcome
  attr_reader :value, :error

  def self.success(value = nil) = new(value, nil)
  def self.failure(error) = new(nil, error)

  def initialize(value, error)
    @value = value
    @error = error
  end

  def success? = error.nil?
end
