module HyperSpec
  module Internal
    module ClientExecution
      def internal_evaluate_ruby(*args, &block)
        insure_page_loaded
        add_promise_execute_and_wait(*process_params(*args, &block))
      end

      private

      PRIVATE_VARIABLES = %i[
        @__inspect_output @__memoized @example @_hyperspec_private_client_code
        @_hyperspec_private_html_block @fixture_cache
        @fixture_connections @connection_subscriber @loaded_fixtures
        @_hyperspec_private_client_options
        b __ _ _ex_ pry_instance _out_ _in_ _dir_ _file_
      ]

      def add_locals(in_str, block)
        b = block.binding

        memoized = b.eval('__memoized').instance_variable_get(:@memoized)
        in_str = memoized.inject(in_str) do |str, pair|
          "#{str}\n#{set_local_var(pair.first, pair.last)}"
        end if memoized

        in_str = b.local_variables.inject(in_str) do |str, var|
          next str if PRIVATE_VARIABLES.include? var

          "#{str}\n#{set_local_var(var, b.local_variable_get(var))}"
        end

        in_str = b.eval('instance_variables').inject(in_str) do |str, var|
          next str if PRIVATE_VARIABLES.include? var

          "#{str}\n#{set_local_var(var, b.eval("instance_variable_get('#{var}')"))}"
        end
        in_str
      end

      def add_opal_block(str, block)
        return str unless block

        source = block.source
        ast = Parser::CurrentRuby.parse(source)
        ast = find_block(ast)
        raise "could not find block within source: #{block.source}" unless ast

        "#{add_locals(str, block)}\n#{Unparser.unparse ast.children.last}"
      end

      def add_promise_execute_and_wait(str, opts)
        js = opal_compile(add_promise_wrapper(str))
        page.execute_script("window.hyper_spec_promise_result = false; #{js}")
        Timeout.timeout(Capybara.default_max_wait_time) do
          loop do
            break if page.evaluate_script('!!window.hyper_spec_promise_result')

            sleep 0.25
          end
        end
        JSON.parse(page.evaluate_script('window.hyper_spec_promise_result.$to_json()'), opts).first
      end

      def add_promise_wrapper(str)
        <<~RUBY
          (#{str}).tap do |r|
            if defined?(Promise) && r.is_a?(Promise)
              r.then { |args| `window.hyper_spec_promise_result = [args]` }
            else
              #after(0) do
                #puts "setting window.hyper_spec_promise_result = [\#{r}]"
                `window.hyper_spec_promise_result = [r]`
              #end
            end
          end
        RUBY
      end

      def find_block(node)
        # find a block with the ast tree.

        return false unless node.class == Parser::AST::Node
        return node if the_node_you_are_looking_for?(node)

        node.children.each do |child|
          found = find_block(child)
          return found if found
        end
        false
      end

      def process_params(*args, &block)
        args = ['', *args] if args[0].is_a? Hash
        args = [args[0], {}, args[1] || {}] if args.length < 3
        str, opts, vars = args
        vars.each do |name, value|
          str = "#{name} = #{value.inspect}\n#{str}"
        end
        [add_opal_block(str, block), opts]
      end

      def the_node_you_are_looking_for?(node)
        # we could also check that the block is going to the right method
        #   respond_to?(node.children.first.children[1]) &&
        #   method(node.children.first.children[1]) == method(:evaluate_ruby)
        # however that does not work for expect { ... }.on_client_to ...
        # because now the block is being sent to expect... so we could
        # check the above OR node.children.first.children[1] == :expect
        # but what if there are two blocks? on and on...
        node.type == :block &&
          node.children.first.class == Parser::AST::Node &&
          node.children.first.type == :send
      end

      def set_local_var(name, object)
        serialized = object.opal_serialize
        if serialized
          "#{name} = #{serialized}"
        else
          "self.class.define_method(:#{name}) "\
          "{ raise 'Attempt to access the variable #{name} "\
          'that was defined in the spec, but its value could not be serialized '\
          "so it is undefined on the client.' }"
        end
      end

      def opal_compile(str, *)
        Opal.hyperspec_compile(str)
      end
    end
  end
end
