require "test_helper"

class Tiktok::VideosControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:keith)
    login_as @user
    stub_features(tiktok_tools: true)
    @credential = @user.credentials.create!(type: "TiktokCredential", external_id: "open_1", oauth_token: "t", oauth_refresh_token: "r", properties: {username: "keithtiktok"})
  end

  test "redirects to connect a TikTok account before uploading" do
    @credential.destroy
    get new_tiktok_video_url
    assert_redirected_to tiktok_connections_url
  end

  test "uploading a video creates it and enqueues the publish job" do
    get new_tiktok_video_url
    assert_response :success

    file = fixture_file_upload("test/fixtures/files/racecar.jpg", "video/mp4")

    assert_difference "TiktokVideo.count", 1 do
      assert_enqueued_with(job: Tiktok::PublishVideoJob) do
        post tiktok_videos_url, params: {tiktok_video: {file: file, caption: "hey", overlay_text: "SALE", privacy_level: "SELF_ONLY"}}
      end
    end

    video = TiktokVideo.last
    assert_redirected_to tiktok_video_url(video)
    assert_equal @user, video.user
    assert_equal @credential, video.tiktok_credential
    assert video.file.attached?
  end

  test "lists videos" do
    create_tiktok_video!(user: @user, tiktok_credential: @credential, status: "posted")
    get tiktok_videos_url
    assert_response :success
  end

  test "shows the video's status" do
    video = create_tiktok_video!(user: @user, tiktok_credential: @credential, status: "posted")
    get tiktok_video_url(video)
    assert_response :success
  end

  test "deletes a video" do
    video = create_tiktok_video!(user: @user, tiktok_credential: @credential, status: "posted")
    assert_difference "TiktokVideo.count", -1 do
      delete tiktok_video_url(video)
    end
    assert_redirected_to tiktok_videos_url
  end
end
