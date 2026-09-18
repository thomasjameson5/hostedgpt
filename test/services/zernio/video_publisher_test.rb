require "test_helper"

class Zernio::VideoPublisherTest < ActiveSupport::TestCase
  class FakeZernio
    attr_reader :calls

    def initialize
      @calls = []
    end

    def accounts_list(**args)
      @calls << [:accounts_list, args]
      {"accounts" => [{"_id" => "acc_1", "platform" => "tiktok"}]}
    end

    def create_post(**args)
      @calls << [:create_post, args]
      {"existingPost" => {"_id" => "post_123"}}
    end
  end

  setup do
    @user = users(:keith)
    @video = create_tiktok_video!(user: @user, status: "pending", caption: "hello")
    @fake_zernio = FakeZernio.new
  end

  test "publishes the video through Zernio" do
    result = Zernio::VideoPublisher.new(@video, zernio: @fake_zernio).publish!

    assert result
    assert_equal "posted", @video.reload.status
    assert_equal "post_123", @video.tiktok_item_id
    assert_equal [:accounts_list, :create_post], @fake_zernio.calls.map(&:first)
  end

  test "marks the video failed when no TikTok account is connected in Zernio" do
    def @fake_zernio.accounts_list(**)
      @calls << [:accounts_list, {}]
      {"accounts" => []}
    end

    result = Zernio::VideoPublisher.new(@video, zernio: @fake_zernio).publish!

    refute result
    assert_equal "failed", @video.reload.status
    assert_match "No TikTok account connected", @video.error_message
  end

  test "marks the video failed when Zernio doesn't return a post id" do
    def @fake_zernio.create_post(**args)
      @calls << [:create_post, args]
      {}
    end

    result = Zernio::VideoPublisher.new(@video, zernio: @fake_zernio).publish!

    refute result
    assert_equal "failed", @video.reload.status
    assert_match "didn't return a post id", @video.error_message
  end

  test "marks the video failed when Zernio raises" do
    def @fake_zernio.create_post(**args)
      @calls << [:create_post, args]
      raise Zernio::Http::Error, "network blew up"
    end

    result = Zernio::VideoPublisher.new(@video, zernio: @fake_zernio).publish!

    refute result
    assert_equal "failed", @video.reload.status
    assert_match "network blew up", @video.error_message
  end
end
