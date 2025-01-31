# frozen_string_literal: true

class Api::V1::Timelines::PublicController < Api::V1::Timelines::BaseController
  before_action :require_user!, only: [:show], if: :require_auth?

  PERMITTED_PARAMS = %i(local remote limit only_media).freeze

  def show
    cache_if_unauthenticated!
    @statuses = load_statuses
    render json: @statuses, each_serializer: REST::StatusSerializer,
           relationships: StatusRelationshipsPresenter.new(@statuses, current_user&.account_id),
           emoji_reaction_permitted_account_ids: EmojiReactionAccountsPresenter.new(@statuses, current_user&.account_id)
  end

  private

  def require_auth?
    !Setting.timeline_preview
  end

  def load_statuses
    cached_public_statuses_page
  end

  def cached_public_statuses_page
    cache_collection(public_statuses, Status)
  end

  def public_statuses
    public_feed.get(
      limit_param(DEFAULT_STATUSES_LIMIT),
      params[:max_id],
      params[:since_id],
      params[:min_id]
    )
  end

  def public_feed
    PublicFeed.new(
      current_account,
      local: truthy_param?(:local),
      remote: truthy_param?(:remote),
      only_media: truthy_param?(:only_media)
    )
  end

  def next_path
    api_v1_timelines_public_url next_path_params
  end

  def prev_path
    api_v1_timelines_public_url prev_path_params
  end
end
