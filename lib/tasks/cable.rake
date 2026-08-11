namespace :db do
  namespace :migrate do
    desc "Migrate cable database"
    task cable: :environment do
      # production環境でのみ実行（developmentはasyncアダプターを使用）
      if Rails.env.production?
        puts "🔄 Migrating cable database..."
        
        # cable接続に切り替え
        ActiveRecord::Base.establish_connection(:cable)
        
        # マイグレーションパスを設定
        ActiveRecord::MigrationContext.new(
          Rails.root.join("db/cable_migrate").to_s,
          ActiveRecord::SchemaMigration
        ).migrate
        
        puts "✅ Cable database migration complete"
        
        # primary接続に戻す
        ActiveRecord::Base.establish_connection(:primary)
      else
        puts "⏭️  Skipping cable migration in #{Rails.env} environment (uses async adapter)"
      end
    end
  end
  
  namespace :prepare do
    desc "Prepare cable database"
    task cable: :environment do
      if Rails.env.production?
        puts "🔄 Preparing cable database..."
        
        ActiveRecord::Base.establish_connection(:cable)
        
        # スキーマをロード
        schema_path = Rails.root.join("db/cable_schema.rb")
        if File.exist?(schema_path)
          load(schema_path)
          puts "✅ Cable schema loaded"
        end
        
        # マイグレーションを実行
        ActiveRecord::MigrationContext.new(
          Rails.root.join("db/cable_migrate").to_s,
          ActiveRecord::SchemaMigration
        ).migrate
        
        puts "✅ Cable database prepared"
        
        ActiveRecord::Base.establish_connection(:primary)
      else
        puts "⏭️  Skipping cable preparation in #{Rails.env} environment"
      end
    end
  end
end

# rails db:prepare 実行時に自動的にcableデータベースも準備
Rake::Task["db:prepare"].enhance do
  Rake::Task["db:prepare:cable"].invoke if Rails.env.production?
end
