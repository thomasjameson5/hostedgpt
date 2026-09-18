require "tmpdir"
require "securerandom"

# Takes a TiktokVideo (an uploaded file + optional overlay text + caption), burns the overlay
# text into the video if present (re-attaching the result so TiktokVideo#public_url always
# points at what actually gets posted), then publishes it to the connected TikTok account via
# Zernio's POST /v1/posts.
#
# NOTE: the exact JSON shape of a successful /v1/posts response wasn't available when this was
# built (only that a publishNow: true post "comes back with platformPostUrl in the response").
# The parsing below is a best-effort guess at where the post id/URL live - verify against a real
# response once a TikTok account is actually connected in Zernio, and adjust accordingly.
class Zernio::VideoPublisher
  def initialize(video, zernio: nil)
    @video = video
    @zernio = zernio || Zernio::API.new
  end

  def publish!
    video.update!(status: "processing", error_message: nil)

    render_overlay_into_attachment!
    account = find_tiktok_account!

    response = zernio.create_post(
      platforms: [{platform: "tiktok", accountId: account["_id"] || account["id"]}],
      content: video.caption,
      media_urls: [video.public_url],
      publish_now: true
    )

    post = response["existingPost"] || response
    item_id = post["_id"] || post["id"]
    raise "Zernio didn't return a post id" if item_id.blank?

    video.update!(status: "posted", tiktok_item_id: item_id)
    true
  rescue => e
    video.update!(status: "failed", error_message: e.message)
    false
  end

  private

  attr_reader :video, :zernio

  def render_overlay_into_attachment!
    return if video.overlay_text.blank?

    source_path = File.join(Dir.tmpdir, "zernio_source_#{video.id}_#{SecureRandom.hex(4)}#{File.extname(video.file.filename.to_s).presence || ".mp4"}")
    File.binwrite(source_path, video.file.download)

    output_path = File.join(Dir.tmpdir, "zernio_overlay_#{video.id}_#{SecureRandom.hex(4)}.mp4")
    Tiktok::VideoOverlay.new(
      input_path: source_path, output_path: output_path, text: video.overlay_text,
      style: video.overlay_style, position: video.overlay_position
    ).call

    video.file.attach(
      io: File.open(output_path),
      filename: video.file.filename.to_s,
      content_type: video.file.content_type.presence || "video/mp4"
    )
  ensure
    File.delete(source_path) if source_path && File.exist?(source_path)
    File.delete(output_path) if output_path && File.exist?(output_path) && output_path != source_path
  end

  def find_tiktok_account!
    response = zernio.accounts_list(platform: "tiktok")
    accounts = response["accounts"] || response["data"] || response
    account = Array(accounts).first
    raise "No TikTok account connected in Zernio - connect one at zernio.com first" unless account

    account
  end
end
