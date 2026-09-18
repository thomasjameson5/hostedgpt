require "open3"

# Burns a line of text onto a video using ffmpeg's drawtext filter. TikTok's APIs only let you
# set a caption (the text below the video), not draw pixels onto the video itself, so if the
# user wants text visually on the video we have to render it in ourselves before uploading.
#
# STYLES mirrors a few of the text style presets TikTok's own in-app editor offers (classic
# outlined text, a solid background box, the yellow "highlighter" look, and a neon-bordered
# variant); POSITIONS mirrors dragging that text to the top, middle, or bottom of the screen.
#
# Requires the `ffmpeg` binary (with drawtext/freetype support) and the DejaVu fonts installed
# on the host - see Dockerfile (`ttf-dejavu` on Alpine, `fonts-dejavu-core` on Debian/Ubuntu).
class Tiktok::VideoOverlay
  Error = Class.new(StandardError)

  FONT_DIR = "/usr/share/fonts/truetype/dejavu"
  REGULAR_FONT = "#{FONT_DIR}/DejaVuSans.ttf"
  BOLD_FONT = "#{FONT_DIR}/DejaVuSans-Bold.ttf"

  STYLES = {
    "classic" => {fontfile: REGULAR_FONT, fontcolor: "white", bordercolor: "black", borderw: 3},
    "bold" => {fontfile: BOLD_FONT, fontcolor: "white", box: true, boxcolor: "black@0.85", boxborderw: 20},
    "highlight" => {fontfile: BOLD_FONT, fontcolor: "black", box: true, boxcolor: "yellow@0.95", boxborderw: 16},
    "neon" => {fontfile: BOLD_FONT, fontcolor: "white", bordercolor: "#FF2E88", borderw: 6}
  }.freeze

  POSITIONS = {
    "top" => "y=80",
    "middle" => "y=(h-text_h)/2",
    "bottom" => "y=h-text_h-80"
  }.freeze

  def initialize(input_path:, output_path:, text:, style: "classic", position: "bottom")
    @input_path = input_path
    @output_path = output_path
    @text = text
    @style = STYLES.key?(style) ? style : "classic"
    @position = POSITIONS.key?(position) ? position : "bottom"
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
    # expansion=none turns off drawtext's own %{...} text-expansion syntax (timestamps, frame
    # numbers, etc.) - we only ever burn in a static literal string, and with it off a literal
    # "%" in the text (e.g. "50% off") needs no special escaping at all.
    options = {text: "'#{escaped_text}'", fontsize: 64, x: "(w-text_w)/2", expansion: "none"}.merge(STYLES.fetch(@style))
    options[:box] = 1 if options.delete(:box)

    "drawtext=" + options.map { |key, value| "#{key}=#{value}" }.join(":") + ":#{POSITIONS.fetch(@position)}"
  end

  def escaped_text
    @text.to_s
      .gsub("\\", "\\\\\\\\")
      .gsub(":", "\\:")
      .tr("'", "’") # ffmpeg's drawtext quoting can't handle an escaped single quote inside a single-quoted text arg, so swap in a visually identical right single quote
  end
end
