require "open3"

# Burns a line of text onto a video using ffmpeg's drawtext filter. TikTok's APIs only let you
# set a caption (the text below the video), not draw pixels onto the video itself, so if the
# user wants text visually on the video we have to render it in ourselves before uploading.
#
# Requires the `ffmpeg` binary to be installed on the host (see Dockerfile).
class Tiktok::VideoOverlay
  Error = Class.new(StandardError)

  def initialize(input_path:, output_path:, text:)
    @input_path = input_path
    @output_path = output_path
    @text = text
  end

  def call
    return @input_path if @text.blank?

    command = [
      "ffmpeg", "-y",
      "-i", @input_path,
      "-vf", drawtext_filter,
      "-codec:a", "copy",
      @output_path
    ]

    stdout, stderr, status = Open3.capture3(*command)
    raise Error, "ffmpeg failed: #{stderr.presence || stdout}" unless status.success?

    @output_path
  end

  private

  def drawtext_filter
    escaped = @text.to_s
      .gsub("\\", "\\\\\\\\")
      .gsub(":", "\\:")
      .tr("'", "’") # ffmpeg's drawtext quoting can't handle an escaped single quote inside a single-quoted text arg, so swap in a visually identical right single quote
      .gsub("%", "\\%")

    "drawtext=text='#{escaped}':fontcolor=white:fontsize=64:box=1:boxcolor=black@0.5:boxborderw=16:x=(w-text_w)/2:y=h-th-80"
  end
end
