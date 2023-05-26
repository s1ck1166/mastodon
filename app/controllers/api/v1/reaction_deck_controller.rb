# frozen_string_literal: true

class Api::V1::ReactionDeckController < Api::BaseController
  include RoutingHelper

  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:index]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, only: [:create]

  before_action :require_user!
  before_action :set_deck, only: [:index, :create]

  rescue_from ArgumentError do |e|
    render json: { error: e.to_s }, status: 422
  end

  def index
    render json: remove_metas(@deck)
  end

  def create
    deck = @deck

    (deck_params['emojis'] || []).each do |data|
      raise ArgumentError if data['id'].to_i >= 16 || data['id'].to_i.negative?

      shortcode = data['emoji'].delete(':')
      custom_emoji = CustomEmoji.find_by(shortcode: shortcode, domain: nil)

      old = deck.find { |dd| dd['id'] == data['id'] }
      emoji_data = old || { 'id' => data['id'] }

      if custom_emoji
        emoji_data['name'] = custom_emoji.shortcode
        emoji_data['url'] = full_asset_url(custom_emoji.image.url)
        emoji_data['static_url'] = full_asset_url(custom_emoji.image.url(:static))
        emoji_data['width'] = custom_emoji.image_width
        emoji_data['height'] = custom_emoji.image_height
        emoji_data['custom_emoji_id'] = custom_emoji.id
      else
        emoji_data['name'] = shortcode
      end

      deck << emoji_data if old.nil?
    end

    deck = deck.sort_by { |a| a['id'].to_i }
    current_user.settings['reaction_deck'] = deck.to_json
    current_user.save!

    render json: remove_metas(deck)
  end

  private

  def set_deck
    deck = current_user.setting_reaction_deck ? JSON.parse(current_user.setting_reaction_deck) : []
    @deck = remove_unused_custom_emojis(deck)
  end

  def remove_unused_custom_emojis(deck)
    custom_ids = []
    deck.each do |item|
      custom_ids << item['custom_emoji_id'].to_i if item.key?('custom_emoji_id')
    end
    custom_emojis = CustomEmoji.where(id: custom_ids)

    deck.each do |item|
      next if item['custom_emoji_id'].nil?

      custom_emoji = custom_emojis.find { |em| em.id == item['custom_emoji_id'].to_i }
      remove = custom_emoji.nil? || custom_emoji.disabled
      item['remove'] = remove if remove
    end
    deck.filter { |item| !item.key?('remove') }
  end

  def remove_metas(deck)
    deck.tap do |d|
      d.each do |item|
        item.delete('custom_emoji_id')
      end
    end
  end

  def deck_params
    params
  end
end