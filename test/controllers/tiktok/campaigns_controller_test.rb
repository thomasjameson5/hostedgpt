require "test_helper"

class Tiktok::CampaignsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:keith)
    login_as @user
    stub_features(tiktok_tools: true)

    ads_credential = @user.credentials.create!(type: "TiktokAdsCredential", external_id: "adv_1", oauth_token: "t")
    @ad_account = TiktokAdAccount.create!(user: @user, tiktok_ads_credential: ads_credential, advertiser_id: "adv_1", name: "My Ads")

    content_credential = @user.credentials.create!(type: "TiktokCredential", external_id: "open_1", oauth_token: "t", oauth_refresh_token: "r")
    @video = create_tiktok_video!(user: @user, tiktok_credential: content_credential, status: "posted")

    @identities_response = {"code" => 0, "data" => {"identity_list" => [{"identity_id" => "id_1", "identity_type" => "CUSTOMIZED_USER", "display_name" => "My Brand"}]}}
    @instant_forms_response = {"code" => 0, "data" => {"list" => [{"page_id" => "form_1", "form_name" => "Lead Form"}]}}
  end

  test "lists campaigns" do
    campaign = TiktokCampaign.create!(user: @user, tiktok_ad_account: @ad_account, name: "Existing", objective_type: "TRAFFIC", budget_mode: "BUDGET_MODE_DAY", budget: 10)
    get tiktok_campaigns_url
    assert_response :success

    get edit_tiktok_campaign_url(campaign)
    assert_response :success
  end

  test "redirects to connect an ads account before starting a new campaign" do
    @user.tiktok_ad_accounts.destroy_all
    get new_tiktok_campaign_url
    assert_redirected_to tiktok_connections_url
  end

  test "walks a campaign through the whole wizard to launch" do
    get new_tiktok_campaign_url
    assert_response :success

    assert_difference "TiktokCampaign.count", 1 do
      post tiktok_campaigns_url, params: {
        tiktok_campaign: {tiktok_ad_account_id: @ad_account.id, name: "My Campaign", objective_type: "LEAD_GENERATION", budget_mode: "BUDGET_MODE_DAY", budget: 50},
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
        age_groups: ["AGE_18_24"], genders: [], location_ids_text: "1, 2", languages_text: "en"
      }
    }
    assert_redirected_to creative_tiktok_campaign_path(campaign)
    campaign.tiktok_ad_group.reload
    assert_equal ["1", "2"], campaign.tiktok_ad_group.location_ids
    assert_equal ["en"], campaign.tiktok_ad_group.languages

    Tiktok::MarketingAPI.stub_any_instance :identities, @identities_response do
      Tiktok::MarketingAPI.stub_any_instance :instant_forms, @instant_forms_response do
        get creative_tiktok_campaign_url(campaign)
        assert_response :success

        patch creative_tiktok_campaign_url(campaign), params: {
          tiktok_ad: {
            name: "My Ad", ad_text: "Buy now", call_to_action: "LEARN_MORE",
            tiktok_video_id: @video.id, identity_choice: "id_1|CUSTOMIZED_USER", instant_form_id: "form_1"
          }
        }
      end
    end
    assert_redirected_to review_tiktok_campaign_path(campaign)

    ad = campaign.tiktok_ad_group.tiktok_ad.reload
    assert_equal "id_1", ad.identity_id
    assert_equal "CUSTOMIZED_USER", ad.identity_type
    assert_equal "My Brand", ad.identity_display_name
    assert_equal "form_1", ad.instant_form_id
    assert_equal "Lead Form", ad.instant_form_name
    assert campaign.reload.ready_to_launch?

    get review_tiktok_campaign_url(campaign)
    assert_response :success
    assert_select "form[action=?]", launch_tiktok_campaign_path(campaign)

    Tiktok::CampaignLauncher.stub_any_instance :call, -> {
      campaign.update!(status: "launched", tiktok_campaign_id: "camp_1")
      true
    } do
      post launch_tiktok_campaign_url(campaign)
    end

    assert_redirected_to tiktok_campaign_path(campaign)
    assert_equal "launched", campaign.reload.status
  end

  test "cannot launch a campaign that isn't ready" do
    campaign = TiktokCampaign.create!(user: @user, tiktok_ad_account: @ad_account, name: "Incomplete", objective_type: "LEAD_GENERATION", budget_mode: "BUDGET_MODE_DAY", budget: 10)
    ad_group = campaign.build_tiktok_ad_group(name: "AG")
    ad_group.save(validate: false)
    ad_group.build_tiktok_ad(name: "Ad")
    ad_group.tiktok_ad.save(validate: false)

    post launch_tiktok_campaign_url(campaign)

    assert_redirected_to review_tiktok_campaign_path(campaign)
    assert_equal "draft", campaign.reload.status
  end
end
