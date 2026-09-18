class CreateTiktokTables < ActiveRecord::Migration[7.1]
  def change
    create_table :tiktok_ad_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :tiktok_ads_credential, null: false, foreign_key: { to_table: :credentials }
      t.string :advertiser_id, null: false
      t.string :name

      t.timestamps
    end
    add_index :tiktok_ad_accounts, [:tiktok_ads_credential_id, :advertiser_id], unique: true, name: "index_tiktok_ad_accounts_on_credential_and_advertiser"

    create_table :tiktok_videos do |t|
      t.references :user, null: false, foreign_key: true
      t.references :tiktok_credential, null: false, foreign_key: { to_table: :credentials }
      t.text :caption
      t.string :overlay_text
      t.string :privacy_level, null: false, default: "SELF_ONLY", comment: "TikTok Content Posting API privacy_level. Unaudited apps are restricted to SELF_ONLY (private)."
      t.string :status, null: false, default: "pending", comment: "pending, processing, publishing, posted, failed"
      t.string :tiktok_publish_id
      t.string :tiktok_item_id, comment: "The published TikTok video/item id once posted"
      t.string :tiktok_ad_video_id, comment: "The video_id returned by the Marketing API's ad creative asset upload, used to build ad creatives"
      t.text :error_message

      t.timestamps
    end

    create_table :tiktok_campaigns do |t|
      t.references :user, null: false, foreign_key: true
      t.references :tiktok_ad_account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :objective_type, null: false, default: "LEAD_GENERATION"
      t.string :budget_mode, null: false, default: "BUDGET_MODE_DAY"
      t.decimal :budget, precision: 12, scale: 2
      t.string :status, null: false, default: "draft", comment: "draft, launching, launched, failed"
      t.string :tiktok_campaign_id
      t.text :error_message

      t.timestamps
    end

    create_table :tiktok_ad_groups do |t|
      t.references :tiktok_campaign, null: false, foreign_key: true
      t.string :name, null: false
      t.string :placement_type, null: false, default: "PLACEMENT_TYPE_AUTOMATIC"
      t.string :optimization_goal, null: false, default: "LEAD_GENERATION"
      t.string :billing_event, null: false, default: "OCPM"
      t.decimal :bid_price, precision: 12, scale: 2
      t.string :budget_mode, null: false, default: "BUDGET_MODE_DAY"
      t.decimal :budget, precision: 12, scale: 2
      t.datetime :schedule_start_time
      t.datetime :schedule_end_time
      t.jsonb :location_ids, default: []
      t.jsonb :age_groups, default: []
      t.jsonb :genders, default: []
      t.jsonb :languages, default: []
      t.string :status, null: false, default: "draft"
      t.string :tiktok_adgroup_id
      t.text :error_message

      t.timestamps
    end

    create_table :tiktok_ads do |t|
      t.references :tiktok_ad_group, null: false, foreign_key: true
      t.references :tiktok_video, null: true, foreign_key: true, comment: "Nullable until the creative step of the campaign wizard picks a video"
      t.string :name, null: false
      t.string :ad_text
      t.string :call_to_action, null: false, default: "LEARN_MORE"
      t.string :identity_type, comment: "The TikTok 'card' - which account identity the ad is shown as coming from"
      t.string :identity_id
      t.string :identity_display_name
      t.string :instant_form_id
      t.string :instant_form_name
      t.string :landing_page_url
      t.string :status, null: false, default: "draft"
      t.string :tiktok_ad_id
      t.text :error_message

      t.timestamps
    end
  end
end
