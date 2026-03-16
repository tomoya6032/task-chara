FactoryBot.define do
  factory :support_report do
    character { nil }
    title { "MyString" }
    period_start { "2026-03-10" }
    period_end { "2026-03-10" }
    content { "MyText" }
    generated_at { "2026-03-10 13:03:31" }
    status { 1 }
  end
end
