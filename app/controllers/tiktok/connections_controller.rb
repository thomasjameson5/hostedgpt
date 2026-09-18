# Posting and ad campaigns go through Zernio (a third-party layer with its own registered
# TikTok apps), which holds the actual TikTok connection - the user connects their TikTok
# account(s) directly on zernio.com, not through this app. This page is read-only: it just
# shows what's currently connected in Zernio, using this app's single configured API key.
class Tiktok::ConnectionsController < Tiktok::ApplicationController
  def show
    @accounts, @accounts_error = fetch_tiktok_accounts
    # Zernio's exact platform string for a TikTok Business Center / Ads account isn't confirmed
    # in their docs (Zernio::CampaignLauncher tries "tiktokads" and falls back to "tiktok" for
    # the same reason) - this heuristic just separates anything that looks ads/business-related
    # from a plain posting account, so it degrades gracefully if the real string differs.
    @ads_accounts, @posting_accounts = @accounts.partition { |a| ads_platform?(a) }
  end

  private

  def ads_platform?(account)
    platform = account["platform"].to_s.downcase
    platform.include?("ads") || platform.include?("business")
  end

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
