module Api
  module V1
    class StatusController < BaseController
      # GET /api/v1/status  -> what the demo page needs to open on the right place
      def show
        lat, lng = Demo::Mode.center
        render json: {
          status: "ok",
          demo_mode: Demo::Mode.enabled?,
          center: { lat: lat, lng: lng },
          legal: { version: Terms::VERSION, name: ENV["LEGAL_NAME"].presence, email: ENV["LEGAL_EMAIL"].presence },
          mail: { enabled: Messaging::Mailer.configured? },
          auth: { google_client_id: Auth::GoogleIdentity.client_id },
          counts: { reports: Trash.for_heatmap.count, heat_cells: HeatCell.count }
        }
      end
    end
  end
end
