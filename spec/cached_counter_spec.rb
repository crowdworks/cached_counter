require 'spec_helper'

require 'dalli'

require 'cached_counter'

RSpec.describe CachedCounter do
  before(:each) do
    load 'setup/articles_with_delayed_jobs.rb'

    CachedCounter.cache_store :dalli, hosts: %w| 127.0.0.1 |
  end

  after :each do
    ActiveRecord::Schema.define(:version => 2) do
      drop_table :delayed_jobs
      drop_table :articles
    end
  end

  let(:cache_store) { CachedCounter.cache_store.call }
  let(:cached_counter) { CachedCounter.create(record: record, attribute: :num_read, cache_store: cache_store) }
  let(:record) { Article.first }

  subject { cached_counter }

  before do
    cached_counter.invalidate_cache
  end

  describe '#increment' do
    subject { -> { cached_counter.increment } }

    it { is_expected.to change { cached_counter.value }.by(1) }
    it { is_expected.not_to change { record.num_read} }
    it { is_expected.to change { record.reload.num_read }.by(1) }

    context 'when the surrounding transaction rolled-back' do
      subject { -> { transaction }}

      let(:transaction) {
        begin
          Article.transaction do
            cached_counter.increment

            fail 'simulated error'
          end
        rescue
          ;
        end
      }

      it { is_expected.not_to change { cached_counter.value } }
      it { is_expected.not_to change { record.num_read } }
      it { is_expected.not_to change { record.reload.num_read } }
    end

    context 'when the cache is updated concurrently' do
      before do
        expect(cache_store).to receive(:incr).and_return(false)
        expect(cache_store).to receive(:add).and_return(false)
      end

      subject { -> { cached_counter.increment } }

      it { is_expected.to raise_error(CachedCounter::ConcurrentCacheWriteError)}
    end
  end

  describe '#decrement' do
    subject { -> { cached_counter.decrement } }

    it { is_expected.to change { cached_counter.value }.by(-1) }
    it { is_expected.not_to change { record.num_read} }
    it { is_expected.to change { record.reload.num_read }.by(-1) }

    context 'when the surrounding transaction rolled-back' do
      subject { -> { transaction }}

      let(:transaction) {
        begin
          Article.transaction do
            cached_counter.decrement

            fail 'simulated error'
          end
        rescue
          ;
        end
      }

      it { is_expected.not_to change { cached_counter.value } }
      it { is_expected.not_to change { record.num_read } }
      it { is_expected.not_to change { record.reload.num_read } }
    end

    context 'when the cache is updated concurrently' do
      before do
        expect(cache_store).to receive(:decr).and_return(false)
        expect(cache_store).to receive(:add).and_return(false)
      end

      subject { -> { cached_counter.decrement } }

      it { is_expected.to raise_error(CachedCounter::ConcurrentCacheWriteError)}
    end
  end

  context 'when the cache_store is not specified' do
    let(:cache_store) { nil }

    describe '#increment' do
      subject { -> { cached_counter.increment } }

      it { is_expected.to change { cached_counter.value }.by(1) }
      it { is_expected.not_to change { record.num_read} }
      it { is_expected.to change { record.reload.num_read }.by(1) }
    end
  end
end
