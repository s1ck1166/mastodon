# frozen_string_literal: true

class REST::InstanceSerializer < ActiveModel::Serializer
  class ContactSerializer < ActiveModel::Serializer
    attributes :email

    has_one :account, serializer: REST::AccountSerializer
  end

  include RoutingHelper
  include KmyblueCapabilitiesHelper
  include RegistrationLimitationHelper

  attributes :domain, :title, :version, :source_url, :description,
             :usage, :thumbnail, :languages, :configuration,
             :registrations, :fedibird_capabilities

  has_one :contact, serializer: ContactSerializer
  has_many :rules, serializer: REST::RuleSerializer

  def thumbnail
    if object.thumbnail
      {
        url: full_asset_url(object.thumbnail.file.url(:'@1x')),
        blurhash: object.thumbnail.blurhash,
        versions: {
          '@1x': full_asset_url(object.thumbnail.file.url(:'@1x')),
          '@2x': full_asset_url(object.thumbnail.file.url(:'@2x')),
        },
      }
    else
      {
        url: frontend_asset_url('images/preview.png'),
      }
    end
  end

  def usage
    {
      users: {
        active_month: object.active_user_count(4),
      },
    }
  end

  def configuration
    {
      urls: {
        streaming: Rails.configuration.x.streaming_api_base_url,
        status: object.status_page_url,
      },

      vapid: {
        public_key: Rails.configuration.x.vapid_public_key,
      },

      accounts: {
        max_featured_tags: FeaturedTag::LIMIT,
      },

      statuses: {
        max_characters: StatusLengthValidator::MAX_CHARS,
        max_media_attachments: MediaAttachment::LOCAL_STATUS_ATTACHMENT_MAX,
        max_media_attachments_with_poll: MediaAttachment::LOCAL_STATUS_ATTACHMENT_MAX_WITH_POLL,
        max_media_attachments_from_activitypub: MediaAttachment::ACTIVITYPUB_STATUS_ATTACHMENT_MAX,
        characters_reserved_per_url: StatusLengthValidator::URL_PLACEHOLDER_CHARS,
      },

      media_attachments: {
        supported_mime_types: MediaAttachment::IMAGE_MIME_TYPES + MediaAttachment::VIDEO_MIME_TYPES + MediaAttachment::AUDIO_MIME_TYPES,
        image_size_limit: MediaAttachment::IMAGE_LIMIT,
        image_matrix_limit: Attachmentable::MAX_MATRIX_LIMIT,
        video_size_limit: MediaAttachment::VIDEO_LIMIT,
        video_frame_rate_limit: MediaAttachment::MAX_VIDEO_FRAME_RATE,
        video_matrix_limit: MediaAttachment::MAX_VIDEO_MATRIX_LIMIT,
      },

      polls: {
        max_options: PollValidator::MAX_OPTIONS,
        max_characters_per_option: PollValidator::MAX_OPTION_CHARS,
        min_expiration: PollValidator::MIN_EXPIRATION,
        max_expiration: PollValidator::MAX_EXPIRATION,
        allow_image: true,
      },

      translation: {
        enabled: TranslationService.configured?,
      },

      emoji_reactions: {
        max_reactions: EmojiReaction::EMOJI_REACTION_LIMIT,
        max_reactions_per_account: EmojiReaction::EMOJI_REACTION_PER_ACCOUNT_LIMIT,
        max_reactions_per_remote_account: EmojiReaction::EMOJI_REACTION_PER_REMOTE_ACCOUNT_LIMIT,
      },

      reaction_deck: {
        max_emojis: User::REACTION_DECK_MAX,
      },

      reactions: {
        max_reactions: EmojiReaction::EMOJI_REACTION_PER_ACCOUNT_LIMIT,
      },

      # https://github.com/mastodon/mastodon/pull/27009
      search: {
        enabled: Chewy.enabled?,
      },
    }
  end

  def registrations
    {
      enabled: registrations_enabled?,
      approval_required: Setting.registrations_mode == 'approved' || (Setting.registrations_mode == 'open' && !registrations_in_time?),
      limit_reached: Setting.registrations_mode != 'none' && reach_registrations_limit?,
      message: registrations_enabled? ? nil : registrations_message,
      url: ENV.fetch('SSO_ACCOUNT_SIGN_UP', nil),
    }
  end

  private

  def registrations_enabled?
    Setting.registrations_mode != 'none' && !reach_registrations_limit? && !Rails.configuration.x.single_user_mode
  end

  def registrations_message
    markdown.render(Setting.closed_registrations_message) if Setting.closed_registrations_message.present?
  end

  def markdown
    @markdown ||= Redcarpet::Markdown.new(Redcarpet::Render::HTML, no_images: true)
  end
end
