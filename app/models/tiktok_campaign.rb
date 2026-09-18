class TiktokCampaign < ApplicationRecord
  OBJECTIVE_TYPES = %w[LEAD_GENERATION TRAFFIC REACH VIDEO_VIEWS ENGAGEMENT CONVERSIONS]
  BUDGET_MODES = %w[BUDGET_MODE_DAY BUDGET_MODE_TOTAL BUDGET_MODE_INFINITE]
  STATUSES = %w[draft launching launched failed]

  belongs_to :user
  belongs_to :tiktok_ad_account

  has_one :tiktok_ad_group, dependent: :destroy

  validates :name, presence: true
  validates :objective_type, inclusion: {in: OBJECTIVE_TYPES}
  validates :budget_mode, inclusion: {in: BUDGET_MODES}
  validates :budget, numericality: {greater_than: 0}, unless: -> { budget_mode == "BUDGET_MODE_INFINITE" }
  validates :status, inclusion: {in: STATUSES}

  def draft?
    status == "draft"
  end

  def launched?
    status == "launched"
  end

  def ready_to_launch?
    tiktok_ad_group.present? && tiktok_ad_group.ready_to_launch?
  end
end
