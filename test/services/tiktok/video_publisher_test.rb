require "test_helper"

class Tiktok::VideoPublisherTest < ActiveSupport::TestCase
  class FakeContentAPI
    attr_reader :calls

    def initialize
      @calls = []
    end

    def init_video_upload(**args)
      @calls << [:init_video_upload, args]
      {"data" => {"publish_id" => "pub_123", "upload_url" => "https://example.com/upload"}}
    end

    def upload_video_chunk(**args)
      @calls << [:upload_video_chunk, args]
      {"data" => {}}
    end

    def fetch_publish_status(publish_id:)
      @calls << [:fetch_publish_status, publish_id]
      @status_response || {"data" => {"status" => "PROCESSING_DOWNLOAD"}}
    end

    def respond_with_status(response)
      @status_response = response
    end
  end

  setup do
    @user = users(:keith)
    credential = @user.credentials.create!(type: "TiktokCredential", external_id: "open123", oauth_token: "t", oauth_refresh_token: "r")
    @video = create_tiktok_video!(user: @user, tiktok_credential: credential, status: "pending", caption: "hello")
    @fake_api = FakeContentAPI.new
  end

  test "uploads the video and moves it to publishing" do
    result = Tiktok::VideoPublisher.new(@video, content_api: @fake_api).publish!

    assert result
    assert_equal "publishing", @video.reload.status
    assert_equal "pub_123", @video.tiktok_publish_id
    assert_includes @fake_api.calls.map(&:first), :init_video_upload
    assert_includes @fake_api.calls.map(&:first), :upload_video_chunk
  end

  test "marks the video failed when the API errors" do
    def @fake_api.init_video_upload(**)
      raise "network blew up"
    end

    result = Tiktok::VideoPublisher.new(@video, content_api: @fake_api).publish!

    refute result
    assert_equal "failed", @video.reload.status
    assert_match "network blew up", @video.error_message
  end

  test "check_status! marks the video posted once TikTok finishes processing" do
    @video.update!(status: "publishing", tiktok_publish_id: "pub_123")
    @fake_api.respond_with_status("data" => {"status" => "PUBLISH_COMPLETE", "publicly_available_post_id" => ["item_1"]})

    done = Tiktok::VideoPublisher.new(@video, content_api: @fake_api).check_status!

    assert done
    assert_equal "posted", @video.reload.status
    assert_equal "item_1", @video.tiktok_item_id
  end

  test "check_status! returns false while TikTok is still processing" do
    @video.update!(status: "publishing", tiktok_publish_id: "pub_123")

    done = Tiktok::VideoPublisher.new(@video, content_api: @fake_api).check_status!

    refute done
    assert_equal "publishing", @video.reload.status
  end
end
