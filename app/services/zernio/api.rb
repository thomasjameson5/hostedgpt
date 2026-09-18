# Wraps Zernio's REST API (https://docs.zernio.com) - a third-party layer that already holds
# its own registered TikTok app, so posting a video and (eventually) building ad campaigns
# doesn't require registering a TikTok developer app of our own. The user connects their TikTok
# account to Zernio directly on zernio.com; we only need a single Zernio API key configured for
# this whole app (Setting.zernio_api_key), not a per-user OAuth flow.
class Zernio::API
  API_BASE = "https://zernio.com/api/v1"

  def initialize(api_key: Setting.zernio_api_key, http: Zernio::Http.new)
    @api_key = api_key
    @http = http
  end

  # Confirmed by Zernio's own docs ("An account ID may have been disconnected and removed.
  # Read GET /v1/accounts for current account IDs.").
  def accounts_list(platform: nil)
    http.get("#{API_BASE}/accounts", headers: auth_headers, params: {platform: platform}.compact)
  end

  # NOTE: the exact request/response shape of POST /v1/media/presign hasn't been confirmed
  # against Zernio's own reference docs - it's only referenced in passing on the "Create post"
  # page ("Upload files with POST /v1/media/presign first"). This follows the common presigned
  # upload convention (send a filename/content type, get back an uploadUrl to PUT the file
  # bytes to and a public fileUrl to reference afterward). Verify the real field names against
  # Zernio's docs for this endpoint before relying on it.
  def media_presign(filename:, content_type:)
    http.post_json("#{API_BASE}/media/presign", headers: auth_headers, body: {
      filename: filename,
      contentType: content_type
    })
  end

  def upload_media(upload_url:, content:, content_type:)
    http.put_binary(upload_url, body: content, content_type: content_type)
  end

  # platforms: array of { platform:, accountId: } (see Zernio's createPost reference).
  def create_post(platforms:, content: nil, media_urls: [], publish_now: false, scheduled_for: nil, is_draft: false, title: nil, request_id: nil)
    body = {
      content: content,
      platforms: platforms,
      mediaItems: media_urls.map { |url| {url: url} }.presence,
      publishNow: publish_now,
      scheduledFor: scheduled_for,
      isDraft: is_draft,
      title: title
    }.compact

    headers = auth_headers
    headers["x-request-id"] = request_id if request_id.present?

    http.post_json("#{API_BASE}/posts", headers: headers, body: body)
  end

  # Creates the campaign + ad set + ad together in one call ("the legacy single-creative
  # shape" in Zernio's terms). Zernio's own field docs list `existingCampaignId` - the shape
  # that would let us create an empty campaign shell first and attach the ad set/ad to it
  # later - as supported only on Meta, Google Ads, and LinkedIn, NOT TikTok. So for TikTok
  # everything has to be created atomically in this one call; there's no two-step path.
  #
  # TikTok-specific quirks baked into this method (per Zernio's "Create standalone ad" reference):
  #   - `imageUrl` carries the VIDEO url for TikTok, not an image - the field is misnamed for
  #     cross-platform consistency with platforms where it really is an image.
  #   - `headline` is ignored on TikTok - omit it.
  #   - `linkUrl` is not required when goal is lead_generation (the ad opens the Instant Form
  #     instead of a destination URL).
  #   - `identityType` is TikTok-only: "TT_USER" runs the ad as the connected TikTok posting
  #     account (the "card"); "CUSTOMIZED_USER" needs a synthetic `brandIdentity` we don't
  #     collect yet, so we only support TT_USER for now.
  def create_ad(account_id:, ad_account_id:, name:, goal:, video_url:, budget_amount:, budget_type:,
    body: nil, call_to_action: nil, link_url: nil, lead_gen_form_id: nil,
    identity_type: "TT_USER", countries: nil, age_min: nil, age_max: nil, gender: nil,
    languages: nil, status: nil, idempotency_key: nil)
    request_body = {
      accountId: account_id,
      adAccountId: ad_account_id,
      name: name,
      goal: goal,
      imageUrl: video_url,
      budgetAmount: budget_amount,
      budgetType: budget_type,
      body: body,
      callToAction: call_to_action,
      linkUrl: link_url,
      leadGenFormId: lead_gen_form_id,
      identityType: identity_type,
      countries: countries,
      ageMin: age_min,
      ageMax: age_max,
      gender: gender,
      languages: languages,
      status: status
    }.compact

    headers = auth_headers
    headers["Idempotency-Key"] = idempotency_key if idempotency_key.present?

    http.post_json("#{API_BASE}/ads/create", headers: headers, body: request_body)
  end

  private

  attr_reader :http, :api_key

  def auth_headers
    {"Authorization" => "Bearer #{api_key}"}
  end
end
