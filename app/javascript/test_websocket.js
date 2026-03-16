// テスト用のWebSocket関数をグローバルに追加
window.testWebSocketConnection = function(activityId) {
  console.log("🧪 Testing WebSocket connection for activity:", activityId)
  
  const consumer = createConsumer()
  const testSubscription = consumer.subscriptions.create(
    { 
      channel: "AiProcessingChannel", 
      activity_id: activityId 
    },
    {
      connected() {
        console.log("✅ Test connection successful!")
        
        // テスト用のデータを処理
        setTimeout(() => {
          this.received({
            type: 'image_ocr',
            status: 'completed',
            content: 'テスト用の文字起こし結果です。\n\n訪問内容：動作確認のためのテストを実施しました。'
          })
        }, 1000)
      },
      
      disconnected() {
        console.log("❌ Test connection disconnected")
      },
      
      received(data) {
        console.log("📨 Test data received:", data)
        window.handleAiProcessingResult(data)
      }
    }
  )
  
  // 10秒後に接続を切断
  setTimeout(() => {
    consumer.subscriptions.remove(testSubscription)
    console.log("🔌 Test connection closed")
  }, 10000)
}

// テストファイルの読み込み確認
console.log("📡 WebSocket test utilities loaded")
console.log("Usage: testWebSocketConnection('your_activity_id')")