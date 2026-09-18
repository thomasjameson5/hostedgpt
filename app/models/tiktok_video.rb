class TiktokVideo < ApplicationRecord
  PRIVACY_LEVELS = %w[PUBLIC_TO_EVERYONE MUTUAL_FOLLOW_FRIENDS FOLLOWER_OF_CREATOR SELF_ONLY]
  STATUSES = %w[pending processing publishing posted failed]
  OVERLAY_STYLES = Tiktok::VideoOverlay::STYLES.keys
  OVERLAY_POSITIONS = Tiktok::VideoOverlay::POSITIONS.keys

  belongs_to :user
  belongs_to :tiktok_credential, optional: true

  # Posted via Zernio (see app/services/zernio), which fetches the video from a public URL of
  # ours rather than us pushing bytes to it, so this needs a stable, non-expiring URL - the
  # default ActiveStorage service here only issues short-lived signed URLs.
  has_one_attached :file, service: :database_public

  validates :privacy_level, inclusion: {in: PRIVACY_LEVELS}
  validates :status, inclusion: {in: STATUSES}
  validates :overlay_style, inclusion: {in: OVERLAY_STYLES}
  validates :overlay_position, inclusion: {in: OVERLAY_POSITIONS}
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

  # A stable, publicly fetchable URL for the (possibly overlay-processed) video file, handed to
  # Zernio so its servers can download it directly rather than us pushing the bytes over.
  def public_url
    return nil unless file.attached?

    Rails.application.routes.url_helpers.rails_blob_url(file, host: Setting.app_host, protocol: "https")
  end

  private

  def file_present
    errors.add(:file, "must be attached") unless file.attached?
  end
end
