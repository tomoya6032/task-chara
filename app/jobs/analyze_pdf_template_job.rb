# app/jobs/analyze_pdf_template_job.rb
class AnalyzePdfTemplateJob < ApplicationJob
  queue_as :default

  def perform(template_id)
    Rails.logger.info "=== PDF Template Analysis Started ==="
    Rails.logger.info "Template ID: #{template_id}"

    template = ReportTemplate.find(template_id)

    unless template.pdf_file.attached?
      Rails.logger.error "No PDF file attached to template #{template_id}"
      return
    end

    begin
      # PDFファイルを一時ファイルとして保存
      temp_file = Tempfile.new([ "template", ".pdf" ])
      temp_file.binmode
      temp_file.write(template.pdf_file.download)
      temp_file.rewind

      Rails.logger.info "PDF file saved to: #{temp_file.path}"

      # OpenAI Vision APIで構造解析
      pdf_content = analyze_pdf_structure(temp_file.path, template.name)

      if pdf_content.present?
        template.update!(
          content: pdf_content
        )
        Rails.logger.info "✅ Template analysis completed successfully"
      else
        Rails.logger.error "❌ Failed to extract template content"
      end

    rescue => e
      Rails.logger.error "PDF analysis error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    ensure
      temp_file&.close
      temp_file&.unlink
    end
  end

  private

  def analyze_pdf_structure(pdf_path, template_name)
    Rails.logger.info "Analyzing PDF structure with OpenAI Vision API..."

    # PDFを画像に変換 (最初のページのみ)
    image_path = convert_pdf_to_image(pdf_path)
    return nil unless image_path

    begin
      client = OpenAI::Client.new

      # Base64エンコード
      image_data = Base64.strict_encode64(File.read(image_path))

      response = client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text: <<~PROMPT
                    この報告書テンプレート「#{template_name}」のPDF画像を分析して、以下の情報を抽出してください：

                    1. 文書の全体構成（セクション、見出し、項目の階層）
                    2. 各セクションのタイトルと内容の枠組み
                    3. 使用されている書式パターン（見出し記号、箇条書き、番号付きリスト等）
                    4. 日付、時間、場所、署名などの定型項目と配置
                    5. 特徴的な表現や定型文
                    6. レイアウトの特徴（インデント、改行、区切り線等）

                    この情報を元に、報告書の基本構成・項目枠を示すテンプレートとして整理してください。
                    各セクションは「■ セクション名」の形式で表し、必要な項目や構成要素を簡潔に記載してください。

                    例:
                    ■ 報告書タイトル
                    ■ 対象期間と利用者情報
                    ■ 支援内容の概要
                    ■ 詳細な支援記録
                    ■ 気分・体調の傾向
                    ■ 今後の支援方針
                    ■ 作成日・作成者

                    回答は日本語で、テンプレートの基本構成のみを返してください。
                  PROMPT
                },
                {
                  type: "image_url",
                  image_url: {
                    url: "data:image/jpeg;base64,#{image_data}"
                  }
                }
              ]
            }
          ],
          max_tokens: 2000,
          temperature: 0.3
        }
      )

      pdf_content = response.dig("choices", 0, "message", "content")
      Rails.logger.info "Template content extracted: #{pdf_content&.truncate(200)}"

      pdf_content

    rescue => e
      Rails.logger.error "OpenAI API error: #{e.message}"
      nil
    ensure
      File.delete(image_path) if image_path && File.exist?(image_path)
    end
  end

  def convert_pdf_to_image(pdf_path)
    # PDFから画像への変換（ImageMagick/MiniMagickを使用）
    begin
      require "mini_magick"

      output_path = "#{pdf_path}_page_0.jpg"

      MiniMagick::Tool::Convert.new do |convert|
        convert << "#{pdf_path}[0]"  # 最初のページのみ
        convert.resize "1200x1600>"   # 適切なサイズに調整
        convert.quality "85"
        convert << output_path
      end

      Rails.logger.info "PDF converted to image: #{output_path}"
      output_path

    rescue LoadError
      Rails.logger.error "MiniMagick gem not available. Install with: gem install mini_magick"
      nil
    rescue => e
      Rails.logger.error "PDF to image conversion failed: #{e.message}"
      nil
    end
  end
end
