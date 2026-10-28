Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise needs the :user mapping to sign people in; the controllers under Api::V1 do the work.
  devise_for :users, skip: :all

  namespace :api do
    namespace :v1 do
      get "status", to: "status#show"
      resources :devices, only: :create
      get "heatmap", to: "heatmap#index"
      get "places/:h3_index", to: "places#show"
      get "rankings", to: "rankings#index"
      get "follows", to: "follows#index"
      post "follows", to: "follows#create"
      delete "follows/:h3_index", to: "follows#destroy"
      get "notifications", to: "notifications#index"
      post "notifications/read", to: "notifications#read_all"

      resources :trashes, only: %i[index show create] do
        resources :flags, only: :create
      end

      get "me/trashes", to: "me#trashes"
      get "me/feed", to: "me#feed"
      get "me/trashes/:id", to: "me#show"
      post "me/trashes/:id/publish", to: "me#publish"
      delete "me/trashes/:id", to: "me#destroy"

      namespace :admin do
        resources :reviews, only: :index do
          member do
            post :approve
            post :reject
          end
        end
      end

      resource :session, only: %i[show create destroy]
      post "session/google", to: "google_sessions#create"
      post "users", to: "registrations#create"
      get "passkeys", to: "passkeys#index"
      post "passkeys", to: "passkeys#create"
      delete "passkeys/:id", to: "passkeys#destroy"
      post "passkeys/registration_options", to: "passkeys#registration_options"
      post "passkeys/authentication_options", to: "passkeys#authentication_options"
      post "passkeys/authenticate", to: "passkeys#authenticate"
    end
  end
end
