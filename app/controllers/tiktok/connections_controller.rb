require "securerandom"

# Connects two separate TikTok OAuth apps:
#  - the Login Kit / Content Posting API app (posts videos to a creator/business account)
#  - the Marketing API app (manages ad accounts, campaigns, ad groups, and ads)
# TikTok treats these as different products with different developer apps and scopes, so a user
# may need to connect both here before they can use the video and campaign wizards.
class Tiktok::ConnectionsController < Tiktok::ApplicationController
  def show
    @content_credential = Current.user.tiktok_credential
    @ads_credential = Current.user.tiktok_ads_credential
    @ad_accounts = Current.user.tiktok_ad_accounts
  end

  def new_content
    state = SecureRandom.hex(16)
    session[:tiktok_content_oauth_state] = state
    redirect_to Tiktok::ContentAPI.authorize_url(redirect_uri: tiktok_connections_content_callback_url, state: state), allow_other_host: true
  end

  def callback_content
    verify_state!(:tiktok_content_oauth_state)
    raise params[:error_description].presence || params[:error] if params[:error].present?

    token = Tiktok::ContentAPI.exchange_code(code: params[:code], redirect_uri: tiktok_connections_content_callback_url)
    raise token["error_description"].presence || token["error"] if token["error"].present?

    Current.user.tiktok_credential&.destroy

    credential = Current.user.credentials.build(
      type: "TiktokCredential",
      external_id: token["open_id"],
      oauth_token: token["access_token"],
      oauth_refresh_token: token["refresh_token"],
      properties: {scope: token["scope"]}
    )

    info = Tiktok::ContentAPI.new(credential: credential).user_info.dig("data", "user") || {}
    credential.properties = credential.properties.merge(
      "display_name" => info["display_name"],
      "username" => info["username"],
      "avatar_url" => info["avatar_url"]
    )

    credential.save!
    redirect_to tiktok_connections_path, notice: "Connected your TikTok account"
  rescue => e
    redirect_to tiktok_connections_path, alert: "Couldn't connect your TikTok account: #{e.message}"
  end

  def destroy_content
    Current.user.tiktok_credential&.destroy
    redirect_to tiktok_connections_path, notice: "Disconnected your TikTok account"
  end

  def new_ads
    state = SecureRandom.hex(16)
    session[:tiktok_ads_oauth_state] = state
    redirect_to Tiktok::MarketingAPI.authorize_url(redirect_uri: tiktok_connections_ads_callback_url, state: state), allow_other_host: true
  end

  def callback_ads
    verify_state!(:tiktok_ads_oauth_state)
    raise params[:error_description].presence || params[:error] if params[:error].present?

    token = Tiktok::MarketingAPI.exchange_code(auth_code: params[:auth_code] || params[:code])
    raise token["message"].presence || "TikTok returned an error" if token["code"].present? && token["code"].to_i != 0
    data = token["data"] || {}
    raise "No access token returned" if data["access_token"].blank?

    Current.user.tiktok_ads_credential&.destroy

    credential = Current.user.credentials.build(
      type: "TiktokAdsCredential",
      external_id: Array(data["advertiser_ids"]).first.presence || SecureRandom.uuid,
      oauth_token: data["access_token"],
      properties: {"display_name" => "TikTok Ads"}
    )
    credential.save!

    sync_ad_accounts_for!(credential)

    redirect_to tiktok_connections_path, notice: "Connected your TikTok Ads account"
  rescue => e
    redirect_to tiktok_connections_path, alert: "Couldn't connect your TikTok Ads account: #{e.message}"
  end

  def destroy_ads
    Current.user.tiktok_ads_credential&.destroy
    redirect_to tiktok_connections_path, notice: "Disconnected your TikTok Ads account"
  end

  def sync_ad_accounts
    credential = Current.user.tiktok_ads_credential
    raise "Connect a TikTok Ads account first" unless credential

    sync_ad_accounts_for!(credential)
    redirect_to tiktok_connections_path, notice: "Refreshed your TikTok ad accounts"
  rescue => e
    redirect_to tiktok_connections_path, alert: "Couldn't refresh ad accounts: #{e.message}"
  end

  private

  def verify_state!(session_key)
    expected = session.delete(session_key)
    raise "Your session expired, please try connecting again" if expected.blank? || expected != params[:state]
  end

  def sync_ad_accounts_for!(credential)
    response = Tiktok::MarketingAPI.new(credential: credential).advertisers
    raise response["message"].presence || "Couldn't load ad accounts" if response["code"].present? && response["code"].to_i != 0

    list = response.dig("data", "list") || []
    list.each do |advertiser|
      account = credential.tiktok_ad_accounts.find_or_initialize_by(advertiser_id: advertiser["advertiser_id"])
      account.user = Current.user
      account.name = advertiser["advertiser_name"]
      account.save!
    end
  end
end
