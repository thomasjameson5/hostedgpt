# Posting and ad campaigns go through Zernio (a third-party layer with its own registered
# TikTok apps), which holds the actual TikTok connection - the user connects their TikTok
# account(s) directly on zernio.com, not through this app. This page is read-only: it just
# shows what's currently connected in Zernio, using this app's single configured API key.
class Tiktok::ConnectionsController < Tiktok::ApplicationController
  def show
    @accounts, @accounts_error = fetch_tiktok_accounts
  end

  private

  def fetch_tiktok_accounts
    return [[], "Set ZERNIO_API_KEY to connect this app to Zernio"] if Setting.zernio_api_key.blank?

    response = Zernio::API.new.accounts_list
    accounts = response["accounts"] || response["data"] || response
    tiktok_accounts = Array(accounts).select { |a| a["platform"].to_s.downcase.include?("tiktok") }
    [tiktok_accounts, nil]
  rescue => e
    [[], e.message]
  end
end
