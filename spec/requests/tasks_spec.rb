require 'rails_helper'

RSpec.describe "Tasks", type: :request do
  describe "GET /create" do
    it "returns http success" do
      get "/tasks/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /complete" do
    it "returns http success" do
      get "/tasks/complete"
      expect(response).to have_http_status(:success)
    end
  end

end
