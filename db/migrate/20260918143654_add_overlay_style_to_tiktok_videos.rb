class AddOverlayStyleToTiktokVideos < ActiveRecord::Migration[7.1]
  def change
    add_column :tiktok_videos, :overlay_style, :string, default: "classic", null: false
    add_column :tiktok_videos, :overlay_position, :string, default: "bottom", null: false
  end
end
