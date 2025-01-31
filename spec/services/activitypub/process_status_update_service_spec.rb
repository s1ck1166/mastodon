# frozen_string_literal: true

require 'rails_helper'

def poll_option_json(name, votes)
  { type: 'Note', name: name, replies: { type: 'Collection', totalItems: votes } }
end

RSpec.describe ActivityPub::ProcessStatusUpdateService, type: :service do
  subject { described_class.new }

  let(:thread) { nil }
  let!(:status) { Fabricate(:status, text: 'Hello world', account: Fabricate(:account, domain: 'example.com'), thread: thread) }
  let(:json_tags) do
    [
      { type: 'Hashtag', name: 'hoge' },
      { type: 'Mention', href: ActivityPub::TagManager.instance.uri_for(alice) },
    ]
  end
  let(:content) { 'Hello universe' }
  let(:payload) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: 'foo',
      type: 'Note',
      summary: 'Show more',
      content: content,
      updated: '2021-09-08T22:39:25Z',
      tag: json_tags,
    }
  end
  let(:payload_override) { {} }
  let(:json) { Oj.load(Oj.dump(payload.merge(payload_override))) }

  let(:alice) { Fabricate(:account) }
  let(:bob) { Fabricate(:account) }

  let(:mentions) { [] }
  let(:tags) { [] }
  let(:media_attachments) { [] }

  before do
    mentions.each { |a| Fabricate(:mention, status: status, account: a) }
    tags.each { |t| status.tags << t }
    media_attachments.each { |m| status.media_attachments << m }
  end

  describe '#call' do
    it 'updates text' do
      subject.call(status, json, json)
      expect(status.reload.text).to eq 'Hello universe'
    end

    it 'updates content warning' do
      subject.call(status, json, json)
      expect(status.reload.spoiler_text).to eq 'Show more'
    end

    context 'when the changes are only in sanitized-out HTML' do
      let!(:status) { Fabricate(:status, text: '<p>Hello world <a href="https://joinmastodon.org" rel="nofollow">joinmastodon.org</a></p>', account: Fabricate(:account, domain: 'example.com')) }

      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'foo',
          type: 'Note',
          updated: '2021-09-08T22:39:25Z',
          content: '<p>Hello world <a href="https://joinmastodon.org" rel="noreferrer">joinmastodon.org</a></p>',
        }
      end

      before do
        subject.call(status, json, json)
      end

      it 'does not create any edits' do
        expect(status.reload.edits).to be_empty
      end

      it 'does not mark status as edited' do
        expect(status.edited?).to be false
      end
    end

    context 'when the status has not been explicitly edited' do
      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'foo',
          type: 'Note',
          content: 'Updated text',
        }
      end

      before do
        subject.call(status, json, json)
      end

      it 'does not create any edits' do
        expect(status.reload.edits).to be_empty
      end

      it 'does not mark status as edited' do
        expect(status.reload.edited?).to be false
      end

      it 'does not update the text' do
        expect(status.reload.text).to eq 'Hello world'
      end
    end

    context 'when the status has not been explicitly edited and features a poll' do
      let(:account) { Fabricate(:account, domain: 'example.com') }
      let!(:expiration) { 10.days.from_now.utc }
      let!(:status) do
        Fabricate(:status,
                  text: 'Hello world',
                  account: account,
                  poll_attributes: {
                    options: %w(Foo Bar),
                    account: account,
                    multiple: false,
                    hide_totals: false,
                    expires_at: expiration,
                  })
      end

      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'https://example.com/foo',
          type: 'Question',
          content: 'Hello world',
          endTime: expiration.iso8601,
          oneOf: [
            poll_option_json('Foo', 4),
            poll_option_json('Bar', 3),
          ],
        }
      end

      before do
        subject.call(status, json, json)
      end

      it 'does not create any edits' do
        expect(status.reload.edits).to be_empty
      end

      it 'does not mark status as edited' do
        expect(status.reload.edited?).to be false
      end

      it 'does not update the text' do
        expect(status.reload.text).to eq 'Hello world'
      end

      it 'updates tallies' do
        expect(status.poll.reload.cached_tallies).to eq [4, 3]
      end
    end

    context 'when the status changes a poll despite being not explicitly marked as updated' do
      let(:account) { Fabricate(:account, domain: 'example.com') }
      let!(:expiration) { 10.days.from_now.utc }
      let!(:status) do
        Fabricate(:status,
                  text: 'Hello world',
                  account: account,
                  poll_attributes: {
                    options: %w(Foo Bar),
                    account: account,
                    multiple: false,
                    hide_totals: false,
                    expires_at: expiration,
                  })
      end

      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'https://example.com/foo',
          type: 'Question',
          content: 'Hello world',
          endTime: expiration.iso8601,
          oneOf: [
            poll_option_json('Foo', 4),
            poll_option_json('Bar', 3),
            poll_option_json('Baz', 3),
          ],
        }
      end

      before do
        subject.call(status, json, json)
      end

      it 'does not create any edits' do
        expect(status.reload.edits).to be_empty
      end

      it 'does not mark status as edited' do
        expect(status.reload.edited?).to be false
      end

      it 'does not update the text' do
        expect(status.reload.text).to eq 'Hello world'
      end

      it 'does not update tallies' do
        expect(status.poll.reload.cached_tallies).to eq [0, 0]
      end
    end

    context 'when receiving an edit older than the latest processed' do
      before do
        status.snapshot!(at_time: status.created_at, rate_limit: false)
        status.update!(text: 'Hello newer world', edited_at: Time.now.utc)
        status.snapshot!(rate_limit: false)
      end

      it 'does not create any edits' do
        expect { subject.call(status, json, json) }.to_not(change { status.reload.edits.pluck(&:id) })
      end

      it 'does not update the text, spoiler_text or edited_at' do
        expect { subject.call(status, json, json) }
          .to_not(change { status.reload.attributes.slice('text', 'spoiler_text', 'edited_at').values })
      end
    end

    context 'with no changes at all' do
      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'foo',
          type: 'Note',
          content: 'Hello world',
        }
      end

      before do
        subject.call(status, json, json)
      end

      it 'does not create any edits' do
        expect(status.reload.edits).to be_empty
      end

      it 'does not mark status as edited' do
        expect(status.edited?).to be false
      end
    end

    context 'with no changes and originally with no ordered_media_attachment_ids' do
      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'foo',
          type: 'Note',
          content: 'Hello world',
        }
      end

      before do
        status.update(ordered_media_attachment_ids: nil)
        subject.call(status, json, json)
      end

      it 'does not create any edits' do
        expect(status.reload.edits).to be_empty
      end

      it 'does not mark status as edited' do
        expect(status.edited?).to be false
      end
    end

    context 'when originally without tags' do
      before do
        subject.call(status, json, json)
      end

      it 'updates tags' do
        expect(status.tags.reload.map(&:name)).to eq %w(hoge)
      end
    end

    context 'when originally with tags' do
      let(:tags) { [Fabricate(:tag, name: 'test'), Fabricate(:tag, name: 'foo')] }

      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'foo',
          type: 'Note',
          summary: 'Show more',
          content: 'Hello universe',
          updated: '2021-09-08T22:39:25Z',
          tag: [
            { type: 'Hashtag', name: 'foo' },
          ],
        }
      end

      before do
        subject.call(status, json, json)
      end

      it 'updates tags' do
        expect(status.tags.reload.map(&:name)).to eq %w(foo)
      end
    end

    context 'when reject tags by domain-block' do
      let(:tags) { [Fabricate(:tag, name: 'hoge'), Fabricate(:tag, name: 'ohagi')] }

      before do
        Fabricate(:domain_block, domain: 'example.com', severity: :noop, reject_hashtag: true)
        subject.call(status, json, json)
      end

      it 'updates tags' do
        expect(status.tags.reload.map(&:name)).to eq []
      end
    end

    context 'when reject mentions to stranger by domain-block' do
      let(:json_tags) do
        [
          { type: 'Mention', href: ActivityPub::TagManager.instance.uri_for(alice) },
        ]
      end

      before do
        Fabricate(:domain_block, domain: 'example.com', reject_reply_exclude_followers: true, severity: :noop)
      end

      it 'updates mentions' do
        subject.call(status, json, json)

        expect(status.mentions.reload.map(&:account_id)).to eq []
      end

      it 'updates mentions when follower' do
        alice.follow!(status.account)
        subject.call(status, json, json)

        expect(status.mentions.reload.map(&:account_id)).to eq [alice.id]
      end
    end

    context 'when originally without mentions' do
      before do
        subject.call(status, json, json)
      end

      it 'updates mentions' do
        expect(status.active_mentions.reload.map(&:account_id)).to eq [alice.id]
      end
    end

    context 'when originally with mentions' do
      let(:mentions) { [alice, bob] }

      before do
        subject.call(status, json, json)
      end

      it 'updates mentions' do
        expect(status.active_mentions.reload.map(&:account_id)).to eq [alice.id]
      end
    end

    context 'when originally without media attachments' do
      before do
        stub_request(:get, 'https://example.com/foo.png').to_return(body: attachment_fixture('emojo.png'))
        subject.call(status, json, json)
      end

      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'foo',
          type: 'Note',
          content: 'Hello universe',
          updated: '2021-09-08T22:39:25Z',
          attachment: [
            { type: 'Image', mediaType: 'image/png', url: 'https://example.com/foo.png' },
          ],
        }
      end

      it 'updates media attachments' do
        media_attachment = status.reload.ordered_media_attachments.first

        expect(media_attachment).to_not be_nil
        expect(media_attachment.remote_url).to eq 'https://example.com/foo.png'
      end

      it 'fetches the attachment' do
        expect(a_request(:get, 'https://example.com/foo.png')).to have_been_made
      end

      it 'records media change in edit' do
        expect(status.edits.reload.last.ordered_media_attachment_ids).to_not be_empty
      end
    end

    context 'when originally with media attachments' do
      let(:media_attachments) { [Fabricate(:media_attachment, remote_url: 'https://example.com/foo.png'), Fabricate(:media_attachment, remote_url: 'https://example.com/unused.png')] }

      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'foo',
          type: 'Note',
          content: 'Hello universe',
          updated: '2021-09-08T22:39:25Z',
          attachment: [
            { type: 'Image', mediaType: 'image/png', url: 'https://example.com/foo.png', name: 'A picture' },
          ],
        }
      end

      before do
        allow(RedownloadMediaWorker).to receive(:perform_async)
        subject.call(status, json, json)
      end

      it 'updates the existing media attachment in-place' do
        media_attachment = status.media_attachments.ordered.reload.first

        expect(media_attachment).to_not be_nil
        expect(media_attachment.remote_url).to eq 'https://example.com/foo.png'
        expect(media_attachment.description).to eq 'A picture'
      end

      it 'does not queue redownload for the existing media attachment' do
        expect(RedownloadMediaWorker).to_not have_received(:perform_async)
      end

      it 'updates media attachments' do
        expect(status.ordered_media_attachments.map(&:remote_url)).to eq %w(https://example.com/foo.png)
      end

      it 'records media change in edit' do
        expect(status.edits.reload.last.ordered_media_attachment_ids).to_not be_empty
      end
    end

    context 'when originally with a poll' do
      before do
        poll = Fabricate(:poll, status: status)
        status.update(preloadable_poll: poll)
        subject.call(status, json, json)
      end

      it 'removes poll' do
        expect(status.reload.poll).to be_nil
      end

      it 'records media change in edit' do
        expect(status.edits.reload.last.poll_options).to be_nil
      end
    end

    context 'when originally without a poll' do
      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'foo',
          type: 'Question',
          content: 'Hello universe',
          updated: '2021-09-08T22:39:25Z',
          closed: true,
          oneOf: [
            { type: 'Note', name: 'Foo' },
            { type: 'Note', name: 'Bar' },
            { type: 'Note', name: 'Baz' },
          ],
        }
      end

      before do
        subject.call(status, json, json)
      end

      it 'creates a poll' do
        poll = status.reload.poll

        expect(poll).to_not be_nil
        expect(poll.options).to eq %w(Foo Bar Baz)
      end

      it 'records media change in edit' do
        expect(status.edits.reload.last.poll_options).to eq %w(Foo Bar Baz)
      end
    end

    it 'creates edit history' do
      subject.call(status, json, json)
      expect(status.edits.reload.map(&:text)).to eq ['Hello world', 'Hello universe']
    end

    it 'sets edited timestamp' do
      subject.call(status, json, json)
      expect(status.reload.edited_at.to_s).to eq '2021-09-08 22:39:25 UTC'
    end

    describe 'ng word is set' do
      let(:json_tags) { [] }

      context 'when hit ng words' do
        let(:content) { 'ng word test' }

        it 'update status' do
          Form::AdminSettings.new(ng_words: 'test').save

          subject.call(status, json, json)
          expect(status.reload.text).to_not eq content
        end
      end

      context 'when not hit ng words' do
        let(:content) { 'ng word aiueo' }

        it 'update status' do
          Form::AdminSettings.new(ng_words: 'test').save

          subject.call(status, json, json)
          expect(status.reload.text).to eq content
        end
      end

      context 'when hit ng words for mention to local stranger' do
        let(:json_tags) do
          [
            { type: 'Mention', href: ActivityPub::TagManager.instance.uri_for(alice) },
          ]
        end
        let(:content) { 'ng word test' }

        it 'update status' do
          Form::AdminSettings.new(ng_words_for_stranger_mention: 'test', stranger_mention_from_local_ng: '1').save

          subject.call(status, json, json)
          expect(status.reload.text).to_not eq content
          expect(status.mentioned_accounts.pluck(:id)).to_not include alice.id
        end

        it 'update status when following' do
          Form::AdminSettings.new(ng_words_for_stranger_mention: 'test', stranger_mention_from_local_ng: '1').save
          alice.follow!(status.account)

          subject.call(status, json, json)
          expect(status.reload.text).to eq content
          expect(status.mentioned_accounts.pluck(:id)).to include alice.id
        end
      end

      context 'when hit ng words for mention but local posts are not checked' do
        let(:json_tags) do
          [
            { type: 'Mention', href: ActivityPub::TagManager.instance.uri_for(alice) },
          ]
        end
        let(:content) { 'ng word test' }

        it 'update status' do
          Form::AdminSettings.new(ng_words_for_stranger_mention: 'test', stranger_mention_from_local_ng: '0').save

          subject.call(status, json, json)
          expect(status.reload.text).to_not eq content
          expect(status.mentioned_accounts.pluck(:id)).to_not include alice.id
        end
      end

      context 'when hit ng words for mention to follower' do
        let(:json_tags) do
          [
            { type: 'Mention', href: ActivityPub::TagManager.instance.uri_for(alice) },
          ]
        end
        let(:content) { 'ng word test' }

        before do
          alice.follow!(status.account)
        end

        it 'update status' do
          Form::AdminSettings.new(ng_words_for_stranger_mention: 'test').save

          subject.call(status, json, json)
          expect(status.reload.text).to eq content
          expect(status.mentioned_accounts.pluck(:id)).to include alice.id
        end
      end

      context 'when hit ng words for reply' do
        let(:json_tags) do
          [
            { type: 'Mention', href: ActivityPub::TagManager.instance.uri_for(alice) },
          ]
        end
        let(:content) { 'ng word test' }
        let(:thread) { Fabricate(:status, account: alice) }

        it 'update status' do
          Form::AdminSettings.new(ng_words_for_stranger_mention: 'test').save

          subject.call(status, json, json)
          expect(status.reload.text).to_not eq content
          expect(status.mentioned_accounts.pluck(:id)).to_not include alice.id
        end
      end

      context 'when hit ng words for reply to follower' do
        let(:json_tags) do
          [
            { type: 'Mention', href: ActivityPub::TagManager.instance.uri_for(alice) },
          ]
        end
        let(:content) { 'ng word test' }
        let(:thread) { Fabricate(:status, account: alice) }

        before do
          alice.follow!(status.account)
        end

        it 'update status' do
          Form::AdminSettings.new(ng_words_for_stranger_mention: 'test').save

          subject.call(status, json, json)
          expect(status.reload.text).to eq content
          expect(status.mentioned_accounts.pluck(:id)).to include alice.id
        end
      end

      context 'when hit ng words for reference' do
        let!(:target_status) { Fabricate(:status, account: alice) }
        let(:payload_override) do
          {
            references: {
              id: 'target_status',
              type: 'Collection',
              first: {
                type: 'CollectionPage',
                next: nil,
                partOf: 'target_status',
                items: [
                  ActivityPub::TagManager.instance.uri_for(target_status),
                ],
              },
            },
          }
        end
        let(:content) { 'ng word test' }

        it 'update status' do
          Form::AdminSettings.new(ng_words_for_stranger_mention: 'test', stranger_mention_from_local_ng: '1').save

          subject.call(status, json, json)
          expect(status.reload.text).to_not eq content
          expect(status.references.pluck(:id)).to_not include target_status.id
        end

        context 'when alice follows sender' do
          before do
            alice.follow!(status.account)
          end

          it 'update status' do
            Form::AdminSettings.new(ng_words_for_stranger_mention: 'test').save

            subject.call(status, json, json)
            expect(status.reload.text).to eq content
            expect(status.references.pluck(:id)).to include target_status.id
          end
        end
      end

      context 'when using hashtag under limit' do
        let(:json_tags) do
          [
            { type: 'Hashtag', name: 'a' },
            { type: 'Hashtag', name: 'b' },
          ]
        end
        let(:content) { 'ohagi is good' }

        it 'update status' do
          Form::AdminSettings.new(post_hash_tags_max: 2).save

          subject.call(status, json, json)
          expect(status.reload.text).to eq content
        end
      end

      context 'when using hashtag over limit' do
        let(:json_tags) do
          [
            { type: 'Hashtag', name: 'a' },
            { type: 'Hashtag', name: 'b' },
            { type: 'Hashtag', name: 'c' },
          ]
        end
        let(:content) { 'ohagi is good' }

        it 'update status' do
          Form::AdminSettings.new(post_hash_tags_max: 2).save

          subject.call(status, json, json)
          expect(status.reload.text).to_not eq content
        end
      end
    end

    describe 'ng rule is set' do
      context 'when ng rule is match' do
        before do
          Fabricate(:ng_rule, account_domain: 'example.com', status_text: 'universe')
          subject.call(status, json, json)
        end

        it 'does not update text' do
          expect(status.reload.text).to eq 'Hello world'
          expect(status.edits.reload.map(&:text)).to eq []
        end
      end

      context 'when ng rule is not match' do
        before do
          Fabricate(:ng_rule, account_domain: 'foo.bar', status_text: 'universe')
          subject.call(status, json, json)
        end

        it 'updates text' do
          expect(status.reload.text).to eq 'Hello universe'
          expect(status.edits.reload.map(&:text)).to eq ['Hello world', 'Hello universe']
        end
      end
    end

    describe 'sensitive word is set' do
      let(:payload) do
        {
          '@context': 'https://www.w3.org/ns/activitystreams',
          id: 'foo',
          type: 'Note',
          content: content,
          updated: '2021-09-08T22:39:25Z',
          tag: json_tags,
        }
      end

      context 'when hit sensitive words' do
        let(:content) { 'ng word aiueo' }

        it 'update status' do
          Form::AdminSettings.new(sensitive_words_all: 'test').save

          subject.call(status, json, json)
          expect(status.reload.text).to eq content
          expect(status.spoiler_text).to eq ''
        end
      end

      context 'when not hit sensitive words' do
        let(:content) { 'ng word test' }

        it 'update status' do
          Form::AdminSettings.new(sensitive_words_all: 'test').save

          subject.call(status, json, json)
          expect(status.reload.text).to eq content
          expect(status.spoiler_text).to_not eq ''
        end
      end
    end
  end
end
