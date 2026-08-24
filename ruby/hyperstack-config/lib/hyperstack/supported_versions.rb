require 'yaml'

module Hyperstack
  # Checks the configuration an app actually booted with against the supported
  # matrix in `supported_versions.yml`.
  #
  # This exists because the version string no longer encodes the combination.
  # Up to 1.0.alpha1.8 the gem version *was* the answer -- one build served
  # exactly one combination and said so (`...18.81.1902.0` => Rails 8.1,
  # React 19.2). From 1.0.alpha1.9 one gem supports many, so the only way to
  # know whether a given app is on a tested combination is to look.
  #
  # Three outcomes, deliberately not just pass/fail:
  #
  #   :supported   an exact cell -- this combination has a CI pipeline
  #   :untested    inside the spans we cover, but not a cell anyone runs
  #   :unsupported outside the spans entirely
  #
  # `:untested` matters. A hard failure there would refuse combinations that
  # very likely work and that we simply have not paid for a runner to prove;
  # silence would let people believe they are on a tested path when they are
  # not. So it warns once, and names the nearest cell.
  module SupportedVersions
    AXES = %w[ruby rails opal react_rails].freeze

    class << self
      def table_path
        @table_path ||= find_table
      end

      attr_writer :table_path

      def cells
        @cells ||= begin
          path = table_path
          path ? Array(YAML.safe_load(File.read(path))['cells']) : []
        end
      end

      def reset!
        @cells = nil
        @table_path = nil
        @reported = nil
      end

      # The versions this process actually loaded. Each is nil when the library
      # is absent, which is normal -- hyperstack-config is used outside Rails.
      def current
        {
          'ruby'        => major_minor(RUBY_VERSION),
          'rails'       => major_minor(gem_version('rails') || rails_constant),
          'opal'        => major_minor(gem_version('opal')),
          # React comes from react-rails (2.x bundles React 16, 3.3 bundles 18.2)
          # or, on the esbuild pipeline, from npm. The gem is the part we can see
          # from Ruby, so it is the axis we match on.
          'react_rails' => major_minor(gem_version('react-rails'))
        }
      end

      def status(actual = current)
        return :unknown if cells.empty?
        # Only classify when the whole combination is visible. A partly-detectable
        # environment (hyperstack-config loaded outside Rails, a rake task run from
        # the repo root, a gem build) must not be reported as supported OR as
        # unsupported -- both would be claims we cannot back up.
        return :unknown unless AXES.all? { |axis| actual[axis] }
        return :supported if cells.any? { |cell| matches?(cell, actual) }
        return :untested  if within_spans?(actual)

        :unsupported
      end

      # Human-readable explanation, always safe to call.
      def describe(actual = current)
        shown = AXES.map { |a| "#{a} #{actual[a] || '?'}" }.join(', ')
        case status(actual)
        when :unknown
          if cells.empty?
            "Hyperstack: supported_versions.yml not found; cannot check this configuration (#{shown})."
          else
            missing = AXES.reject { |a| actual[a] }
            "Hyperstack: cannot check this configuration — #{missing.join(', ')} not detectable here (#{shown})."
          end
        when :supported
          "Hyperstack: #{shown} — supported (matches cell '#{matching_cell(actual)['id']}')."
        when :untested
          "Hyperstack: #{shown} — within the supported range but not a tested combination. "\
          "Nearest tested: #{nearest(actual)}. If it misbehaves, try that combination before reporting a bug."
        else
          "Hyperstack: #{shown} — NOT a supported configuration. Supported: #{summary}."
        end
      end

      # Called from the railtie at boot, and reports at most once per process.
      #
      #   mode :warn  -- warn on :untested, raise on :unsupported (default)
      #   mode :raise -- raise on either
      #
      # :unsupported always raises: continuing would fail later somewhere far
      # less obvious (inside Opal, or the asset pipeline).
      def check!(mode: :warn)
        state = status
        return state if %i[supported unknown].include?(state)
        return state if @reported

        @reported = true
        message = describe
        raise message if state == :unsupported || mode == :raise

        warn message
        state
      end

      def summary
        AXES.map do |axis|
          values = cells.map { |c| c[axis] }.compact.uniq.sort
          "#{axis} #{values.join('/')}"
        end.join('; ')
      end

      private

      def matching_cell(actual)
        cells.detect { |cell| matches?(cell, actual) }
      end

      # An axis we cannot see is skipped rather than counted as a mismatch --
      # otherwise a legitimate non-Rails boot would be reported as unsupported.
      def matches?(cell, actual)
        AXES.all? do |axis|
          expected = cell[axis]
          expected.nil? || actual[axis].nil? || actual[axis] == expected
        end
      end

      # Inside the min..max we test on every axis, without being an exact cell.
      def within_spans?(actual)
        AXES.all? do |axis|
          values = cells.map { |c| c[axis] }.compact
          next true if values.empty?

          value = actual[axis]
          next true unless value # undetectable axis: skip, do not fail

          sorted = values.map { |v| Gem::Version.new(v) }.sort
          v = Gem::Version.new(value)
          v >= sorted.first && v <= sorted.last
        end
      rescue ArgumentError
        false
      end

      def nearest(actual)
        scored = cells.map do |cell|
          [AXES.count { |axis| cell[axis] == actual[axis] }, cell]
        end
        scored.max_by(&:first).last['id']
      end

      def gem_version(name)
        spec = Gem.loaded_specs[name]
        spec&.version&.to_s
      end

      def rails_constant
        return nil unless defined?(::Rails) && ::Rails.respond_to?(:version)

        ::Rails.version
      end

      def major_minor(version)
        return nil unless version

        version.to_s.split('.').first(2).join('.')
      end

      # The table lives at the repo/app root. Walk up from this file so it is
      # found both in a checkout and in an installed gem sitting next to one.
      def find_table
        dir = File.expand_path('../../..', __dir__)
        6.times do
          candidate = File.join(dir, 'supported_versions.yml')
          return candidate if File.exist?(candidate)

          parent = File.dirname(dir)
          break if parent == dir

          dir = parent
        end
        nil
      end
    end
  end
end
