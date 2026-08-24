module Hyperstack
  # When a client sends a save or destroy request for an *existing* record it
  # supplies the record's primary key.  Historically the server resolved that
  # key with a bare `Model.find(id)`, which meant the only gate on the whole
  # operation was `create_permitted?`/`update_permitted?`/`destroy_permitted?`.
  # Policies that read as "is someone signed in" (rather than "does this record
  # belong to the acting user") therefore let a client name the id of *any*
  # record of that model, because the natural place to answer "may this client
  # reach this record at all" -- the read regulation -- was never consulted.
  #
  # With this setting true (the default) the resolved record must also be
  # readable by the acting user, i.e. `view_permitted?(primary_key)` must hold,
  # which is exactly the gate the read path applies when it resolves a record by
  # id (see `__hyperstack_internal_scoped_find_by`).
  #
  # Set to false in an initializer to restore the pre-fix behavior:
  #
  #   Hyperstack.configuration do |config|
  #     config.verify_record_visibility_on_write = false
  #   end
  define_setting :verify_record_visibility_on_write, true

  class InternalPolicy

    def self.accessible_attributes_for(model, acting_user)
      user_channels = ClassConnectionRegulation.connections_for(acting_user, false) +
        InstanceConnectionRegulation.connections_for(acting_user, false)
      internal_policy = InternalPolicy.new(model, model.attribute_names, user_channels)
      ChannelBroadcastRegulation.broadcast(internal_policy)
      InstanceBroadcastRegulation.broadcast(model, internal_policy)
      internal_policy.accessible_attributes_for
    end

    def accessible_attributes_for
      accessible_attributes = Set.new
      @channel_sets.each do |channel, attribute_set|
        accessible_attributes.merge attribute_set
      end
      accessible_attributes << :id unless accessible_attributes.empty?
      accessible_attributes
    end
  end
end

class ActiveRecord::Base

  attr_accessor :acting_user

  def view_permitted?(attribute)
    Hyperstack::InternalPolicy.accessible_attributes_for(self, acting_user).include? attribute.to_sym
  end

  def create_permitted?
    false
  end

  def update_permitted?
    false
  end

  def destroy_permitted?
    false
  end

  def only_changed?(*attributes)
    (self.attributes.keys + self.class.reactive_record_association_keys).each do |key|
      return false if self.send("#{key}_changed?") and !attributes.include? key
    end
    true
  end

  def none_changed?(*attributes)
    attributes.each do |key|
      return false if self.send("#{key}_changed?")
    end
    true
  end

  def any_changed?(*attributes)
    attributes.each do |key|
      return true if self.send("#{key}_changed?")
    end
    false
  end

  def all_changed?(*attributes)
    attributes.each do |key|
      return false unless self.send("#{key}_changed?")
    end
    true
  end

  class << self

    attr_reader :reactive_record_association_keys

    [:has_many, :belongs_to, :composed_of].each do |macro|
      define_method "#{macro}_with_reactive_record_add_changed_method".to_sym do |attr_name, *args,**kwargs, &block|
        define_method "#{attr_name}_changed?".to_sym do
          instance_variable_get "@reactive_record_#{attr_name}_changed".to_sym
        end
        (@reactive_record_association_keys ||= []) << attr_name
        send "#{macro}_without_reactive_record_add_changed_method".to_sym, attr_name, *args,**kwargs, &block
      end
      alias_method "#{macro}_without_reactive_record_add_changed_method".to_sym, macro
      alias_method macro, "#{macro}_with_reactive_record_add_changed_method".to_sym
    end

    alias belongs_to_without_reactive_record_add_is_method belongs_to

    def belongs_to(attr_name, *args,**kwargs)
      belongs_to_without_reactive_record_add_is_method(attr_name, *args,**kwargs).tap do
        define_method "#{attr_name}_is?".to_sym do |model|
          attributes[self.class.reflections[attr_name.to_s].foreign_key] == model.id
        end
      end
    end
  end

  def check_permission_with_acting_user(user, permission, *args)
    old = acting_user
    self.acting_user = user
    if self.send(permission, *args)
      self.acting_user = old
      self
    else
      acting_user_string =
        if acting_user
          id = user.respond_to?(:id) ? user.id : user
          "not allowed for acting_user: <##{user.class} id: #{user}>"
        else
          "not allowed without acting_user (acting_user = nil)"
        end

      message = "CRUD access violation: <##{self.class} id: #{self.id}> - #{permission}(#{args}) #{acting_user_string}"
      if permission == :view_permitted?
        details = Hyperstack::PolicyDiagnostics.policy_dump_for(self, user)
      end
      Hyperstack::InternalPolicy.raise_operation_access_violation(message, details || '')
    end
  end

end

class ActionController::Base

  def acting_user
  end

end
