module Api
  module V1
    class StatusController < BaseController
      # GET /api/v1/status  -> what the demo page needs to open on the right place
      def show
        lat, lng = DemoMode.center
        render json: {
          status: "ok",
          demo_mode: DemoMode.enabled?,
          center: { lat: lat, lng: lng },
          counts: { reports: Trash.for_heatmap.count, heat_cells: HeatCell.count }
        }
      end
    end
  end
end
