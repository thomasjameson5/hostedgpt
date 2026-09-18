require "test_helper"

class Tiktok::CampaignsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:keith)
    login_as @user
    stub_features(tiktok_tools: true)

    @video = create_tiktok_video!(user: @user, status: "posted")
  end

  test "lists campaigns" do
    campaign = TiktokCampaign.create!(user: @user, name: "Existing", objective_type: "TRAFFIC", budget_mode: "BUDGET_MODE_DAY", budget: 10)
    get tiktok_campaigns_url
    assert_response :success

    get edit_tiktok_campaign_url(campaign)
    assert_response :success
  end

  test "walks a campaign through the whole wizard to launch" do
    get new_tiktok_campaign_url
    assert_response :success

    assert_difference "TiktokCampaign.count", 1 do
      post tiktok_campaigns_url, params: {
        tiktok_campaign: {name: "My Campaign", objective_type: "LEAD_GENERATION", budget_mode: "BUDGET_MODE_DAY", budget: 50},
        video_id: @video.id
      }
    end
    campaign = TiktokCampaign.last
    assert_redirected_to audience_tiktok_campaign_path(campaign)
    assert campaign.tiktok_ad_group.present?
    assert_equal @video, campaign.tiktok_ad_group.tiktok_ad.tiktok_video

    get audience_tiktok_campaign_url(campaign)
    assert_response :success

    patch audience_tiktok_campaign_url(campaign), params: {
      tiktok_ad_group: {
        name: "Ad Group", placement_type: "PLACEMENT_TYPE_AUTOMATIC", billing_event: "OCPM",
        budget_mode: "BUDGET_MODE_DAY", budget: 50, schedule_start_time: 1.hour.from_now,
        age_min: 18, age_max: 34, genders: [], location_ids_text: "US, GB", languages_text: "en"
      }
    }
    assert_redirected_to creative_tiktok_campaign_path(campaign)
    campaign.tiktok_ad_group.reload
    assert_equal ["US", "GB"], campaign.tiktok_ad_group.location_ids
    assert_equal ["en"], campaign.tiktok_ad_group.languages
    assert_equal 18, campaign.tiktok_ad_group.age_min
    assert_equal 34, campaign.tiktok_ad_group.age_max

    get creative_tiktok_campaign_url(campaign)
    assert_response :success

    patch creative_tiktok_campaign_url(campaign), params: {
      tiktok_ad: {
        name: "My Ad", ad_text: "Buy now", call_to_action: "LEARN_MORE",
        tiktok_video_id: @video.id, instant_form_id: "form_1"
      }
    }
    assert_redirected_to review_tiktok_campaign_path(campaign)

    ad = campaign.tiktok_ad_group.tiktok_ad.reload
    assert_equal "form_1", ad.instant_form_id
    assert campaign.reload.ready_to_launch?

    get review_tiktok_campaign_url(campaign)
    assert_response :success
    assert_select "form[action=?]", launch_tiktok_campaign_path(campaign)

    Zernio::CampaignLauncher.stub_any_instance :call, -> {
      campaign.update!(status: "launched", tiktok_campaign_id: "camp_1")
      true
    } do
      post launch_tiktok_campaign_url(campaign)
    end

    assert_redirected_to tiktok_campaign_path(campaign)
    assert_equal "launched", campaign.reload.status
  end

  test "cannot launch a campaign that isn't ready" do
    campaign = TiktokCampaign.create!(user: @user, name: "Incomplete", objective_type: "LEAD_GENERATION", budget_mode: "BUDGET_MODE_DAY", budget: 10)
    ad_group = campaign.build_tiktok_ad_group(name: "AG")
    ad_group.save(validate: false)
    ad_group.build_tiktok_ad(name: "Ad")
    ad_group.tiktok_ad.save(validate: false)

    post launch_tiktok_campaign_url(campaign)

    assert_redirected_to review_tiktok_campaign_path(campaign)
    assert_equal "draft", campaign.reload.status
  end
end
