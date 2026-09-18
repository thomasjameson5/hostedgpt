class TiktokAd < ApplicationRecord
  CALL_TO_ACTIONS = %w[LEARN_MORE SIGN_UP APPLY_NOW GET_QUOTE SUBSCRIBE CONTACT_US DOWNLOAD]
  STATUSES = %w[draft launching launched failed]

  belongs_to :tiktok_ad_group
  belongs_to :tiktok_video, optional: true

  validates :name, presence: true
  validates :call_to_action, inclusion: {in: CALL_TO_ACTIONS}
  validates :identity_id, :identity_type, presence: true
  validates :instant_form_id, presence: true, if: -> { tiktok_ad_group&.tiktok_campaign&.objective_type == "LEAD_GENERATION" }

  def ready_to_launch?
    tiktok_video.present? && tiktok_video.file.attached? &&
      identity_id.present? && identity_type.present? &&
      (instant_form_id.present? || tiktok_ad_group.tiktok_campaign.objective_type != "LEAD_GENERATION")
  end
end
