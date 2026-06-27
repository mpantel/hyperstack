# frozen_string_literal: true

require "spec_helper"

describe "ActiveRecord::ClassMethods", js: true do
  context "method_missing" do
    it "should return a TypeError if name is nil" do
      expect_evaluate_ruby do
        error = nil

        begin
          User.send(nil)
        rescue StandardError => e
          error = e
        end

        error
      end.to eq("User is not a symbol nor a string")
    end

    # Issue #23: under Opal 1.8 model class load reaches method_missing for
    # server-only macros (e.g. :regulate_scope) *before* the first mount, while
    # `public_columns_hash` is still nil. The generic attribute-accessor heuristic
    # used to match the macro name and prematurely run define_attribute_methods
    # (flipping @hyperstack_tried_define_methods), which both crashed in
    # columns_hash and blocked the real definition once columns finally loaded.
    # Excluding SERVER_METHODS from the heuristic makes server macros silent
    # no-ops on the client, so the flag is never set by such a call.
    it "does not trigger premature attribute-method definition for a server-only macro (issue #23)" do
      expect_evaluate_ruby do
        saved = User.instance_variable_get(:@hyperstack_tried_define_methods)
        User.instance_variable_set(:@hyperstack_tried_define_methods, nil)
        begin
          User.regulate_scope(:dummy_scope) rescue nil
          # post-fix: the SERVER_METHODS exclusion skips the define branch, so the
          # flag remains unset; pre-fix it would have been set to true here.
          User.instance_variable_get(:@hyperstack_tried_define_methods)
        ensure
          User.instance_variable_set(:@hyperstack_tried_define_methods, saved)
        end
      end.to be_nil
    end
  end

  context "columns_hash" do
    # Issue #23: model class load can reach columns_hash before before_first_mount
    # populates ReactiveRecord::Base.public_columns_hash. The lookup must tolerate a
    # nil public_columns_hash (returning {}) instead of raising
    # `undefined method '[]' for nil`, which previously cascaded into the <Pager>
    # `to_sym for nil` render crash.
    it "returns {} instead of raising when public_columns_hash is nil (issue #23)" do
      expect_evaluate_ruby do
        saved = ReactiveRecord::Base.instance_variable_get(:@public_columns_hash)
        ReactiveRecord::Base.instance_variable_set(:@public_columns_hash, nil)
        begin
          result = User.columns_hash
          [result.is_a?(Hash), result.empty?]
        ensure
          ReactiveRecord::Base.instance_variable_set(:@public_columns_hash, saved)
        end
      end.to eq([true, true])
    end
  end
end
