class Tiktok::VideosController < Tiktok::ApplicationController
  before_action :set_video, only: [:show, :destroy]

  def index
    @videos = Current.user.tiktok_videos.order(created_at: :desc)
  end

  def new
    return redirect_missing_connection if Current.user.tiktok_credential.nil?

    @video = Current.user.tiktok_videos.build(privacy_level: "SELF_ONLY")
  end

  def create
    @video = Current.user.tiktok_videos.build(video_params)
    @video.tiktok_credential = Current.user.tiktok_credential

    if @video.tiktok_credential.nil?
      redirect_missing_connection
    elsif @video.save
      Tiktok::PublishVideoJob.perform_later(@video.id)
      redirect_to tiktok_video_path(@video), notice: "Uploading to TikTok..."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def destroy
    @video.destroy
    redirect_to tiktok_videos_path, notice: "Deleted"
  end

  private

  def set_video
    @video = Current.user.tiktok_videos.find(params[:id])
  end

  def video_params
    params.require(:tiktok_video).permit(:file, :caption, :overlay_text, :privacy_level)
  end

  def redirect_missing_connection
    redirect_to tiktok_connections_path, alert: "Connect a TikTok account first"
  end
end
