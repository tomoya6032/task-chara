require 'rails_helper'

RSpec.describe "Activities", type: :request do
  describe "GET /create" do
    it "returns http success" do
      get "/activities/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/activities/show"
      expect(response).to have_http_status(:success)
    end
  end

end
