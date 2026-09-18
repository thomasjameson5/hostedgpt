require "tmpdir"

# Takes a TiktokVideo (an uploaded file + optional overlay text + caption), burns the overlay
# text into the video if present, then posts it to the connected TikTok account via the Content
# Posting API. Publishing on TikTok's side is async, so #publish! only kicks it off - poll with
# #check_status! (see Tiktok::CheckVideoStatusJob) until the video's status is "posted"/"failed".
class Tiktok::VideoPublisher
  # TikTok chunk size must be a multiple of the video size unless the last chunk, min 5MB unless
  # the whole file is smaller than that. We keep it simple: upload in a single chunk for files
  # under 60MB (typical short-form TikTok video), otherwise split into 10MB chunks.
  SINGLE_CHUNK_LIMIT = 60 * 1024 * 1024
  CHUNK_SIZE = 10 * 1024 * 1024

  def initialize(video, content_api: nil)
    @video = video
    @content_api = content_api || Tiktok::ContentAPI.new(credential: video.tiktok_credential)
  end

  def publish!
    video.update!(status: "processing", error_message: nil)

    rendered_path = render_overlay
    begin
      publish_rendered_file(rendered_path)
    ensure
      File.delete(rendered_path) if rendered_path && File.exist?(rendered_path) && rendered_path != downloaded_source_path
      File.delete(downloaded_source_path) if downloaded_source_path && File.exist?(downloaded_source_path)
    end

    video.update!(status: "publishing")
    true
  rescue => e
    video.update!(status: "failed", error_message: e.message)
    false
  end

  def check_status!
    return true if video.status != "publishing" || video.tiktok_publish_id.blank?

    response = content_api.fetch_publish_status(publish_id: video.tiktok_publish_id)
    status = response.dig("data", "status")

    case status
    when "PUBLISH_COMPLETE"
      item_id = Array(response.dig("data", "publicly_available_post_id")).first
      video.update!(status: "posted", tiktok_item_id: item_id)
      true
    when "FAILED"
      video.update!(status: "failed", error_message: response.dig("data", "fail_reason") || "TikTok reported a publish failure")
      true
    else
      false # still processing, caller should check again later
    end
  end

  private

  attr_reader :video, :content_api

  def render_overlay
    download_source
    return downloaded_source_path if video.overlay_text.blank?

    output_path = File.join(Dir.tmpdir, "tiktok_overlay_#{video.id}_#{SecureRandom.hex(4)}.mp4")
    Tiktok::VideoOverlay.new(input_path: downloaded_source_path, output_path: output_path, text: video.overlay_text).call
  end

  def download_source
    return downloaded_source_path if @downloaded

    @downloaded_source_path = File.join(Dir.tmpdir, "tiktok_source_#{video.id}_#{SecureRandom.hex(4)}#{File.extname(video.file.filename.to_s).presence || ".mp4"}")
    File.binwrite(@downloaded_source_path, video.file.download)
    @downloaded = true
    @downloaded_source_path
  end

  attr_reader :downloaded_source_path

  def publish_rendered_file(path)
    bytes = File.read(path, mode: "rb")
    total_size = bytes.bytesize
    chunk_size = (total_size <= SINGLE_CHUNK_LIMIT) ? total_size : CHUNK_SIZE
    total_chunk_count = (total_size.to_f / chunk_size).ceil

    init_response = content_api.init_video_upload(
      video_size: total_size,
      chunk_size: chunk_size,
      total_chunk_count: total_chunk_count,
      privacy_level: video.privacy_level,
      caption: video.caption
    )

    publish_id = init_response.dig("data", "publish_id")
    upload_url = init_response.dig("data", "upload_url")
    raise "TikTok didn't return a publish_id/upload_url: #{init_response}" if publish_id.blank? || upload_url.blank?

    offset = 0
    while offset < total_size
      chunk = bytes.byteslice(offset, chunk_size)
      range_end = offset + chunk.bytesize - 1
      content_api.upload_video_chunk(upload_url: upload_url, chunk: chunk, range_start: offset, range_end: range_end, total_size: total_size)
      offset += chunk.bytesize
    end

    video.update!(tiktok_publish_id: publish_id)
  end
end
