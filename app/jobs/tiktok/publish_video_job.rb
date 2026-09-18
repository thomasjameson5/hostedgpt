class Tiktok::PublishVideoJob < ApplicationJob
  queue_as :default

  def perform(video_id)
    video = TiktokVideo.find(video_id)
    published = Tiktok::VideoPublisher.new(video).publish!
    Tiktok::CheckVideoStatusJob.set(wait: 10.seconds).perform_later(video_id) if published
  end
end
