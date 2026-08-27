module ReactiveRecord
  # The one place that answers "is this client-supplied string the name of a
  # constant that is *genuinely* loaded?" -- defined, with no pending autoload.
  #
  # `const_defined?` on its own cannot answer that under Zeitwerk (the default
  # autoloader since Rails 6.0, and the only one from Rails 7): every class under
  # `app/*` gets a registered autoload at boot and therefore reports as defined
  # *before its file is loaded*. A gate built on `const_defined?` alone will
  # happily let a client string force the load of an arbitrary class -- exactly
  # what `ServerDataCache.get_model` and `LazyColumnsHash#key?` exist to prevent.
  #
  # Both of those gates call this, so the predicate cannot drift apart or be
  # quietly refactored back to `const_defined?` on one side only. See #60.
  module ConstantGate
    module_function

    # Resolution starts at Object, matching the `str.constantize` that follows a
    # passing gate -- so the check and the resolution cannot disagree.
    def loaded?(str)
      str = str.to_s
      return false unless Object.const_defined?(str)
      namespace, _sep, leaf = str.rpartition('::')
      owner = namespace.empty? ? Object : Object.const_get(namespace)
      !(owner.respond_to?(:autoload?) && owner.autoload?(leaf))
    rescue NameError
      false
    end
  end
end
