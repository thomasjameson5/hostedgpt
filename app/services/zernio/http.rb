require "net/http"
require "json"

# Small dependency-free JSON HTTP client for Zernio's REST API (https://zernio.com/api/v1).
# Kept separate from Tiktok::Http (even though the shape is similar) so the two integrations
# stay independent - Zernio is a third-party layer sitting in front of TikTok's own APIs.
class Zernio::Http
  Error = Class.new(StandardError)

  def get(url, headers: {}, params: {})
    uri = build_uri(url, params)
    request(Net::HTTP::Get.new(uri), uri, headers: headers)
  end

  def post_json(url, headers: {}, body: {})
    uri = build_uri(url)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = body.to_json
    request(req, uri, headers: headers)
  end

  # For uploading raw file bytes to a presigned URL (no auth header needed - the URL itself is
  # the credential).
  def put_binary(url, body:, content_type:)
    uri = URI.parse(url)
    req = Net::HTTP::Put.new(uri)
    req["Content-Type"] = content_type
    req.body = body
    request(req, uri, headers: {})
  end

  private

  def build_uri(url, params = {})
    uri = URI.parse(url)
    uri.query = URI.encode_www_form(params) if params.present?
    uri
  end

  def request(req, uri, headers: {})
    headers.each { |k, v| req[k.to_s] = v }

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 120, open_timeout: 30) do |http|
      http.request(req)
    end

    body = response.body.presence
    parsed = body && begin
      JSON.parse(body)
    rescue
      {"raw_body" => body}
    end

    unless response.is_a?(Net::HTTPSuccess)
      message = parsed.is_a?(Hash) ? (parsed["error"] || parsed) : body
      raise Error, "Zernio API request failed (#{response.code}): #{message}"
    end

    parsed || {}
  end
end
