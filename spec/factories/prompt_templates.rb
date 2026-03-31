FactoryBot.define do
  factory :prompt_template do
    name { "MyString" }
    meeting_type { 1 }
    prompt_type { 1 }
    system_prompt { "MyText" }
    user_prompt_template { "MyText" }
    is_active { false }
    organization_id { 1 }
    description { "MyText" }
  end
end
