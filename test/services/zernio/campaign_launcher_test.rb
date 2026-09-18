require "test_helper"

class Zernio::CampaignLauncherTest < ActiveSupport::TestCase
  class FakeZernio
    attr_reader :calls

    def initialize
      @calls = []
      @account = {"_id" => "acc_1", "adAccountId" => "adacc_1"}
    end

    def accounts_list(**args)
      @calls << [:accounts_list, args]
      {"accounts" => [@account]}
    end

    def create_ad(**args)
      @calls << [:create_ad, args]
      {"ad" => {"platformAdId" => "ad_123", "platformCampaignId" => "camp_123", "platformAdSetId" => "adset_123"}}
    end
  end

  setup do
    @user = users(:keith)
    @campaign = TiktokCampaign.create!(user: @user, name: "Campaign", objective_type: "LEAD_GENERATION", budget_mode: "BUDGET_MODE_DAY", budget: 50)
    @ad_group = @campaign.build_tiktok_ad_group(name: "Ad Group", budget: 50, schedule_start_time: 1.hour.from_now, location_ids: ["US"])
    @ad_group.save!

    @video = create_tiktok_video!(user: @user, status: "posted")

    @ad = @ad_group.build_tiktok_ad(name: "Ad", tiktok_video: @video, instant_form_id: "form1", call_to_action: "LEARN_MORE")
    @ad.save!

    @fake_zernio = FakeZernio.new
  end

  test "launches the campaign, ad group, and ad in a single Zernio call" do
    result = Zernio::CampaignLauncher.new(@campaign, zernio: @fake_zernio).call

    assert result
    assert_equal "launched", @campaign.reload.status
    assert_equal "launched", @ad_group.reload.status
    assert_equal "launched", @ad.reload.status
    assert_equal "camp_123", @campaign.tiktok_campaign_id
    assert_equal "adset_123", @ad_group.tiktok_adgroup_id
    assert_equal "ad_123", @ad.tiktok_ad_id
    assert_equal [:accounts_list, :create_ad], @fake_zernio.calls.map(&:first)
  end

  test "marks the campaign failed when Zernio has no connected TikTok Ads account" do
    def @fake_zernio.accounts_list(**)
      @calls << [:accounts_list, {}]
      {"accounts" => []}
    end

    result = Zernio::CampaignLauncher.new(@campaign, zernio: @fake_zernio).call

    refute result
    assert_equal "failed", @campaign.reload.status
    assert_match "No TikTok Ads account connected", @campaign.error_message
  end

  test "marks the campaign failed when Zernio doesn't return an ad id" do
    def @fake_zernio.create_ad(**args)
      @calls << [:create_ad, args]
      {"ad" => {}}
    end

    result = Zernio::CampaignLauncher.new(@campaign, zernio: @fake_zernio).call

    refute result
    assert_equal "failed", @campaign.reload.status
    assert_match "didn't return an ad id", @campaign.error_message
  end

  test "refuses to launch a campaign that isn't ready" do
    @ad.update_column(:instant_form_id, nil)

    result = Zernio::CampaignLauncher.new(@campaign, zernio: @fake_zernio).call

    refute result
    assert_equal "failed", @campaign.reload.status
    assert_match "not ready", @campaign.error_message
    assert_empty @fake_zernio.calls
  end
end
