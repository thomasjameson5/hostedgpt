# Wraps TikTok's Login Kit (OAuth) and Content Posting API - the API used to connect a
# creator/business TikTok account and post a video to it directly.
#
# Docs: https://developers.tiktok.com/docs/en/content-posting-api-get-started
#       https://developers.tiktok.com/docs/en/content-posting-api-reference-direct-post
#
# NOTE: while this app doesn't yet have TikTok API access approved, the endpoint paths and
# request/response shapes below reflect TikTok's documented v2 Content Posting API. Re-verify
# against the live docs once your developer app is approved, TikTok's API surface does change.
class Tiktok::ContentAPI
  AUTHORIZE_URL = "https://www.tiktok.com/v2/auth/authorize/"
  TOKEN_URL = "https://open.tiktokapis.com/v2/oauth/token/"
  API_BASE = "https://open.tiktokapis.com/v2"
  SCOPES = %w[user.info.basic video.upload video.publish].freeze

  class << self
    def authorize_url(redirect_uri:, state:)
      params = {
        client_key: Setting.tiktok_client_key,
        scope: SCOPES.join(","),
        response_type: "code",
        redirect_uri: redirect_uri,
        state: state
      }
      "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
    end

    def exchange_code(code:, redirect_uri:, http: Tiktok::Http.new)
      http.post_form(TOKEN_URL, body: {
        client_key: Setting.tiktok_client_key,
        client_secret: Setting.tiktok_client_secret,
        code: code,
        grant_type: "authorization_code",
        redirect_uri: redirect_uri
      })
    end

    def refresh_token(refresh_token:, http: Tiktok::Http.new)
      http.post_form(TOKEN_URL, body: {
        client_key: Setting.tiktok_client_key,
        client_secret: Setting.tiktok_client_secret,
        grant_type: "refresh_token",
        refresh_token: refresh_token
      })
    end
  end

  attr_reader :credential, :http

  def initialize(credential:, http: Tiktok::Http.new)
    @credential = credential
    @http = http
  end

  def user_info
    http.get("#{API_BASE}/user/info/", headers: auth_headers, params: {fields: "open_id,display_name,avatar_url,username"})
  end

  # Step 1 of Direct Post: tell TikTok we're about to upload a video of a given size, in chunks.
  def init_video_upload(video_size:, chunk_size:, total_chunk_count:, privacy_level:, caption: nil)
    body = {
      post_info: {
        title: caption.presence,
        privacy_level: privacy_level,
        disable_duet: false,
        disable_comment: false,
        disable_stitch: false
      }.compact,
      source_info: {
        source: "FILE_UPLOAD",
        video_size: video_size,
        chunk_size: chunk_size,
        total_chunk_count: total_chunk_count
      }
    }

    http.post_json("#{API_BASE}/post/publish/video/init/", headers: auth_headers, body: body)
  end

  # Step 2: PUT the (possibly chunked) video bytes to the upload_url returned by init_video_upload.
  def upload_video_chunk(upload_url:, chunk:, range_start:, range_end:, total_size:)
    headers = {
      "Content-Range" => "bytes #{range_start}-#{range_end}/#{total_size}",
      "Content-Length" => chunk.bytesize.to_s
    }
    http.put_binary(upload_url, headers: headers, body: chunk)
  end

  # Step 3: poll until status flips from PROCESSING_UPLOAD/PROCESSING_DOWNLOAD to PUBLISH_COMPLETE (or FAILED).
  def fetch_publish_status(publish_id:)
    http.post_json("#{API_BASE}/post/publish/status/fetch/", headers: auth_headers, body: {publish_id: publish_id})
  end

  private

  def auth_headers
    {"Authorization" => "Bearer #{credential.oauth_token}", "Content-Type" => "application/json; charset=UTF-8"}
  end
end
