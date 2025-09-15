# frozen_string_literal: true

require 'spec_helper'
require 'ears/testing'
require 'ears/testing/message_capture'
require 'ears/testing/matchers'

RSpec.describe Ears::Testing::Matchers do
  include Ears::Testing::Matchers

  let(:message_capture) { Ears::Testing::MessageCapture.new }

  before do
    allow(Ears::Testing).to receive(:message_capture).and_return(
      message_capture,
    )
  end

  context 'when no messages are published' do
    it 'fails positive expectations' do
      expect {
        expect(routing_key: 'orders.created').to have_been_published
      }.to raise_error(
        RSpec::Expectations::ExpectationNotMetError,
        /expected a message/,
      )
    end

    it 'passes negative expectations' do
      expect(routing_key: 'orders.created').not_to have_been_published
    end
  end

  context 'when messages are published' do
    let(:messages) do
      [
        Ears::Testing::MessageCapture::Message.new(
          routing_key: 'orders.created',
          data: {
            'id' => 1,
          },
          options: {
            app_id: 'test-app',
          },
        ),
        Ears::Testing::MessageCapture::Message.new(
          routing_key: 'orders.updated',
          data: {
            'id' => 2,
          },
          options: {
            app_id: 'test-app',
          },
        ),
      ]
    end

    before do
      allow(message_capture).to receive(:all_messages).and_return(messages)
    end

    it 'matches by routing_key' do
      expect(routing_key: 'orders.created').to have_been_published
      expect(routing_key: 'orders.updated').to have_been_published
    end

    it 'matches by data' do
      expect(data: { 'id' => 1 }).to have_been_published
    end

    it 'matches by options' do
      expect(options: { app_id: 'test-app' }).to have_been_published
    end

    it 'matches by multiple attributes' do
      expect(
        routing_key: 'orders.created',
        data: {
          'id' => 1,
        },
        options: {
          app_id: 'test-app',
        },
      ).to have_been_published
    end

    it 'fails when routing_key does not match' do
      expect {
        expect(routing_key: 'orders.deleted').to have_been_published
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it 'fails when data does not match' do
      expect {
        expect(
          routing_key: 'orders.created',
          data: {
            'id' => 99,
          },
        ).to have_been_published
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it 'fails when options do not match' do
      expect {
        expect(
          routing_key: 'orders.created',
          options: {
            app_id: 'other-app',
          },
        ).to have_been_published
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it 'fails when negated but message matches' do
      expect {
        expect(routing_key: 'orders.created').not_to have_been_published
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end

  context 'when exchange_name is specified' do
    let(:messages) do
      [
        Ears::Testing::MessageCapture::Message.new(
          routing_key: 'stuff.created',
          data: {
            'id' => 1,
          },
          options: {
          },
          exchange_name: 'stuff',
        ),
        Ears::Testing::MessageCapture::Message.new(
          routing_key: 'other_stuff.received',
          data: {
            'id' => 42,
          },
          options: {
          },
          exchange_name: 'other stuff',
        ),
      ]
    end

    before do
      allow(message_capture).to receive(:messages_for).with(
        'orders',
      ).and_return([messages[0]])
      allow(message_capture).to receive(:messages_for).with(
        'payments',
      ).and_return([messages[1]])
      allow(message_capture).to receive(:all_messages).and_return(messages)
    end

    it 'matches only messages from the specified exchange' do
      expect(
        routing_key: 'stuff.created',
        exchange_name: 'orders',
      ).to have_been_published
      expect(
        routing_key: 'other_stuff.received',
        exchange_name: 'payments',
      ).to have_been_published
    end

    it 'does not match if the routing_key exists but in another exchange' do
      expect {
        expect(
          routing_key: 'payments.received',
          exchange_name: 'orders',
        ).to have_been_published
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end
end
