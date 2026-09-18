class TiktokAdGroup < ApplicationRecord
  PLACEMENT_TYPES = %w[PLACEMENT_TYPE_AUTOMATIC PLACEMENT_TYPE_NORMAL]
  BILLING_EVENTS = %w[OCPM CPC CPM]
  BUDGET_MODES = %w[BUDGET_MODE_DAY BUDGET_MODE_TOTAL]
  STATUSES = %w[draft launching launched failed]

  belongs_to :tiktok_campaign

  has_one :tiktok_ad, dependent: :destroy

  validates :name, presence: true
  validates :placement_type, inclusion: {in: PLACEMENT_TYPES}
  validates :billing_event, inclusion: {in: BILLING_EVENTS}
  validates :budget_mode, inclusion: {in: BUDGET_MODES}
  validates :budget, numericality: {greater_than: 0}
  validates :schedule_start_time, presence: true

  def ready_to_launch?
    tiktok_ad.present? && tiktok_ad.ready_to_launch?
  end
end
