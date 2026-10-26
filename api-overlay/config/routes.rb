Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "status", to: "status#show"
      resources :devices, only: :create
      get "heatmap", to: "heatmap#index"

      resources :trashes, only: %i[index show create] do
        resources :flags, only: :create
      end

      get "me/trashes", to: "me#trashes"
      get "me/trashes/:id", to: "me#show"
      post "me/trashes/:id/publish", to: "me#publish"
      delete "me/trashes/:id", to: "me#destroy"
      # later: resource :session, resources :users (login)
    end
  end
end
