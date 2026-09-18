module TiktokTestHelpers
  def create_tiktok_video!(**)
    video = TiktokVideo.new(status: "pending", privacy_level: "SELF_ONLY", **)
    video.file.attach(io: File.open(Rails.root.join("test/fixtures/files/racecar.jpg")), filename: "video.mp4", content_type: "video/mp4")
    video.save!
    video
  end
end
