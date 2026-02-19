// app/javascript/controllers/template_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  applyWelfareTemplate() {
    const textarea = document.querySelector('textarea[name="activity[content]"]')
    const categorySelect = document.querySelector('select[name="activity[category]"]')
    
    if (textarea && categorySelect) {
      categorySelect.value = 'welfare'
      textarea.value = `【訪問福祉業務】
■ 利用者情報
- 氏名：
- 年齢：
- 住所：

■ 実施したサービス
- 身体介護（　　　）
- 生活援助（　　　）
- その他（　　　　）

■ 利用者の状況・変化
- 

■ 特記事項・申し送り
- 

■ 次回の注意点
- `
      
      // 文字数カウンターを更新
      const event = new Event('input', { bubbles: true })
      textarea.dispatchEvent(event)
    }
  }

  applyWebTemplate() {
    const textarea = document.querySelector('textarea[name="activity[content]"]')
    const categorySelect = document.querySelector('select[name="activity[category]"]')
    
    if (textarea && categorySelect) {
      categorySelect.value = 'web'
      textarea.value = `【Web制作業務】
■ プロジェクト名
- 

■ 今日の作業内容
- デザイン作業：
- コーディング作業：
- テスト・デバッグ：
- その他：

■ 進捗状況
- 完了：
- 進行中：
- 課題・問題点：

■ 明日の予定
- `
      
      const event = new Event('input', { bubbles: true })
      textarea.dispatchEvent(event)
    }
  }

  applyAdminTemplate() {
    const textarea = document.querySelector('textarea[name="activity[content]"]')
    const categorySelect = document.querySelector('select[name="activity[category]"]')
    
    if (textarea && categorySelect) {
      categorySelect.value = 'admin'
      textarea.value = `【事務作業】
■ 処理した業務
- 書類作成：
- データ入力：
- 電話対応：
- メール対応：
- その他：

■ 完了件数
- 

■ 課題・改善点
- 

■ 明日の予定
- `
      
      const event = new Event('input', { bubbles: true })
      textarea.dispatchEvent(event)
    }
  }

  applyMedicalTemplate() {
    const textarea = document.querySelector('textarea[name="activity[content]"]')
    const categorySelect = document.querySelector('select[name="activity[category]"]')
    
    if (textarea && categorySelect) {
      categorySelect.value = 'medical'
      textarea.value = `【医療・看護業務】
■ 患者・利用者対応
- 

■ 実施した処置・ケア
- 

■ 記録・報告業務
- 

■ チーム連携・申し送り
- 

■ 特記事項
- `
      
      const event = new Event('input', { bubbles: true })
      textarea.dispatchEvent(event)
    }
  }
}