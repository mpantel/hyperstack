require 'spec_helper'

# Regression coverage for #91.
#
# WarningFilter exists to drop Ruby 3.4 chilled-string deprecations coming from
# three unmaintained gems in the test toolchain. It was matching only one of the
# two messages Ruby emits for chilled strings:
#
#   string returned by :foo.to_s will be frozen in the future   <- was matched
#   literal string will be frozen in the future                 <- was not
#
# The unmatched one is the flood. On a single hyper-model job it accounted for
# 1727 of 2454 trace lines -- 892 from em-websocket's framing07.rb, 821 from its
# masking04.rb, 14 from unicode_utils -- so the filter looked installed and
# working while the logs it was written to clean were still 70% noise.
#
# The examples below drive the module directly rather than through the global
# Warning, so they assert on what is filtered without suppressing anything for
# the rest of the suite. Half of them are negative: a filter that is too wide is
# a worse bug than one that is too narrow, because it swallows real deprecations.
describe HyperSpec::WarningFilter do
  # Warning.warn's contract: return without calling super to swallow the line.
  # Standing in for the real Warning lets us see which lines would survive.
  let(:emitted) { [] }

  let(:warner) do
    recorder = emitted
    sink = Module.new do
      define_method(:warn) { |message, category: nil| recorder << message }
    end
    Object.new.tap do |o|
      o.extend(sink)
      o.extend(described_class)
    end
  end

  def filtered?(message)
    emitted.clear
    warner.warn(message)
    emitted.empty?
  end

  gems = '/somewhere/local_gems/ruby/3.4.0/gems'
  em_websocket = "#{gems}/em-websocket-0.5.3/lib/em-websocket"
  frozen = 'warning: literal string will be frozen in the future'

  describe 'the chilled-string deprecations it exists to drop' do
    it 'drops the literal-string form, which is the whole flood' do
      # the two call sites that produced 1713 of the 1727 lines
      expect(filtered?("#{em_websocket}/framing07.rb:135: #{frozen} " \
                       '(run with --debug-frozen-string-literal for more information)')).to be true
      expect(filtered?("#{em_websocket}/masking04.rb:29: #{frozen}")).to be true
    end

    it 'drops it for every gem on the list, not just em-websocket' do
      expect(filtered?("#{gems}/unicode_utils-1.4.0/lib/unicode_utils/read_cdata.rb:124: #{frozen}"))
        .to be true
      expect(filtered?("#{gems}/parser-3.3.0.5/lib/parser/lexer.rb:10: #{frozen}")).to be true
    end

    it 'still drops the Symbol#to_s form it already handled' do
      expect(filtered?("#{gems}/parser-3.3.0.5/lib/parser/lexer.rb:10: " \
                       'warning: string returned by :foo.to_s will be frozen in the future'))
        .to be true
    end
  end

  describe 'what it must never swallow' do
    it 'keeps the same warning when it comes from Hyperstack itself' do
      # the point of the gem guard: our own chilled-string bugs stay visible
      expect(filtered?("/hyperstack/ruby/hyper-model/lib/reactive_record/base.rb:9: #{frozen}"))
        .to be false
    end

    it 'keeps it for a gem that is not on the list' do
      expect(filtered?("#{gems}/rails-8.1.3.1/lib/rails.rb:1: #{frozen}")).to be false
    end

    it 'keeps unrelated warnings from a gem that is on the list' do
      expect(filtered?("#{em_websocket}/framing07.rb:135: " \
                       'warning: method redefined; discarding old handler')).to be false
    end

    it 'keeps other gems deprecations' do
      expect(filtered?("#{gems}/pg-1.6.2/lib/pg/coder.rb:1: " \
                       'warning: PG::Coder.new(hash) is deprecated')).to be false
    end

    it 'ignores a non-String message rather than raising on it' do
      # Warning.warn is documented as taking a String, but nothing enforces it
      expect { warner.warn(:not_a_string) }.not_to raise_error
      expect(emitted).to eq([:not_a_string])
    end
  end
end
