require "test_helper"

class TiktokAdTest < ActiveSupport::TestCase
  setup do
    @user = users(:keith)
    ads_credential = @user.credentials.create!(type: "TiktokAdsCredential", external_id: "adv123", oauth_token: "token")
    ad_account = TiktokAdAccount.create!(user: @user, tiktok_ads_credential: ads_credential, advertiser_id: "adv123", name: "My Ads")
    @campaign = TiktokCampaign.create!(user: @user, tiktok_ad_account: ad_account, name: "Campaign", objective_type: "LEAD_GENERATION", budget_mode: "BUDGET_MODE_DAY", budget: 50)
    @ad_group = @campaign.build_tiktok_ad_group(name: "Ad Group", budget: 50, schedule_start_time: 1.hour.from_now)
    @ad_group.save!

    content_credential = @user.credentials.create!(type: "TiktokCredential", external_id: "open123", oauth_token: "t", oauth_refresh_token: "r")
    @video = create_tiktok_video!(user: @user, tiktok_credential: content_credential, status: "posted")

    @ad = @ad_group.build_tiktok_ad(name: "Ad", tiktok_video: @video, identity_id: "id1", identity_type: "CUSTOMIZED_USER", instant_form_id: "form1", call_to_action: "LEARN_MORE")
  end

  test "is ready to launch when video, identity, and instant form (for lead gen) are all set" do
    assert @ad.ready_to_launch?
  end

  test "is not ready to launch without an instant form on a lead generation campaign" do
    @ad.instant_form_id = nil
    refute @ad.ready_to_launch?
  end

  test "does not require an instant form for non lead generation objectives" do
    @campaign.update!(objective_type: "TRAFFIC")
    @ad.instant_form_id = nil
    assert @ad.ready_to_launch?
  end

  test "is not ready to launch without a video" do
    @ad.tiktok_video = nil
    refute @ad.ready_to_launch?
  end

  test "requires identity_id and identity_type to save" do
    @ad.identity_id = nil
    refute @ad.valid?
  end
end
