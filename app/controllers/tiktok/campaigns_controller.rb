# The ad campaign wizard: choose the ad account and objective/budget -> audience settings for
# the ad group -> creative (video + call to action + the "card"/Identity TikTok shows the ad as
# coming from + the Instant Form for lead generation) -> review -> launch.
#
# A TiktokCampaign's TiktokAdGroup and TiktokAd are created (unvalidated) as soon as the campaign
# is, so each wizard step just updates the relevant record; nothing is sent to TikTok until the
# final "Launch" step, which is handled by Tiktok::CampaignLauncher.
class Tiktok::CampaignsController < Tiktok::ApplicationController
  before_action :set_campaign, only: [:show, :edit, :update, :destroy, :audience, :update_audience, :creative, :update_creative, :review, :launch]
  before_action :set_ad_group, only: [:audience, :update_audience, :creative, :update_creative, :review, :launch]
  before_action :set_ad, only: [:creative, :update_creative, :review, :launch]

  def index
    @campaigns = Current.user.tiktok_campaigns.includes(:tiktok_ad_account).order(created_at: :desc)
  end

  def new
    if Current.user.tiktok_ad_accounts.empty?
      return redirect_to tiktok_connections_path, alert: "Connect a TikTok Ads account first"
    end

    @campaign = Current.user.tiktok_campaigns.build(objective_type: "LEAD_GENERATION", budget_mode: "BUDGET_MODE_DAY")
    @ad_accounts = Current.user.tiktok_ad_accounts
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
      @ad_accounts = Current.user.tiktok_ad_accounts
      @video_id = params[:video_id]
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def edit
    @ad_accounts = Current.user.tiktok_ad_accounts
  end

  def update
    if @campaign.update(campaign_params)
      redirect_to tiktok_campaign_path(@campaign), notice: "Saved"
    else
      @ad_accounts = Current.user.tiktok_ad_accounts
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
    @identities, @identities_error = fetch_identities
    @instant_forms, @instant_forms_error = (@campaign.objective_type == "LEAD_GENERATION") ? fetch_instant_forms : [[], nil]
  end

  def update_creative
    @videos = Current.user.tiktok_videos.to_a.select { |v| v.file.attached? }
    @identities, @identities_error = fetch_identities
    @instant_forms, @instant_forms_error = (@campaign.objective_type == "LEAD_GENERATION") ? fetch_instant_forms : [[], nil]

    if @ad.update(ad_attributes)
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

    if Tiktok::CampaignLauncher.new(@campaign).call
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
    params.require(:tiktok_campaign).permit(:name, :objective_type, :budget_mode, :budget, :tiktok_ad_account_id)
  end

  def ad_group_params
    params.require(:tiktok_ad_group).permit(
      :name, :placement_type, :optimization_goal, :billing_event, :bid_price,
      :budget_mode, :budget, :schedule_start_time, :schedule_end_time,
      :location_ids_text, :languages_text,
      age_groups: [], genders: []
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

  # identity_choice comes from a single radio group carrying "identity_id|identity_type" so we
  # don't need JS to keep two separate inputs in sync when the user picks a different card.
  def ad_attributes
    attrs = params.require(:tiktok_ad).permit(:name, :ad_text, :call_to_action, :tiktok_video_id, :identity_choice, :instant_form_id).to_h

    if (choice = attrs.delete("identity_choice")).present?
      identity_id, identity_type = choice.split("|", 2)
      identity = @identities.find { |i| i["identity_id"] == identity_id }
      attrs["identity_id"] = identity_id
      attrs["identity_type"] = identity_type
      attrs["identity_display_name"] = identity&.dig("display_name")
    end

    if attrs["instant_form_id"].present?
      form = @instant_forms.find { |f| (f["page_id"] || f["form_id"]).to_s == attrs["instant_form_id"].to_s }
      attrs["instant_form_name"] = form&.dig("form_name") || form&.dig("page_name")
    end

    attrs
  end

  def fetch_identities
    response = Tiktok::MarketingAPI.new(credential: @campaign.tiktok_ad_account.tiktok_ads_credential)
      .identities(advertiser_id: @campaign.tiktok_ad_account.advertiser_id)
    raise response["message"].presence || "TikTok returned an error" if response["code"].present? && response["code"].to_i != 0

    [response.dig("data", "identity_list") || [], nil]
  rescue => e
    [[], e.message]
  end

  def fetch_instant_forms
    response = Tiktok::MarketingAPI.new(credential: @campaign.tiktok_ad_account.tiktok_ads_credential)
      .instant_forms(advertiser_id: @campaign.tiktok_ad_account.advertiser_id)
    raise response["message"].presence || "TikTok returned an error" if response["code"].present? && response["code"].to_i != 0

    [response.dig("data", "list") || [], nil]
  rescue => e
    [[], e.message]
  end
end
