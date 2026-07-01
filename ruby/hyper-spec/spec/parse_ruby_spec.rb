require 'spec_helper'

# Regression coverage for #35: HyperSpec.parse_ruby (used by add_opal_block,
# run_on_client and add_block_with_helpers to Opal-compile spec-authored
# mount/evaluate_ruby blocks) must keep producing Unparser-compatible
# Parser::AST::Node trees now that it's backed by Prism::Translation::Parser
# instead of the no-longer-maintained Parser::CurrentRuby.
describe 'HyperSpec.parse_ruby' do
  def unparsed(source)
    Unparser.unparse(HyperSpec.parse_ruby(source))
  end

  it 'parses a plain block with string interpolation' do
    expect(unparsed('proc { |x| "hi #{x}" }')).to eq("proc { |x|\n  \"hi \#{x}\"\n}")
  end

  it 'parses keyword and double-splat block arguments' do
    expect(unparsed('lambda { |a, b: 1, **rest| a + b }'))
      .to eq("lambda { |a, b: 1, **rest|\n  a + b\n}")
  end

  it 'parses pattern matching (case/in)' do
    expect(unparsed('proc { case 1; in Integer => n; n; end }'))
      .to eq("proc {\n  case 1\n  in Integer => n then\n    n\n  end\n}")
  end

  it 'parses index op-assign back to subscript syntax, not a bare send (regression, #35)' do
    # Prism::Translation::Parser::Builder subclasses Parser::Builders::Default
    # but does not inherit its emit_* class-level flags; without setting them
    # separately (see hyper-spec.rb), this unparses as the invalid
    # `hash.[]("foo") += 1` instead of `hash["foo"] += 1`.
    source = <<~RUBY
      proc {
        hash = { 'foo' => 1 }
        hash['foo'] += 1
        hash['foo']
      }
    RUBY
    expect(unparsed(source)).to eq(
      "proc {\n  hash = { \"foo\" => 1 }\n  hash[\"foo\"] += 1\n  hash[\"foo\"]\n}"
    )
  end

  it 'returns a Parser::AST::Node tree, so downstream find_block/type checks keep working' do
    ast = HyperSpec.parse_ruby('proc { 1 + 1 }')
    expect(ast).to be_a(Parser::AST::Node)
    expect(ast.type).to eq(:block)
  end
end
