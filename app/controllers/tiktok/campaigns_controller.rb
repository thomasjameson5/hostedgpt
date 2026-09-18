# The ad campaign wizard: settings/objective/budget -> audience settings for the ad group ->
# creative (video + call to action + landing page/Instant Form) -> review -> launch.
#
# A TiktokCampaign's TiktokAdGroup and TiktokAd are created (unvalidated) as soon as the campaign
# is, so each wizard step just updates the relevant record; nothing is sent to TikTok until the
# final "Launch" step, which is handled by Zernio::CampaignLauncher. The TikTok Ads account
# itself is resolved automatically from Zernio's connected accounts at launch time, not picked
# here, so there's no ad-account step.
class Tiktok::CampaignsController < Tiktok::ApplicationController
  before_action :set_campaign, only: [:show, :edit, :update, :destroy, :audience, :update_audience, :creative, :update_creative, :review, :launch]
  before_action :set_ad_group, only: [:audience, :update_audience, :creative, :update_creative, :review, :launch]
  before_action :set_ad, only: [:creative, :update_creative, :review, :launch]

  def index
    @campaigns = Current.user.tiktok_campaigns.order(created_at: :desc)
  end

  def new
    @campaign = Current.user.tiktok_campaigns.build(objective_type: "LEAD_GENERATION", budget_mode: "BUDGET_MODE_DAY")
    @video_id = params[:video_id]
  end

  def create
    @campaign = Current.user.tiktok_campaigns.build(campaign_params)

    if @campaign.save
      ad_group = @campaign.build_tiktok_ad_group(name: "#{@campaign.name} - Ad Group")
      ad_group.save(validate: false)
      ad_group.build_tiktok_ad(name: "#{@campaign.name} - Ad", tiktok_video_id: params[:video_id].presence)
      ad_group.tiktok_ad.save(validate: false)

      redirect_to audience_tiktok_campaign_path(@campaign)
    else
      @video_id = params[:video_id]
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def edit
  end

  def update
    if @campaign.update(campaign_params)
      redirect_to tiktok_campaign_path(@campaign), notice: "Saved"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @campaign.destroy
    redirect_to tiktok_campaigns_path, notice: "Deleted"
  end

  def audience
  end

  def update_audience
    if @ad_group.update(audience_attributes)
      redirect_to creative_tiktok_campaign_path(@campaign)
    else
      render :audience, status: :unprocessable_entity
    end
  end

  def creative
    @videos = Current.user.tiktok_videos.to_a.select { |v| v.file.attached? }
  end

  def update_creative
    @videos = Current.user.tiktok_videos.to_a.select { |v| v.file.attached? }

    if @ad.update(ad_params)
      redirect_to review_tiktok_campaign_path(@campaign)
    else
      render :creative, status: :unprocessable_entity
    end
  end

  def review
  end

  def launch
    unless @campaign.ready_to_launch?
      return redirect_to review_tiktok_campaign_path(@campaign), alert: "Finish filling out every step before launching"
    end

    if Zernio::CampaignLauncher.new(@campaign).call
      redirect_to tiktok_campaign_path(@campaign), notice: "Campaign launched on TikTok!"
    else
      redirect_to review_tiktok_campaign_path(@campaign), alert: @campaign.reload.error_message.presence || "TikTok rejected the campaign"
    end
  end

  private

  def set_campaign
    @campaign = Current.user.tiktok_campaigns.find(params[:id])
  end

  def set_ad_group
    @ad_group = @campaign.tiktok_ad_group
    unless @ad_group
      @ad_group = @campaign.build_tiktok_ad_group(name: "#{@campaign.name} - Ad Group")
      @ad_group.save(validate: false)
    end
  end

  def set_ad
    @ad = @ad_group.tiktok_ad
    unless @ad
      @ad = @ad_group.build_tiktok_ad(name: "#{@campaign.name} - Ad")
      @ad.save(validate: false)
    end
  end

  def campaign_params
    params.require(:tiktok_campaign).permit(:name, :objective_type, :budget_mode, :budget)
  end

  def ad_group_params
    params.require(:tiktok_ad_group).permit(
      :name, :placement_type, :optimization_goal, :billing_event, :bid_price,
      :budget_mode, :budget, :schedule_start_time, :schedule_end_time,
      :age_min, :age_max, :location_ids_text, :languages_text,
      genders: []
    )
  end

  # location_ids/languages come in as comma-separated text fields rather than jsonb array
  # inputs, so split them out before assigning to the jsonb columns.
  def audience_attributes
    attrs = ad_group_params.to_h
    attrs["location_ids"] = attrs.delete("location_ids_text").to_s.split(",").map(&:strip).reject(&:blank?)
    attrs["languages"] = attrs.delete("languages_text").to_s.split(",").map(&:strip).reject(&:blank?)
    attrs
  end

  def ad_params
    params.require(:tiktok_ad).permit(:name, :ad_text, :call_to_action, :tiktok_video_id, :landing_page_url, :instant_form_id)
  end
end
