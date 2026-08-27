module HyperSpec
  module Internal
    module ComponentMount
      private

      TEST_CODE_KEY = 'hyper_spec_prerender_test_code.js'.freeze

      # rubocop:disable Metrics/MethodLength
      def add_block_with_helpers(component_name, opts, block)
        return unless block || @_hyperspec_private_client_code ||
                      @_hyperspec_private_mounted_client_code || component_name.nil?

        remember_mounted_client_code(@_hyperspec_private_client_code)
        @_hyperspec_private_client_code = nil

        block_with_helpers = <<-RUBY
          module ComponentHelpers
            def self.js_eval(s)
              `eval(s)`
            end
            def self.dasherize(s)
              res = %x{
                s.replace(/[-_\\s]+/g, '-')
                .replace(/([A-Z\\d]+)([A-Z][a-z])/g, '$1-$2')
                .replace(/([a-z\\d])([A-Z])/g, '$1-$2')
                .toLowerCase()
              }
              res
            end
            def self.add_class(class_name, styles={})
              style = styles.collect { |attr, value| "\#{dasherize(attr)}:\#{value}" }.join("; ")
              cs = class_name.to_s
              %x{
                var style_el = document.createElement("style");
                var css = "." + cs + " { " + style + " }";
                style_el.type = "text/css";
                if (style_el.styleSheet){
                  style_el.styleSheet.cssText = css;
                } else {
                  style_el.appendChild(document.createTextNode(css));
                }
                document.head.appendChild(style_el);
              }
            end
          end
          #{test_dummy}
          #{mounted_client_code}
          #{"#{add_locals('', block) if block}\n#{Unparser.unparse(HyperSpec.parse_ruby(block.source).children.last)}" if block}
        RUBY
        opts[:code] = opal_compile(block_with_helpers)
      end
      # rubocop:enable Metrics/MethodLength

      # `before_mount`, `isomorphic`, `insert_html` and `add_class` put code in the
      # PENDING buffers, and mounting used to just drain them: the code went into
      # one page and the buffer was emptied. Anything that then replaced that page
      # -- an explicit `load_page`, or the reload insure_page_loaded performs when
      # `Opal` looks absent -- produced a page with none of it, and every constant,
      # method and module the spec had put on the client was gone for the rest of
      # the example. Worst inside an RSpec::Steps sequence, which is one example in
      # one long-lived browser, so the injection happens once at the first step's
      # mount and then has to survive every remaining step. See #71.
      #
      # So draining the pending buffer now moves it into a MOUNTED buffer that is
      # replayed into every page built afterwards. Each mount always visits a fresh
      # URL, so replaying only ever targets a blank page -- it restores setup, it
      # never re-runs anything against a page that already has it.
      #
      # The two buffers stay distinct because insure_page_loaded reads the PENDING
      # one as "there is code still waiting for a mount" (see its
      # only_if_code_or_html_exists guard); folding them together would make that
      # test always true and re-mount every example in a no_reset group.
      #
      # Fragments are kept de-duplicated: a `before(:step)` block that re-injects
      # the same helpers on every step of a long sequence would otherwise stack up
      # identical copies, and one copy per page is what the page needs.
      def remember_mounted(buffer_name, code)
        return if code.nil? || code.empty?

        buffer = instance_variable_get(buffer_name) || []
        buffer += [code] unless buffer.include?(code)
        instance_variable_set(buffer_name, buffer)
      end

      def remember_mounted_client_code(code)
        remember_mounted(:@_hyperspec_private_mounted_client_code, code)
      end

      def remember_mounted_html_block(html)
        remember_mounted(:@_hyperspec_private_mounted_html_block, html)
      end

      def mounted_client_code
        (@_hyperspec_private_mounted_client_code || []).join("\n")
      end

      def mounted_html_block
        buffer = @_hyperspec_private_mounted_html_block
        buffer && buffer.join("\n")
      end

      def build_test_url_for(controller = nil, ping = nil)
        id = ping ? 'ping' : Controller.test_id
        "/#{route_root_for(controller)}/#{id}"
      end

      def insure_page_loaded(only_if_code_or_html_exists = nil)
        return if only_if_code_or_html_exists && !@_hyperspec_private_client_code && !@_hyperspec_private_html_block

        # if we are not resetting between examples, or think its mounted
        # then look for Opal, but if we can't find it, then ping to clear and try again
        if !HyperSpec.reset_between_examples? || page.instance_variable_get('@hyper_spec_mounted')
          return if opal_loaded?

          page.visit build_test_url_for(nil, true) rescue nil
        end
        load_page
      end

      # Is Opal actually gone, or did the probe itself just fail?
      #
      # This used to be `evaluate_script('Opal && true') rescue nil`, which
      # answers "no" to both -- so a transient WebDriver failure was read as "the
      # page lost Opal" and reloaded it. #71 makes a reload replay the injected
      # code, but it cannot bring back client-side STATE: the ReactiveRecord
      # cache, mounted component state and transport subscriptions all go with the
      # old page. A reload we did not need is still capable of breaking the
      # example, so only reload when the answer is really "no".
      #
      # A missing Opal raises a JS error (referencing an undeclared identifier);
      # a driver problem raises something else. Matched by class name rather than
      # by constant because hyper-spec also runs on non-Selenium drivers.
      def opal_loaded?
        evaluate_script('Opal && true')
      rescue StandardError => e
        return false if e.class.name.to_s.include?('JavascriptError')

        # not evidence about the page -- ask once more before giving up on it
        begin
          evaluate_script('Opal && true')
        rescue StandardError
          false
        end
      end

      def internal_mount(component_name, params, opts, &block)
        # TODO:  refactor this
        test_url = build_test_url_for(opts.delete(:controller))
        add_block_with_helpers(component_name, opts, block)
        send_params_to_controller_via_cache(test_url, component_name, params, opts)
        setup_prerendering(opts)
        page.instance_variable_set('@hyper_spec_mounted', false)
        visit test_url
        wait_for_ajax unless opts[:no_wait]
        page.instance_variable_set('@hyper_spec_mounted', true)
        Lolex.init(self, client_options[:time_zone], client_options[:clock_resolution])
      end

      def prerendering?(opts)
        return false if HyperSpec.prerendering_disabled?

        %i[both server_only].include?(opts[:render_on])
      end

      def send_params_to_controller_via_cache(test_url, component_name, params, opts)
        component_name ||= 'Hyperstack::Internal::Component::TestDummy' if test_dummy
        remember_mounted_html_block(@_hyperspec_private_html_block)
        @_hyperspec_private_html_block = nil
        Controller.cache_write(
          test_url,
          [component_name, params, mounted_html_block, opts]
        )
      end

      # test_code_key = "hyper_spec_prerender_test_code.js"
      # if defined? ::Hyperstack::Component
      #   @@original_server_render_files ||= ::Rails.configuration.react.server_renderer_options[:files]
      #   if opts[:render_on] == :both || opts[:render_on] == :server_only
      #     unless opts[:code].blank?
      #       ComponentTestHelpers.cache_write(test_code_key, opts[:code])
      #       ::Rails.configuration.react.server_renderer_options[:files] = @@original_server_render_files + [test_code_key]
      #       ::React::ServerRendering.reset_pool # make sure contexts are reloaded so they dont use code from cache, as the rails filewatcher doesnt look for cache changes
      #     else
      #       ComponentTestHelpers.cache_delete(test_code_key)
      #       ::Rails.configuration.react.server_renderer_options[:files] = @@original_server_render_files
      #       ::React::ServerRendering.reset_pool # make sure contexts are reloaded so they dont use code from cache, as the rails filewatcher doesnt look for cache changes
      #     end
      #   end
      # end

      def setup_prerendering(opts)
        return unless defined?(::Hyperstack::Component) && prerendering?(opts)

        @@original_server_render_files ||= ::Rails.configuration.react.server_renderer_options[:files]
        ::Rails.configuration.react.server_renderer_options[:files] = @@original_server_render_files
        if opts[:code].blank?
          Controller.cache_delete(TEST_CODE_KEY)
        else
          Controller.cache_write(TEST_CODE_KEY, opts[:code])
          ::Rails.configuration.react.server_renderer_options[:files] += [TEST_CODE_KEY]
        end
        ::React::ServerRendering.reset_pool
        # make sure contexts are reloaded so they dont use code from cache, as the rails filewatcher
        # doesnt look for cache changes
      end

      def test_dummy
        return unless defined? ::Hyperstack::Component

        <<-RUBY
          class Hyperstack::Internal::Component::TestDummy
            include Hyperstack::Component
            render {}
          end
        RUBY
      end
    end
  end
end
