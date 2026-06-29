Rails.application.routes.draw do
  # Letter Opener Web (development only)
  if Rails.env.development? && defined?(LetterOpenerWeb)
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  devise_for :users
  # LINE Messaging API Webhook
  post "line/callback", to: "line_webhooks#callback"

  # AI Secretary routes
  get "ai_secretary/chat"
  post "ai_secretary/send_message"
  post "ai_secretary/extract_tasks_from_chat"
  get "ai_secretary/conversation_history"
  get "ai_secretary/conversation_list"
  post "ai_secretary/new_conversation"
  post "ai_secretary/create_calendar_event"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Dashboard routes
  get "dashboard", to: "dashboards#show"
  root "dashboards#show"

  # Settings routes
  get "settings", to: "settings#show"
  patch "settings", to: "settings#update"
  delete "settings/line", to: "settings#unlink_line", as: :unlink_line

  # LINE Login OAuth routes (Messaging API連携用)
  get "line_login/authorize", to: "line_login#authorize", as: :line_login_authorize
  get "line_login/callback", to: "line_login#callback", as: :line_login_callback

  # Calendar routes
  resources :calendar, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    member do
      post :notify_line
    end
    collection do
      get :events
      post :sync_external
      get :settings
      patch :update_settings
    end
  end

  # Activities routes
  resources :activities, only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
    collection do
      post :generate_from_chat
    end
    member do
      post :process_image_ocr
      post :process_voice_transcription
      post :extract_tasks
    end
  end

  # Support Reports routes
  resources :support_reports do
    collection do
      post :generate_from_chat
    end
    member do
      post :generate
      get :download_pdf
    end
  end

  # Meeting Minutes routes
  resources :meeting_minutes do
    collection do
      post :process_image_ocr_new
      post :process_voice_transcription_new
      post :generate_from_chat
    end
    member do
      post :generate
      post :process_image_ocr
      post :process_voice_transcription
    end
  end

  # Report Templates routes
  resources :report_templates do
    member do
      post :analyze
    end
  end

  # Prompt Templates routes (AI生成プロンプト管理)
  resources :prompt_templates do
    member do
      patch :toggle_active
    end
    collection do
      get :preview
    end
  end

  # Tasks routes
  resources :tasks, only: [ :index, :new, :create, :show, :edit, :update ] do
    member do
      post :notify_line
      patch :complete
      patch :hide
      patch :unhide
      patch :approve
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
