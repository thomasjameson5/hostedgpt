class Tiktok::ApplicationController < ApplicationController
  before_action :ensure_feature_enabled

  layout "tiktok"

  private

  def ensure_feature_enabled
    redirect_to root_path, alert: "TikTok tools aren't enabled" unless Feature.tiktok_tools?
  end
end
