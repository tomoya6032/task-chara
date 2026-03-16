class ReportTemplate < ApplicationRecord
  belongs_to :user, optional: true
  has_one_attached :pdf_file

  validates :name, presence: true, length: { maximum: 100 }
  validates :pdf_file, presence: true, on: :create
  validate :pdf_file_format
  validate :only_one_default_per_user, if: :is_default?

  scope :for_user, ->(user) { where(user: user) }
  scope :defaults, -> { where(is_default: true) }
  scope :system_wide, -> { where(user_id: nil) }
  scope :available_for, ->(user) { where("user_id IS NULL OR user_id = ?", user&.id) }

  before_save :set_pdf_metadata

  def self.default_for_user(user)
    for_user(user).defaults.first || system_wide.defaults.first
  end

  def system_template?
    user_id.nil?
  end

  def available_for?(current_user)
    system_template? || user == current_user
  end

  def pdf_file_url
    pdf_file.attached? ? Rails.application.routes.url_helpers.rails_blob_path(pdf_file, only_path: true) : nil
  end

  def analyze_pdf_structure!
    return unless pdf_file.attached?

    begin
      # PDF構造をOpenAI Vision APIで解析
      AnalyzePdfTemplateJob.perform_later(id)
      Rails.logger.info "PDF analysis job queued for template #{id}"
    rescue => e
      Rails.logger.error "Failed to queue PDF analysis: #{e.message}"
      false
    end
  end

  private

  def pdf_file_format
    return unless pdf_file.attached?

    unless pdf_file.content_type == 'application/pdf'
      errors.add(:pdf_file, 'PDFファイルのみアップロード可能です')
    end

    if pdf_file.blob.byte_size > 10.megabytes
      errors.add(:pdf_file, 'ファイルサイズは10MB以下にしてください')
    end
  end

  def only_one_default_per_user
    existing_default = if user_id.present?
                        ReportTemplate.for_user(user).defaults.where.not(id: id)
                      else
                        ReportTemplate.system_wide.defaults.where.not(id: id)
                      end

    if existing_default.exists?
      errors.add(:is_default, 'デフォルトテンプレートは1つのみ設定できます')
    end
  end

  def set_pdf_metadata
    if pdf_file.attached? && pdf_file.blob.present?
      self.pdf_file_name = pdf_file.blob.filename.to_s
      self.pdf_file_size = pdf_file.blob.byte_size
    end
  end
end
