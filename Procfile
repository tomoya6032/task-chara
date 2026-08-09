web: bundle exec puma -C config/puma.rb
worker: MALLOC_ARENA_MAX=2 RUBY_GC_HEAP_GROWTH_FACTOR=1.1 RUBY_GC_HEAP_GROWTH_MAX_SLOTS=10000 bundle exec rake solid_queue:start
