Rails.application.routes.draw do
  root to: "assistants#index"

  resources :users, only: [:new, :create, :update]

  resources :assistants do
    resources :messages, only: [:new, :create, :edit]
  end

  resources :conversations, only: [:show, :edit, :update, :destroy] do
    resources :messages, only: [:index]
  end

  resources :messages, only: [:show, :update]

  namespace :settings do
    resources :assistants, except: [:index, :show]
    resource :person, only: [:edit, :update]
    resources :language_models
    resources :api_services, except: [:show]
    resources :memories, only: [:index] do
      delete :destroy, on: :collection
    end
  end

  get "/login", to: "authentications#new"
  post "/login", to: "authentications#create"
  get "/register", to: "users#new"
  get "/logout", to: "authentications#destroy"

  if Feature.password_reset_email?
    resources :password_resets, only: [:new, :create]
    resource :password_credential, only: [:edit, :update]
  end

  get "/auth/:provider/callback" => "authentications/google_oauth#create", as: :google_oauth
  get "/auth/failure" => "authentications/google_oauth#failure" # connected in omniauth.rb

  namespace :tiktok do
    get "connections" => "connections#show", as: :connections
    get "connections/content/authorize" => "connections#new_content", as: :connections_content_authorize
    get "connections/content/callback" => "connections#callback_content", as: :connections_content_callback
    delete "connections/content" => "connections#destroy_content", as: :connections_content
    get "connections/ads/authorize" => "connections#new_ads", as: :connections_ads_authorize
    get "connections/ads/callback" => "connections#callback_ads", as: :connections_ads_callback
    delete "connections/ads" => "connections#destroy_ads", as: :connections_ads
    post "connections/ad_accounts/sync" => "connections#sync_ad_accounts", as: :connections_sync_ad_accounts

    resources :videos, only: [:index, :new, :create, :show, :destroy]

    resources :campaigns, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
      member do
        get :audience
        patch :audience, action: :update_audience
        get :creative
        patch :creative, action: :update_creative
        get :review
        post :launch
      end
    end
  end

  # resources :documents  TODO: finish this feature

  get "/rails/active_storage/postgresql/:encoded_key/*filename" => "active_storage/postgresql#show", as: :rails_postgresql_service
  put "/rails/active_storage/postgresql/:encoded_token" => "active_storage/postgresql#update", as: :update_rails_postgresql_service

  get "up" => "rails/health#show", as: :rails_health_check
end
