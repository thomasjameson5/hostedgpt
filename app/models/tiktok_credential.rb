class TiktokCredential < Credential
  alias_attribute :open_id, :external_id

  validates :oauth_token, presence: true
  validates :oauth_refresh_token, presence: true
  validates :open_id, presence: true, uniqueness: true

  has_many :tiktok_videos, dependent: :destroy

  def display_name
    properties&.dig(:display_name) || properties&.dig(:username) || "TikTok account"
  end

  def username
    properties&.dig(:username)
  end

  def avatar_url
    properties&.dig(:avatar_url)
  end
end
