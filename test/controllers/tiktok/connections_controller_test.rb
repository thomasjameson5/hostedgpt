require "test_helper"

class Tiktok::ConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:keith)
    login_as @user
    stub_features(tiktok_tools: true)
  end

  test "redirects home when the feature is disabled" do
    stub_features(tiktok_tools: false) do
      get tiktok_connections_url
      assert_redirected_to root_url
    end
  end

  test "shows the connections page" do
    get tiktok_connections_url
    assert_response :success
  end

  test "connecting a TikTok content account exchanges the code and saves a credential" do
    get tiktok_connections_content_authorize_url
    assert_response :redirect
    state = session[:tiktok_content_oauth_state]
    assert state.present?

    token_response = {"access_token" => "tok_123", "refresh_token" => "ref_123", "open_id" => "open_123", "scope" => "user.info.basic"}
    user_info_response = {"data" => {"user" => {"display_name" => "Keith", "username" => "keithtiktok", "avatar_url" => "http://x/a.png"}}}

    Tiktok::ContentAPI.stub :exchange_code, ->(**) { token_response } do
      Tiktok::ContentAPI.stub_any_instance :user_info, user_info_response do
        get tiktok_connections_content_callback_url, params: {code: "abc", state: state}
      end
    end

    assert_redirected_to tiktok_connections_url
    credential = @user.reload.tiktok_credential
    assert_equal "open_123", credential.external_id
    assert_equal "tok_123", credential.oauth_token
    assert_equal "keithtiktok", credential.username
  end

  test "rejects the content callback if the state doesn't match" do
    get tiktok_connections_content_authorize_url

    get tiktok_connections_content_callback_url, params: {code: "abc", state: "wrong"}

    assert_redirected_to tiktok_connections_url
    assert_match "session expired", flash[:alert]
    assert_nil @user.reload.tiktok_credential
  end

  test "connecting a TikTok Ads account saves a credential and syncs ad accounts" do
    get tiktok_connections_ads_authorize_url
    state = session[:tiktok_ads_oauth_state]

    token_response = {"code" => 0, "data" => {"access_token" => "adtok_123", "advertiser_ids" => ["adv_1"]}}
    advertisers_response = {"code" => 0, "data" => {"list" => [{"advertiser_id" => "adv_1", "advertiser_name" => "My Ad Account"}]}}

    Tiktok::MarketingAPI.stub :exchange_code, ->(**) { token_response } do
      Tiktok::MarketingAPI.stub_any_instance :advertisers, advertisers_response do
        get tiktok_connections_ads_callback_url, params: {auth_code: "abc", state: state}
      end
    end

    assert_redirected_to tiktok_connections_url
    credential = @user.reload.tiktok_ads_credential
    assert_equal "adtok_123", credential.oauth_token
    assert_equal 1, @user.tiktok_ad_accounts.count
    assert_equal "My Ad Account", @user.tiktok_ad_accounts.first.name
  end

  test "disconnecting removes the credential" do
    @user.credentials.create!(type: "TiktokCredential", external_id: "open_1", oauth_token: "t", oauth_refresh_token: "r")

    assert_difference "@user.credentials.count", -1 do
      delete tiktok_connections_content_url
    end

    assert_redirected_to tiktok_connections_url
  end
end
