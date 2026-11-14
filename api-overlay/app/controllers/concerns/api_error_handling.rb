# One answer for each kind of failure, so no action has to build its own.
module ApiErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordInvalid do |e|
      render json: { errors: e.record.errors.to_hash }, status: :unprocessable_entity
    end
    rescue_from ActiveRecord::RecordNotFound do
      head :not_found
    end
    rescue_from ActionController::ParameterMissing do |e|
      render json: { errors: { e.param => ["is required"] } }, status: :bad_request
    end
  end
end
