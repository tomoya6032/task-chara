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
      temp_file = Tempfile.new(['template', '.pdf'])
      temp_file.binmode
      temp_file.write(template.pdf_file.download)
      temp_file.rewind

      Rails.logger.info "PDF file saved to: #{temp_file.path}"

      # OpenAI Vision APIで構造解析
      format_instructions = analyze_pdf_structure(temp_file.path, template.name)

      if format_instructions.present?
        template.update!(
          format_instructions: format_instructions
        )
        Rails.logger.info "✅ Template analysis completed successfully"
      else
        Rails.logger.error "❌ Failed to extract format instructions"
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

                    1. 文書の構造（セクション、見出し、項目の階層）
                    2. 使用されている書式パターン（箇条書き、番号付きリスト等）
                    3. 日付、時間、場所などの定型項目
                    4. 特徴的な表現や定型文
                    5. レイアウトの特徴

                    この情報を元に、同様の形式で報告書を生成するためのフォーマット指示文を作成してください。
                    指示文は、AIが報告書を生成する際に参考にする具体的で実用的な内容にしてください。

                    例:
                    - 見出しは「■」で始める
                    - 日時は「令和○年○月○日」形式で記載
                    - 活動内容は箇条書きで「・」を使用
                    - 最後に「以上」で締める

                    回答は日本語で、フォーマット指示のみを返してください。
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

      format_instructions = response.dig("choices", 0, "message", "content")
      Rails.logger.info "Format instructions extracted: #{format_instructions&.truncate(200)}"
      
      format_instructions

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
      require 'mini_magick'
      
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