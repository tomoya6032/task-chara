namespace :db do
  namespace :migrate do
    desc "Migrate cable database"
    task cable: :environment do
      # production環境でのみ実行（developmentはasyncアダプターを使用）
      if Rails.env.production?
        puts "🔄 Migrating cable database..."
        
        cable_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "cable")
        
        if cable_config
          # Rails 8 互換: with_temporary_connection を使用してマイグレーションを実行
          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(cable_config) do
            cable_migrations_path = Rails.root.join("db/cable_migrate").to_s
            
            # Rails 8: MigrationContext は第1引数（マイグレーションパス配列）のみで動作
            migration_context = ActiveRecord::MigrationContext.new([cable_migrations_path])
            migration_context.migrate
            
            puts "✅ Cable database migration complete"
          end
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
          # Rails 8 互換: with_temporary_connection を使用
          ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(cable_config) do
            # スキーマをロード
            schema_path = Rails.root.join("db/cable_schema.rb")
            if File.exist?(schema_path)
              load(schema_path)
              puts "✅ Cable schema loaded"
            end
            
            # Rails 8: MigrationContext は第1引数（マイグレーションパス配列）のみで動作
            cable_migrations_path = Rails.root.join("db/cable_migrate").to_s
            migration_context = ActiveRecord::MigrationContext.new([cable_migrations_path])
            migration_context.migrate
            
            puts "✅ Cable database prepared"
          end
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
