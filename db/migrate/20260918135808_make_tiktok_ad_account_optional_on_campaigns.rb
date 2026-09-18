# The TikTok Ads account is now resolved automatically from Zernio's connected accounts at
# launch time (see Zernio::CampaignLauncher) instead of being picked from our own
# TiktokAdAccount records, so the campaign no longer needs one up front.
class MakeTiktokAdAccountOptionalOnCampaigns < ActiveRecord::Migration[7.1]
  def change
    change_column_null :tiktok_campaigns, :tiktok_ad_account_id, true
  end
end
