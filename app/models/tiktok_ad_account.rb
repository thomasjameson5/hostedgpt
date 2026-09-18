class TiktokAdAccount < ApplicationRecord
  belongs_to :user
  belongs_to :tiktok_ads_credential

  has_many :tiktok_campaigns, dependent: :destroy

  validates :advertiser_id, presence: true, uniqueness: {scope: :tiktok_ads_credential_id}
end
