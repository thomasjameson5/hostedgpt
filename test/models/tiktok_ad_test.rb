require "test_helper"

class TiktokAdTest < ActiveSupport::TestCase
  setup do
    @user = users(:keith)
    @campaign = TiktokCampaign.create!(user: @user, name: "Campaign", objective_type: "LEAD_GENERATION", budget_mode: "BUDGET_MODE_DAY", budget: 50)
    @ad_group = @campaign.build_tiktok_ad_group(name: "Ad Group", budget: 50, schedule_start_time: 1.hour.from_now)
    @ad_group.save!

    @video = create_tiktok_video!(user: @user, status: "posted")

    @ad = @ad_group.build_tiktok_ad(name: "Ad", tiktok_video: @video, instant_form_id: "form1", call_to_action: "LEARN_MORE")
  end

  test "is ready to launch when video and instant form (for lead gen) are set" do
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

  test "requires an instant form id to save on a lead generation campaign" do
    @ad.instant_form_id = nil
    refute @ad.valid?
  end

  test "does not require an instant form id to save on a non lead generation campaign" do
    @campaign.update!(objective_type: "TRAFFIC")
    @ad.instant_form_id = nil
    assert @ad.valid?
  end
end
