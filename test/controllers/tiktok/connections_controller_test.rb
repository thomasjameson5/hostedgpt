require "test_helper"

class Tiktok::ConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:keith)
    login_as @user
    stub_features(tiktok_tools: true)
    stub_settings(zernio_api_key: "sk_test_123")
  end

  test "redirects home when the feature is disabled" do
    stub_features(tiktok_tools: false) do
      get tiktok_connections_url
      assert_redirected_to root_url
    end
  end

  test "shows the connections page with Zernio's connected TikTok accounts" do
    accounts_response = {"accounts" => [
      {"_id" => "acc_1", "platform" => "tiktok", "username" => "Keith"},
      {"_id" => "acc_2", "platform" => "facebook", "username" => "Not TikTok"}
    ]}

    Zernio::API.stub_any_instance :accounts_list, accounts_response do
      get tiktok_connections_url
    end

    assert_response :success
    assert_select "body", /Keith/
    assert_select "body", /No TikTok Ads \/ Business Center account connected/
  end

  test "splits ads/business-center accounts from the posting account" do
    accounts_response = {"accounts" => [
      {"_id" => "acc_1", "platform" => "tiktok", "username" => "Keith"},
      {"_id" => "acc_2", "platform" => "tiktokads", "username" => "Keith Ads"}
    ]}

    Zernio::API.stub_any_instance :accounts_list, accounts_response do
      get tiktok_connections_url
    end

    assert_response :success
    assert_select "body", /Keith Ads/
    refute_match "No TikTok Ads / Business Center account connected", @response.body
  end

  test "shows an error when Zernio isn't reachable" do
    Zernio::API.stub_any_instance :accounts_list, ->(**) { raise Zernio::Http::Error, "boom" } do
      get tiktok_connections_url
    end

    assert_response :success
  end
end
