class Tiktok::CheckVideoStatusJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 30 # ~5 minutes at 10s intervals

  def perform(video_id, attempt = 1)
    video = TiktokVideo.find(video_id)
    return unless video.status == "publishing"

    done = Tiktok::VideoPublisher.new(video).check_status!
    return if done

    if attempt >= MAX_ATTEMPTS
      video.update!(status: "failed", error_message: "Timed out waiting for TikTok to finish processing this video")
    else
      Tiktok::CheckVideoStatusJob.set(wait: 10.seconds).perform_later(video_id, attempt + 1)
    end
  end
end
