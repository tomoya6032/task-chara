# lib/tasks/check_support_reports.rake
namespace :support_reports do
  desc "支援報告書機能の設定をチェック"
  task check_config: :environment do
    puts "\n" + "="*60
    puts "🔍 支援報告書機能 - 設定診断"
    puts "="*60 + "\n"

    errors = []
    warnings = []

    # 1. OpenAI API Key のチェック
    print "1. OpenAI API Key... "
    api_key = ENV["OPENAI_API_KEY"] || Rails.application.credentials.dig(:openai, :api_key) || ENV["OPENAI_ACCESS_TOKEN"]
    if api_key.present?
      puts "✅ 設定済み (#{api_key[0..10]}...)"

      # API接続テスト
      print "   - API接続テスト... "
      begin
        client = OpenAI::Client.new
        response = client.models.list
        if response["data"]&.any?
          puts "✅ 接続成功"
        else
          puts "⚠️ 接続できましたが、レスポンスが不正です"
          warnings << "OpenAI APIの接続テストでレスポンスが不正です"
        end
      rescue => e
        puts "❌ 接続失敗: #{e.message}"
        errors << "OpenAI APIに接続できません: #{e.message}"
      end
    else
      puts "❌ 未設定"
      errors << "OPENAI_API_KEY環境変数が設定されていません"
      puts "   → heroku config:set OPENAI_API_KEY=your_key"
    end

    # 2. Active Storage の設定チェック
    print "\n2. Active Storage... "
    storage_service = Rails.application.config.active_storage.service
    puts "#{storage_service}"

    if Rails.env.production?
      if storage_service == :amazon
        puts "   ✅ 本番環境でS3を使用（推奨）"

        # AWS認証情報のチェック
        print "   - AWS_ACCESS_KEY_ID... "
        if ENV["AWS_ACCESS_KEY_ID"].present?
          puts "✅ 設定済み"
        else
          puts "❌ 未設定"
          errors << "AWS_ACCESS_KEY_ID環境変数が設定されていません"
        end

        print "   - AWS_SECRET_ACCESS_KEY... "
        if ENV["AWS_SECRET_ACCESS_KEY"].present?
          puts "✅ 設定済み"
        else
          puts "❌ 未設定"
          errors << "AWS_SECRET_ACCESS_KEY環境変数が設定されていません"
        end

        print "   - AWS_S3_BUCKET... "
        if ENV["AWS_S3_BUCKET"].present?
          puts "✅ 設定済み (#{ENV['AWS_S3_BUCKET']})"
        else
          puts "❌ 未設定"
          errors << "AWS_S3_BUCKET環境変数が設定されていません"
        end

        print "   - AWS_REGION... "
        region = ENV["AWS_REGION"] || "ap-northeast-1"
        puts "✅ #{region}"

      elsif storage_service == :local
        puts "   ⚠️ 本番環境でローカルストレージを使用（非推奨）"
        warnings << "本番環境ではS3の使用を推奨します。Dyno再起動でファイルが消失します。"
        puts "   → AWS S3を設定してください"
      end
    else
      puts "   ✅ 開発環境でローカルストレージを使用"
    end

    # 3. ImageMagick の可用性チェック
    print "\n3. ImageMagick (PDF→画像変換)... "
    begin
      require "mini_magick"
      version_output = MiniMagick::Tool::Convert.new { |c| c.version }
      version = version_output.match(/ImageMagick (\d+\.\d+\.\d+)/)[1] rescue "不明"
      puts "✅ インストール済み (version #{version})"
    rescue LoadError
      puts "❌ mini_magick gem が利用できません"
      errors << "mini_magick gemがインストールされていません"
      puts "   → Gemfile に gem 'mini_magick' を追加してください"
    rescue MiniMagick::Error => e
      puts "❌ ImageMagickがインストールされていません"
      errors << "ImageMagickがインストールされていません"
      puts "   → Herokuの場合: heroku buildpacks:add https://github.com/DarthSim/heroku-buildpack-imagemagick"
    end

    # 4. Solid Queue Worker のチェック
    print "\n4. Solid Queue Worker... "
    if Rails.env.production?
      # Heroku環境でWorkerプロセスが起動しているかチェック
      # （実際の確認は heroku ps コマンドで行う必要があります）
      puts "確認が必要"
      puts "   → heroku ps --app your-app-name でworkerプロセスを確認してください"
      puts "   → worker=0の場合: heroku ps:scale worker=1 --app your-app-name"
    else
      puts "✅ 開発環境（同期実行）"
    end

    # 5. ジョブキューの状態
    print "\n5. ジョブキュー (Solid Queue)... "
    begin
      # Solid Queueのジョブ統計
      total_jobs = SolidQueue::Job.count
      unfinished_jobs = SolidQueue::Job.where(finished_at: nil).count
      failed_jobs = SolidQueue::FailedExecution.count

      puts "✅ 稼働中"
      puts "   - 全ジョブ数: #{total_jobs}件"
      puts "   - 未完了のジョブ: #{unfinished_jobs}件"
      puts "   - 失敗したジョブ: #{failed_jobs}件" if failed_jobs > 0

      if failed_jobs > 0
        warnings << "失敗したジョブが#{failed_jobs}件あります。ログを確認してください。"
      end
    rescue => e
      puts "⚠️ 確認できませんでした: #{e.message}"
      warnings << "Solid Queueの状態を確認できませんでした。データベース接続を確認してください。"
    end

    # 6. テンプレートの存在確認
    print "\n6. 報告書テンプレート... "
    template_count = ReportTemplate.count
    if template_count > 0
      puts "✅ #{template_count}件登録済み"
      default_template = ReportTemplate.defaults.first
      if default_template
        puts "   - デフォルトテンプレート: #{default_template.name}"
      else
        warnings << "デフォルトテンプレートが設定されていません"
      end
    else
      puts "⚠️ テンプレートが登録されていません"
      warnings << "支援報告書のテンプレートを作成してください"
    end

    # 7. RAILS_MASTER_KEY のチェック（本番環境のみ）
    if Rails.env.production?
      print "\n7. RAILS_MASTER_KEY... "
      if ENV["RAILS_MASTER_KEY"].present?
        puts "✅ 設定済み"
      elsif Rails.application.credentials.config.present?
        puts "✅ credentials.yml.encが読み込まれています"
      else
        puts "⚠️ 未設定または読み込めません"
        warnings << "RAILS_MASTER_KEY環境変数が設定されていない可能性があります"
        puts "   → heroku config:set RAILS_MASTER_KEY=your_master_key"
      end
    end

    # 結果サマリー
    puts "\n" + "="*60
    puts "📊 診断結果サマリー"
    puts "="*60

    if errors.empty? && warnings.empty?
      puts "\n✅ すべての設定が正常です！"
      puts "支援報告書機能は正しく動作する準備が整っています。\n"
    else
      if errors.any?
        puts "\n❌ エラー (#{errors.count}件):"
        errors.each_with_index do |error, i|
          puts "   #{i + 1}. #{error}"
        end
      end

      if warnings.any?
        puts "\n⚠️ 警告 (#{warnings.count}件):"
        warnings.each_with_index do |warning, i|
          puts "   #{i + 1}. #{warning}"
        end
      end

      puts "\n📖 詳細な設定手順は HEROKU_SUPPORT_REPORTS_SETUP.md を参照してください。\n"
    end

    puts "="*60 + "\n"
  end

  desc "支援報告書のテスト生成（開発環境用）"
  task test_generate: :environment do
    unless Rails.env.development?
      puts "❌ このタスクは開発環境でのみ実行できます"
      exit 1
    end

    puts "\n🧪 支援報告書のテスト生成を開始します...\n"

    # テストデータの作成
    user = User.first || User.create!(
      email: "test@example.com",
      password: "password",
      password_confirmation: "password"
    )

    character = user.characters.first || user.characters.create!(
      name: "テストキャラクター",
      strength: 50,
      intelligence: 50,
      dexterity: 50,
      luck: 50
    )

    # テスト用の日報データを作成
    3.times do |i|
      character.activities.create!(
        title: "テスト活動#{i + 1}",
        content: "これはテスト用の日報データです。内容#{i + 1}",
        category: "work",
        mood_level: 3,
        fatigue_level: 3,
        visit_start_time: (Time.current - i.days).beginning_of_day + 10.hours,
        visit_end_time: (Time.current - i.days).beginning_of_day + 11.hours
      )
    end

    # 支援報告書を作成
    report = character.support_reports.create!(
      title: "テスト支援報告書",
      period_start: 1.week.ago.to_date,
      period_end: Date.current,
      status: :draft
    )

    puts "✅ テストデータを作成しました"
    puts "   - 支援報告書ID: #{report.id}"
    puts "   - 対象期間: #{report.period_display}"
    puts "\n📝 AI生成を開始します...\n"

    # AI生成を実行
    service = SupportReportGeneratorService.new(report)
    if service.generate
      puts "\n✅ 支援報告書の生成に成功しました！"
      puts "\n--- 生成された内容 (最初の500文字) ---"
      puts report.reload.content.to_s[0..500]
      puts "...\n"
      puts "\n📊 完全な内容を確認: rails console で SupportReport.find(#{report.id}).content"
    else
      puts "\n❌ 支援報告書の生成に失敗しました"
      puts "ログを確認してください: tail -f log/development.log"
    end

    puts "\n"
  end
end
