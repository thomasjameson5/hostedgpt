require "digest"

# Wraps TikTok's Marketing API (aka "TikTok for Business" / Business API) - used to build and
# launch ad campaigns: campaign -> ad group -> ad, plus picking an "Identity" (the account/page
# the ad appears to come from - shown as a picker of account cards in TikTok Ads Manager, hence
# "card" in this app's UI) and an Instant Form for Lead Generation ads.
#
# Docs: https://business-api.tiktok.com/portal/docs
#
# NOTE: TikTok's Marketing API requires your developer app to be approved for these scopes
# before any of this works, and this codebase was built without live API access (outbound
# access to TikTok's domains was blocked in the sandbox this was built in). The endpoint paths,
# parameter names and enum values below reflect the documented v1.3 Marketing API shape, but you
# should diff them against the current docs at business-api.tiktok.com/portal/docs before
# launching real campaigns - TikTok revises field names across API versions.
class Tiktok::MarketingAPI
  AUTHORIZE_URL = "https://business-api.tiktok.com/portal/auth"
  API_BASE = "https://business-api.tiktok.com/open_api/v1.3"

  class << self
    def authorize_url(redirect_uri:, state:)
      params = {
        app_id: Setting.tiktok_marketing_app_id,
        state: state,
        redirect_uri: redirect_uri
      }
      "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
    end

    def exchange_code(auth_code:, http: Tiktok::Http.new)
      http.post_json("#{API_BASE}/oauth2/access_token/", body: {
        app_id: Setting.tiktok_marketing_app_id,
        secret: Setting.tiktok_marketing_app_secret,
        auth_code: auth_code
      })
    end
  end

  attr_reader :credential, :http

  def initialize(credential:, http: Tiktok::Http.new)
    @credential = credential
    @http = http
  end

  # Which advertiser (ad) accounts this token has access to.
  def advertisers
    http.get("#{API_BASE}/oauth2/advertiser/get/", headers: auth_headers, params: {
      app_id: Setting.tiktok_marketing_app_id,
      secret: Setting.tiktok_marketing_app_secret
    })
  end

  # The "cards" - identities this advertiser can run ads as.
  def identities(advertiser_id:)
    http.get("#{API_BASE}/identity/get/", headers: auth_headers, params: {
      advertiser_id: advertiser_id
    })
  end

  # Instant Forms already built in TikTok Ads Manager for this advertiser, available to attach
  # to a Lead Generation ad.
  def instant_forms(advertiser_id:)
    http.get("#{API_BASE}/page/lead_gen_form/get/", headers: auth_headers, params: {
      advertiser_id: advertiser_id
    })
  end

  # Uploads a video into the advertiser's creative asset library so it can be referenced by
  # video_id when creating an ad. This is a separate upload from posting a video organically via
  # the Content Posting API.
  def upload_ad_video(advertiser_id:, filename:, content:, content_type: "video/mp4")
    http.post_multipart("#{API_BASE}/file/video/ad/upload/",
      headers: auth_headers,
      fields: {
        advertiser_id: advertiser_id,
        upload_type: "UPLOAD_BY_FILE",
        video_signature: Digest::MD5.hexdigest(content)
      },
      files: {
        video_file: {filename: filename, content_type: content_type, content: content}
      })
  end

  def create_campaign(campaign, advertiser_id:)
    http.post_json("#{API_BASE}/campaign/create/", headers: auth_headers, body: {
      advertiser_id: advertiser_id,
      campaign_name: campaign.name,
      objective_type: campaign.objective_type,
      budget_mode: campaign.budget_mode,
      budget: (campaign.budget_mode == "BUDGET_MODE_INFINITE") ? nil : campaign.budget
    }.compact)
  end

  def create_adgroup(ad_group, advertiser_id:, campaign_id:)
    http.post_json("#{API_BASE}/adgroup/create/", headers: auth_headers, body: {
      advertiser_id: advertiser_id,
      campaign_id: campaign_id,
      adgroup_name: ad_group.name,
      placement_type: ad_group.placement_type,
      optimization_goal: ad_group.optimization_goal,
      billing_event: ad_group.billing_event,
      bid_price: ad_group.bid_price,
      budget_mode: ad_group.budget_mode,
      budget: ad_group.budget,
      schedule_type: ad_group.schedule_end_time.present? ? "SCHEDULE_START_END" : "SCHEDULE_FROM_NOW",
      schedule_start_time: ad_group.schedule_start_time&.iso8601,
      schedule_end_time: ad_group.schedule_end_time&.iso8601,
      location_ids: ad_group.location_ids,
      age_groups: ad_group.age_groups,
      gender: ad_group.genders,
      languages: ad_group.languages
    }.compact)
  end

  def create_ad(ad, advertiser_id:, adgroup_id:)
    creative = {
      ad_name: ad.name,
      ad_text: ad.ad_text,
      call_to_action: ad.call_to_action,
      identity_type: ad.identity_type,
      identity_id: ad.identity_id,
      video_id: ad.tiktok_video.tiktok_ad_video_id,
      instant_form_id: ad.instant_form_id.presence
    }.compact

    http.post_json("#{API_BASE}/ad/create/", headers: auth_headers, body: {
      advertiser_id: advertiser_id,
      adgroup_id: adgroup_id,
      creatives: [creative]
    })
  end

  private

  def auth_headers
    {"Access-Token" => credential.oauth_token}
  end
end
