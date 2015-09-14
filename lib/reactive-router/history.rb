class History

  class << self

    def setup_handler
      unless @handlers_setup
        %x{
          if (window.addEventListener) {
            window.addEventListener('popstate', #{method(:window_history_pop_handler).to_n}, false);
          } else {
            window.attachEvent('onpopstate', #{method(:window_history_pop_handler).to_n});
          }
        }
      end
      @handlers_setup = true
    end

    def current_path
      @current_path ||= `decodeURI(window.location.pathname + window.location.search)`
    end

    attr_accessor :history

    def histories
      @histories ||= {}
    end

    def window_history_pop_handler(event)
      return if `event.state === undefined`
      puts "pop handler #{`event.state.history_id`}, #{`ReactRouter.History.length`} -> #{`event.state.history_length`}, #{`event.state.path`}"
      old_history = @history
      old_history_length = `ReactRouter.History.length`
      @current_path = `event.state.path`
      @history= histories[`event.state.history_id`]
      `ReactRouter.History.length = event.state.history_length`
      if old_history != @history
        if `ReactRouter.History.length` > old_history_length
          puts "activating "
          @history.on_state_change.call(:active) if @history.on_state_change
        else
          puts "deactivating"
          old_history.on_state_change.call(:inactive) if old_history.on_state_change
        end
      end
      @history.notify_listeners(:pop)
    end

    def push_path(path)
      puts "pushing path #{path}"
      `window.history.pushState({ path: path, history_id: #{@history.object_id}, history_length: (ReactRouter.History.length += 1)}, '', path);`
      @current_path = path
      @history.notify_listeners(:push)
    end

    def replace_path(path)
      puts "replacing path #{path}"
      `window.history.replaceState({ path: path, history_id: #{@history.object_id}, history_length: ReactRouter.History.length}, '', path);`
      @current_path = path
      @history.notify_listeners(:replace)
    end

    def pop_path
      `window.history.go(-1)`
    end
  end

  attr_reader :location
  attr_reader :on_state_change

  def to_s
    "History<#{@initial_path}>"
  end

  def initialize(preactivate_path = nil, &on_state_change)
    self.class.histories[self.object_id] = self
    @on_state_change = on_state_change
    @initial_path = @preactivate_path = preactivate_path
    self.class.setup_handler
    @listeners = []
    @location = {
      addChangeListener: lambda { |listener| @listeners << listener unless @listeners.include? listener} ,
      removeChangeListener: lambda { |listener| @listeners.delete(listener) },
      push: lambda { |path| self.class.push_path(path) },
      pop: lambda { self.class.pop_path },
      replace: lambda { |path| self.class.replace_path path },
      getCurrentPath: lambda { (@preactivate_path || self.class.current_path)},
      toString: lambda { '<HistoryLocation>'}
    }.to_n
  end

  def activate(initial_path = nil)
    puts "activating #{self}"
    @preactivate_path = nil
    initial_path ||= @initial_path || self.class.current_path
    self.class.history = self
    @starting_history_length = `ReactRouter.History.length`
    self.class.push_path initial_path
    @on_state_change.call(:active) if @on_state_change
    self
  end

  def deactivate
    puts "deactivate go(#{@starting_history_length-`ReactRouter.History.length`})"
    `window.history.go(#{@starting_history_length}-ReactRouter.History.length)`
    self
  end

  def notify_listeners(type)
    puts "#{self}.notify_listeners(#{type}) listeners_count: #{@listeners.count}, path: #{self.class.current_path}"
    @listeners.each { |listener| `listener.call(#{@location}, {path: #{self.class.current_path}, type: type})` }
  end


end
