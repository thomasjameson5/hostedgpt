# Drives a TiktokCampaign from "draft" to "launched" against TikTok's Marketing API:
#   1. upload the chosen video into the ad account's creative library (if not already done)
#   2. create the campaign
#   3. create the ad group (audience/budget/schedule)
#   4. create the ad (video + card/identity + instant form + call to action)
#
# Each step is skipped if its TikTok id is already present, so re-running after a failure picks
# up where it left off instead of creating duplicate campaigns/ad groups/ads.
class Tiktok::CampaignLauncher
  Error = Class.new(StandardError)

  def initialize(campaign, marketing_api: nil)
    @campaign = campaign
    @ad_account = campaign.tiktok_ad_account
    @marketing_api = marketing_api || Tiktok::MarketingAPI.new(credential: @ad_account.tiktok_ads_credential)
  end

  def call
    raise Error, "Campaign is not ready to launch" unless campaign.ready_to_launch?

    set_status!(campaign, status: "launching", error_message: nil)
    set_status!(ad_group, status: "launching", error_message: nil)
    set_status!(ad, status: "launching", error_message: nil)

    ensure_ad_video_uploaded!
    ensure_campaign_created!
    ensure_ad_group_created!
    ensure_ad_created!

    set_status!(campaign, status: "launched")
    set_status!(ad_group, status: "launched")
    set_status!(ad, status: "launched")
    true
  rescue => e
    failure_message = e.message
    set_status!(campaign, status: "failed", error_message: failure_message)
    set_status!(ad_group, status: "failed", error_message: failure_message) if ad_group.persisted?
    set_status!(ad, status: "failed", error_message: failure_message) if ad.persisted?
    false
  end

  private

  attr_reader :campaign, :ad_account, :marketing_api

  def ad_group
    campaign.tiktok_ad_group
  end

  def ad
    ad_group.tiktok_ad
  end

  def advertiser_id
    ad_account.advertiser_id
  end

  def ensure_ad_video_uploaded!
    video = ad.tiktok_video
    return if video.tiktok_ad_video_id.present?
    raise Error, "The ad's video isn't attached" unless video.file.attached?

    response = marketing_api.upload_ad_video(
      advertiser_id: advertiser_id,
      filename: video.file.filename.to_s,
      content: video.file.download,
      content_type: video.file.content_type.presence || "video/mp4"
    )
    data = unwrap!(response, context: "uploading the ad video")
    video_id = data.is_a?(Array) ? data.first&.dig("video_id") : data["video_id"]
    raise Error, "TikTok didn't return a video_id for the uploaded video" if video_id.blank?

    set_status!(video, tiktok_ad_video_id: video_id)
  end

  def ensure_campaign_created!
    return if campaign.tiktok_campaign_id.present?

    response = marketing_api.create_campaign(campaign, advertiser_id: advertiser_id)
    data = unwrap!(response, context: "creating the campaign")
    campaign_id = data["campaign_id"]
    raise Error, "TikTok didn't return a campaign_id" if campaign_id.blank?

    set_status!(campaign, tiktok_campaign_id: campaign_id)
  end

  def ensure_ad_group_created!
    return if ad_group.tiktok_adgroup_id.present?

    response = marketing_api.create_adgroup(ad_group, advertiser_id: advertiser_id, campaign_id: campaign.tiktok_campaign_id)
    data = unwrap!(response, context: "creating the ad group")
    adgroup_id = data["adgroup_id"]
    raise Error, "TikTok didn't return an adgroup_id" if adgroup_id.blank?

    set_status!(ad_group, tiktok_adgroup_id: adgroup_id)
  end

  def ensure_ad_created!
    return if ad.tiktok_ad_id.present?

    response = marketing_api.create_ad(ad, advertiser_id: advertiser_id, adgroup_id: ad_group.tiktok_adgroup_id)
    data = unwrap!(response, context: "creating the ad")
    ad_id = Array(data["ad_ids"]).first
    raise Error, "TikTok didn't return an ad_id" if ad_id.blank?

    set_status!(ad, tiktok_ad_id: ad_id)
  end

  # TikTok Marketing API responses are shaped { code:, message:, data: }. code 0 means success.
  def unwrap!(response, context:)
    code = response["code"]
    if code.present? && code.to_i != 0
      raise Error, "TikTok API error while #{context}: #{response["message"] || response}"
    end

    response["data"] || {}
  end

  # We're writing back TikTok's own ids and our sync status here, not user-edited business
  # data, so we bypass validations - a record that's mid-wizard (e.g. missing an instant form)
  # must still be updatable to "failed" with an error message explaining why.
  def set_status!(record, attrs)
    record.update_columns(attrs.merge(updated_at: Time.current))
  end
end
