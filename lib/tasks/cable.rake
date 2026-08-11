namespace :db do
  namespace :migrate do
    desc "Migrate cable database"
    task cable: :environment do
      # production環境でのみ実行（developmentはasyncアダプターを使用）
      if Rails.env.production?
        puts "🔄 Migrating cable database..."
        
        cable_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "cable")
        
        if cable_config
          # cable接続に切り替え
          ActiveRecord::Base.establish_connection(:cable)
          
          # Rails 8 互換: マイグレーションディレクトリを指定して実行
          migrations_paths = [Rails.root.join("db/cable_migrate").to_s]
          ActiveRecord::MigrationContext.new(migrations_paths, ActiveRecord::Base.connection.schema_migration).migrate
          
          puts "✅ Cable database migration complete"
          
          # primary接続に戻す
          ActiveRecord::Base.establish_connection(:primary)
        else
          puts "⚠️  Cable database configuration not found"
        end
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
        
        cable_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "cable")
        
        if cable_config
          # cable接続に切り替え
          ActiveRecord::Base.establish_connection(:cable)
          
          # スキーマをロード
          schema_path = Rails.root.join("db/cable_schema.rb")
          if File.exist?(schema_path)
            load(schema_path)
            puts "✅ Cable schema loaded"
          end
          
          # Rails 8 互換: マイグレーションを実行
          migrations_paths = [Rails.root.join("db/cable_migrate").to_s]
          ActiveRecord::MigrationContext.new(migrations_paths, ActiveRecord::Base.connection.schema_migration).migrate
          
          puts "✅ Cable database prepared"
          
          # primary接続に戻す
          ActiveRecord::Base.establish_connection(:primary)
        else
          puts "⚠️  Cable database configuration not found"
        end
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
