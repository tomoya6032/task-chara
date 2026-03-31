FactoryBot.define do
  factory :meeting_minute do
    title { "MyString" }
    meeting_type { 1 }
    meeting_date { "2026-03-26 05:50:58" }
    content { "MyText" }
    participants { "MyText" }
    location { "MyString" }
    character { nil }
    status { 1 }
    generated_at { "2026-03-26 05:50:58" }
  end
end
