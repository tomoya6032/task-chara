FactoryBot.define do
  factory :ai_token_usage do
    user { nil }
    organization { nil }
    ai_model { "MyString" }
    prompt_tokens { 1 }
    completion_tokens { 1 }
    total_tokens { 1 }
    cost { "9.99" }
    feature { "MyString" }
  end
end
