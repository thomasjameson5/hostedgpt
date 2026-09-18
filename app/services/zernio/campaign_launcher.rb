# Launches a TiktokCampaign (+ its TiktokAdGroup + TiktokAd) through Zernio's
# POST /v1/ads/create. Unlike the old direct-TikTok-API launcher, this is a SINGLE call: Zernio's
# own docs list the two-step "create an empty campaign, then attach an ad set/ad to it" shape
# (`existingCampaignId`) as supported only on Meta, Google Ads, and LinkedIn - not TikTok - so
# for TikTok everything is created atomically here. There's nothing to resume if it partially
# fails; a failed launch is retried from scratch (Idempotency-Key makes a retry with the same
# key-and-body safe rather than creating a duplicate campaign).
class Zernio::CampaignLauncher
  Error = Class.new(StandardError)

  GOALS = {
    "LEAD_GENERATION" => "lead_generation",
    "TRAFFIC" => "traffic",
    "REACH" => "awareness",
    "VIDEO_VIEWS" => "video_views",
    "ENGAGEMENT" => "engagement",
    "CONVERSIONS" => "conversions"
  }.freeze

  BUDGET_TYPES = {
    "BUDGET_MODE_DAY" => "daily",
    "BUDGET_MODE_TOTAL" => "lifetime"
  }.freeze

  def initialize(campaign, zernio: nil)
    @campaign = campaign
    @zernio = zernio || Zernio::API.new
  end

  def call
    raise Error, "Campaign is not ready to launch" unless campaign.ready_to_launch?

    set_status!(campaign, status: "launching", error_message: nil)
    set_status!(ad_group, status: "launching", error_message: nil)
    set_status!(ad, status: "launching", error_message: nil)

    account = find_tiktok_ads_account!
    response = zernio.create_ad(
      account_id: account["_id"] || account["id"],
      ad_account_id: account["adAccountId"] || account["platformAdAccountId"] || account["_id"] || account["id"],
      name: campaign.name,
      goal: goal,
      video_url: ad.tiktok_video.public_url,
      budget_amount: ad_group.budget,
      budget_type: budget_type,
      body: ad.ad_text,
      call_to_action: ad.call_to_action,
      link_url: ad.landing_page_url.presence,
      lead_gen_form_id: ad.instant_form_id.presence,
      countries: ad_group.location_ids.presence,
      age_min: ad_group.age_min,
      age_max: ad_group.age_max,
      gender: gender,
      languages: ad_group.languages.presence,
      status: "ACTIVE",
      idempotency_key: idempotency_key
    )

    data = response["ad"] || response
    ad_id = data["platformAdId"] || data["_id"] || data["id"]
    raise Error, "Zernio didn't return an ad id" if ad_id.blank?

    set_status!(campaign, status: "launched", tiktok_campaign_id: data["platformCampaignId"])
    set_status!(ad_group, status: "launched", tiktok_adgroup_id: data["platformAdSetId"])
    set_status!(ad, status: "launched", tiktok_ad_id: ad_id)
    true
  rescue => e
    failure_message = e.message
    set_status!(campaign, status: "failed", error_message: failure_message)
    set_status!(ad_group, status: "failed", error_message: failure_message) if ad_group.persisted?
    set_status!(ad, status: "failed", error_message: failure_message) if ad.persisted?
    false
  end

  private

  attr_reader :campaign, :zernio

  def ad_group
    campaign.tiktok_ad_group
  end

  def ad
    ad_group.tiktok_ad
  end

  def goal
    GOALS.fetch(campaign.objective_type) { raise Error, "Zernio has no TikTok goal mapping for objective #{campaign.objective_type}" }
  end

  def budget_type
    BUDGET_TYPES.fetch(ad_group.budget_mode) { raise Error, "Zernio has no budget type mapping for #{ad_group.budget_mode}" }
  end

  def gender
    genders = Array(ad_group.genders)
    return "male" if genders == ["GENDER_MALE"]
    return "female" if genders == ["GENDER_FEMALE"]

    nil
  end

  # Reused across a retry of the same campaign so a failed-then-retried launch can't create two
  # ads on TikTok; scoped to this campaign's id, which is stable across retries.
  def idempotency_key
    "hostedgpt-tiktok-campaign-#{campaign.id}"
  end

  # Zernio's docs reference a distinct "tiktokads" SocialAccount type (separate from the
  # "tiktok" posting account) - e.g. "Required on the FIRST CUSTOMIZED_USER ad on a tiktokads
  # SocialAccount". Falls back to a plain "tiktok" account if no tiktokads-specific one is
  # found, in case the exact platform string differs from this guess.
  #
  # NOTE: the exact field names on an account returned by GET /v1/accounts (account id,
  # platform ad account id) aren't confirmed against Zernio's docs - verify against a real
  # response once a TikTok Ads account is connected.
  def find_tiktok_ads_account!
    response = zernio.accounts_list(platform: "tiktokads")
    accounts = response["accounts"] || response["data"] || response
    account = Array(accounts).first
    account ||= begin
      response = zernio.accounts_list(platform: "tiktok")
      Array(response["accounts"] || response["data"] || response).first
    end
    raise Error, "No TikTok Ads account connected in Zernio - connect one at zernio.com first" unless account

    account
  end

  def set_status!(record, attrs)
    record.update_columns(attrs.compact.merge(updated_at: Time.current))
  end
end
