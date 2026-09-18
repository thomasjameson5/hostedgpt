require "test_helper"
require "tmpdir"
require "fileutils"

class Tiktok::VideoOverlayTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @input_path = File.join(@dir, "source.mp4")
    system("ffmpeg", "-y", "-f", "lavfi", "-i", "color=c=blue:s=320x240:d=1", "-pix_fmt", "yuv420p", @input_path,
      out: File::NULL, err: File::NULL, exception: true)
  end

  teardown do
    FileUtils.remove_entry(@dir)
  end

  test "returns the input path unchanged when there's no text" do
    output_path = File.join(@dir, "out.mp4")
    result = Tiktok::VideoOverlay.new(input_path: @input_path, output_path: output_path, text: "").call

    assert_equal @input_path, result
    refute File.exist?(output_path)
  end

  test "burns text onto the video for every style and position" do
    Tiktok::VideoOverlay::STYLES.each_key do |style|
      Tiktok::VideoOverlay::POSITIONS.each_key do |position|
        output_path = File.join(@dir, "#{style}_#{position}.mp4")
        result = Tiktok::VideoOverlay.new(input_path: @input_path, output_path: output_path, text: "SALE 50% off!", style: style, position: position).call

        assert_equal output_path, result
        assert File.exist?(output_path)
        assert File.size(output_path) > 0
      end
    end
  end

  test "falls back to the classic style and bottom position for an unknown value" do
    output_path = File.join(@dir, "out.mp4")
    overlay = Tiktok::VideoOverlay.new(input_path: @input_path, output_path: output_path, text: "hi", style: "nonexistent", position: "nonexistent")

    assert overlay.call
    assert File.exist?(output_path)
  end

  test "raises with the ffmpeg error output when it fails" do
    output_path = File.join(@dir, "out.mp4")
    overlay = Tiktok::VideoOverlay.new(input_path: File.join(@dir, "missing.mp4"), output_path: output_path, text: "hi")

    error = assert_raises(Tiktok::VideoOverlay::Error) { overlay.call }
    assert_match "ffmpeg failed", error.message
  end
end
