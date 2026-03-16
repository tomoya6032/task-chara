Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Dashboard routes
  get "dashboard", to: "dashboards#show"
  root "dashboards#show"

  # Activities routes
  resources :activities, only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
    member do
      post :process_image_ocr
      post :process_voice_transcription
    end
  end

  # Support Reports routes
  resources :support_reports do
    member do
      post :generate
    end
  end

  # Report Templates routes
  resources :report_templates do
    member do
      post :analyze
    end
  end

  # Tasks routes
  resources :tasks, only: [ :index, :new, :create, :show ] do
    member do
      patch :complete
      patch :hide
      patch :unhide
      delete :destroy
    end
    collection do
      get :hidden
      get :completed
    end
  end

  # Special actions routes
  post "sauna/activate", to: "special_actions#sauna_activate"
  post "rewards/claim", to: "special_actions#claim_reward"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Mount ActionCable
  mount ActionCable.server => "/cable"

  # Defines the root path route ("/")
  # root "posts#index"
end
