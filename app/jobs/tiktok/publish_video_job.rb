class Tiktok::PublishVideoJob < ApplicationJob
  queue_as :default

  # Zernio's posts_create with publish_now: true is synchronous - it responds with success or
  # failure in the same request, so there's no separate status-polling job needed here (unlike
  # the old direct TikTok Content Posting API flow, which was async).
  def perform(video_id)
    video = TiktokVideo.find(video_id)
    Zernio::VideoPublisher.new(video).publish!
  end
end
