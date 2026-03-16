FactoryBot.define do
  factory :report_template do
    name { "MyString" }
    description { "MyText" }
    format_instructions { "MyText" }
    is_default { false }
    user_id { 1 }
  end
end
