require "net/http"
require "json"
require "securerandom"

# Small dependency-free JSON/multipart HTTP client used by the Tiktok:: service objects.
# It's intentionally minimal (stdlib Net::HTTP only) and easy to swap out in tests via
# dependency injection - every Tiktok:: API wrapper accepts `http:` in its initializer.
class Tiktok::Http
  Error = Class.new(StandardError)

  def get(url, headers: {}, params: {})
    uri = build_uri(url, params)
    request(Net::HTTP::Get.new(uri), uri)
  end

  def post_json(url, headers: {}, body: {})
    uri = build_uri(url)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = body.to_json
    request(req, uri, headers: headers)
  end

  def post_form(url, headers: {}, body: {})
    uri = build_uri(url)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/x-www-form-urlencoded"
    req.body = URI.encode_www_form(body)
    request(req, uri, headers: headers)
  end

  def put_binary(url, body:, headers: {}, content_type: "video/mp4")
    uri = URI.parse(url)
    req = Net::HTTP::Put.new(uri)
    req["Content-Type"] = content_type
    req.body = body
    request(req, uri, headers: headers, raw: true)
  end

  # files: { field_name => { filename:, content_type:, content: } }
  def post_multipart(url, headers: {}, fields: {}, files: {})
    uri = build_uri(url)
    boundary = SecureRandom.hex(16)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    req.body = build_multipart_body(boundary, fields, files)
    request(req, uri, headers: headers)
  end

  private

  def build_uri(url, params = {})
    uri = URI.parse(url)
    uri.query = URI.encode_www_form(params) if params.present?
    uri
  end

  def request(req, uri, headers: {}, raw: false)
    headers.each { |k, v| req[k.to_s] = v }

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 120, open_timeout: 30) do |http|
      http.request(req)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "TikTok API request failed (#{response.code}): #{response.body}"
    end

    return response if raw

    return {} if response.body.blank?

    JSON.parse(response.body)
  rescue JSON::ParserError
    {"raw_body" => response&.body}
  end

  def build_multipart_body(boundary, fields, files)
    body = +""
    fields.each do |name, value|
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n"
      body << "#{value}\r\n"
    end
    files.each do |name, file|
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{file[:filename]}\"\r\n"
      body << "Content-Type: #{file[:content_type]}\r\n\r\n"
      body << file[:content].b
      body << "\r\n"
    end
    body << "--#{boundary}--\r\n"
    body
  end
end
