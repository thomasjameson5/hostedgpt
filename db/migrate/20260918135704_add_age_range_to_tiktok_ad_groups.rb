# Zernio's ad targeting uses simple ageMin/ageMax integers rather than TikTok's native
# age-bucket enums (which the now-unused age_groups jsonb column was built for).
class AddAgeRangeToTiktokAdGroups < ActiveRecord::Migration[7.1]
  def change
    add_column :tiktok_ad_groups, :age_min, :integer
    add_column :tiktok_ad_groups, :age_max, :integer
  end
end
