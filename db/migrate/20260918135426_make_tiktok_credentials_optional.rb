# Posting and ad campaigns now go through Zernio (which holds its own TikTok connection) instead
# of our own TikTok OAuth apps, so the direct-TikTok credential foreign keys are no longer
# required on new records. Left nullable rather than dropped, since Credential::Tiktok* and the
# direct API service classes still exist for anyone who does register their own TikTok apps.
class MakeTiktokCredentialsOptional < ActiveRecord::Migration[7.1]
  def change
    change_column_null :tiktok_videos, :tiktok_credential_id, true
    change_column_null :tiktok_ad_accounts, :tiktok_ads_credential_id, true
  end
end
