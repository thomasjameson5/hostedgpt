require "test_helper"

class Tiktok::CampaignLauncherTest < ActiveSupport::TestCase
  class FakeMarketingAPI
    attr_reader :calls

    def initialize
      @calls = []
    end

    def upload_ad_video(**args)
      @calls << [:upload_ad_video, args]
      {"code" => 0, "data" => {"video_id" => "vid_123"}}
    end

    def create_campaign(campaign, advertiser_id:)
      @calls << [:create_campaign, campaign, advertiser_id]
      {"code" => 0, "data" => {"campaign_id" => "camp_123"}}
    end

    def create_adgroup(ad_group, advertiser_id:, campaign_id:)
      @calls << [:create_adgroup, ad_group, advertiser_id, campaign_id]
      {"code" => 0, "data" => {"adgroup_id" => "adg_123"}}
    end

    def create_ad(ad, advertiser_id:, adgroup_id:)
      @calls << [:create_ad, ad, advertiser_id, adgroup_id]
      {"code" => 0, "data" => {"ad_ids" => ["ad_123"]}}
    end
  end

  setup do
    @user = users(:keith)
    ads_credential = @user.credentials.create!(type: "TiktokAdsCredential", external_id: "adv123", oauth_token: "token")
    @ad_account = TiktokAdAccount.create!(user: @user, tiktok_ads_credential: ads_credential, advertiser_id: "adv123", name: "My Ads")

    @campaign = TiktokCampaign.create!(user: @user, tiktok_ad_account: @ad_account, name: "Campaign", objective_type: "LEAD_GENERATION", budget_mode: "BUDGET_MODE_DAY", budget: 50)
    @ad_group = @campaign.build_tiktok_ad_group(name: "Ad Group", budget: 50, schedule_start_time: 1.hour.from_now)
    @ad_group.save!

    content_credential = @user.credentials.create!(type: "TiktokCredential", external_id: "open123", oauth_token: "t", oauth_refresh_token: "r")
    @video = create_tiktok_video!(user: @user, tiktok_credential: content_credential, status: "posted")

    @ad = @ad_group.build_tiktok_ad(name: "Ad", tiktok_video: @video, identity_id: "id1", identity_type: "CUSTOMIZED_USER", instant_form_id: "form1")
    @ad.save!

    @fake_api = FakeMarketingAPI.new
  end

  test "walks the campaign through video upload, campaign, ad group, and ad creation" do
    result = Tiktok::CampaignLauncher.new(@campaign, marketing_api: @fake_api).call

    assert result
    assert_equal "launched", @campaign.reload.status
    assert_equal "launched", @ad_group.reload.status
    assert_equal "launched", @ad.reload.status
    assert_equal "camp_123", @campaign.tiktok_campaign_id
    assert_equal "adg_123", @ad_group.tiktok_adgroup_id
    assert_equal "ad_123", @ad.tiktok_ad_id
    assert_equal "vid_123", @video.reload.tiktok_ad_video_id
    assert_equal [:upload_ad_video, :create_campaign, :create_adgroup, :create_ad], @fake_api.calls.map(&:first)
  end

  test "skips steps that already have a TikTok id, for idempotent retries" do
    @campaign.update!(tiktok_campaign_id: "already_there")

    Tiktok::CampaignLauncher.new(@campaign, marketing_api: @fake_api).call

    refute_includes @fake_api.calls.map(&:first), :create_campaign
    assert_includes @fake_api.calls.map(&:first), :create_adgroup
  end

  test "marks the campaign failed and records the error when TikTok rejects the request" do
    def @fake_api.upload_ad_video(**)
      {"code" => 40001, "message" => "boom"}
    end

    result = Tiktok::CampaignLauncher.new(@campaign, marketing_api: @fake_api).call

    refute result
    assert_equal "failed", @campaign.reload.status
    assert_match "boom", @campaign.error_message
    assert_equal "failed", @ad.reload.status
  end

  test "refuses to launch a campaign that isn't ready" do
    @ad.update_column(:instant_form_id, nil)

    result = Tiktok::CampaignLauncher.new(@campaign, marketing_api: @fake_api).call

    refute result
    assert_equal "failed", @campaign.reload.status
    assert_match "not ready", @campaign.error_message
    assert_empty @fake_api.calls
  end
end
