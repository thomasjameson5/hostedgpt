class TiktokVideo < ApplicationRecord
  PRIVACY_LEVELS = %w[PUBLIC_TO_EVERYONE MUTUAL_FOLLOW_FRIENDS FOLLOWER_OF_CREATOR SELF_ONLY]
  STATUSES = %w[pending processing publishing posted failed]

  belongs_to :user
  belongs_to :tiktok_credential

  has_one_attached :file

  validates :privacy_level, inclusion: {in: PRIVACY_LEVELS}
  validates :status, inclusion: {in: STATUSES}
  validate :file_present

  def posted?
    status == "posted"
  end

  def failed?
    status == "failed"
  end

  def ready_for_ads?
    tiktok_ad_video_id.present?
  end

  private

  def file_present
    errors.add(:file, "must be attached") unless file.attached?
  end
end
