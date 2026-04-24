# 祝日データの種（seeds）ファイル
# 2026年の日本の祝日データ

holidays_2026 = [
  { name: '元日', date: Date.new(2026, 1, 1), description: '年の初めを祝う日', country: 'JP' },
  { name: '成人の日', date: Date.new(2026, 1, 12), description: '大人になったことを自覚し、自ら生き抜こうとする青年を祝い励ます日', country: 'JP' },
  { name: '建国記念の日', date: Date.new(2026, 2, 11), description: '建国をしのび、国を愛する心を養う日', country: 'JP' },
  { name: '天皇誕生日', date: Date.new(2026, 2, 23), description: '天皇の誕生日を祝う日', country: 'JP' },
  { name: '春分の日', date: Date.new(2026, 3, 20), description: '自然をたたえ、生物をいつくしむ日', country: 'JP' },
  { name: '昭和の日', date: Date.new(2026, 4, 29), description: '激動の日々を経て、復興を遂げた昭和の時代を顧み、国の将来に思いをいたす日', country: 'JP' },
  { name: '憲法記念日', date: Date.new(2026, 5, 3), description: '日本国憲法の施行を記念し、国の成長を期する日', country: 'JP' },
  { name: 'みどりの日', date: Date.new(2026, 5, 4), description: '自然に親しむとともにその恩恵に感謝し、豊かな心をはぐくむ日', country: 'JP' },
  { name: 'こどもの日', date: Date.new(2026, 5, 5), description: 'こどもの人格を重んじ、こどもの幸福をはかるとともに、母に感謝する日', country: 'JP' },
  { name: '海の日', date: Date.new(2026, 7, 20), description: '海の恩恵に感謝するとともに、海洋国日本の繁栄を願う日', country: 'JP' },
  { name: '山の日', date: Date.new(2026, 8, 11), description: '山に親しむ機会を得て、山の恩恵に感謝する日', country: 'JP' },
  { name: '敬老の日', date: Date.new(2026, 9, 21), description: '多年にわたり社会につくしてきた老人を敬愛し、長寿を祝う日', country: 'JP' },
  { name: '秋分の日', date: Date.new(2026, 9, 23), description: '祖先をうやまい、なくなった人々をしのぶ日', country: 'JP' },
  { name: 'スポーツの日', date: Date.new(2026, 10, 12), description: 'スポーツにしたしみ、健康な心身をつちかう日', country: 'JP' },
  { name: '文化の日', date: Date.new(2026, 11, 3), description: '自由と平和を愛し、文化をすすめる日', country: 'JP' },
  { name: '勤労感謝の日', date: Date.new(2026, 11, 23), description: '勤労をたっとび、生産を祝い、国民たがいに感謝しあう日', country: 'JP' }
]

puts '祝日データを追加しています...'

created_count = 0
holidays_2026.each do |holiday_data|
  if Holiday.find_by(date: holiday_data[:date], country: holiday_data[:country])
    puts "#{holiday_data[:name]} (#{holiday_data[:date]}) は既に存在します"
  else
    Holiday.create!(holiday_data)
    created_count += 1
    puts "#{holiday_data[:name]} (#{holiday_data[:date]}) を追加しました"
  end
end

puts "\n#{created_count}件の祝日データを追加しました！"
