require 'rails_helper'

RSpec.describe "AiSecretaries", type: :request do
  describe "GET /chat" do
    it "returns http success" do
      get "/ai_secretary/chat"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /send_message" do
    it "returns http success" do
      get "/ai_secretary/send_message"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /conversation_history" do
    it "returns http success" do
      get "/ai_secretary/conversation_history"
      expect(response).to have_http_status(:success)
    end
  end

end
