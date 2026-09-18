class TiktokAdsCredential < Credential
  alias_attribute :open_id, :external_id

  validates :oauth_token, presence: true
  validates :open_id, presence: true, uniqueness: true

  has_many :tiktok_ad_accounts, dependent: :destroy

  def display_name
    properties&.dig(:display_name) || "TikTok Ads account"
  end
end
