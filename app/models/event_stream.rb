class EventStream < ApplicationRecord
  include_concern 'Purging'
  serialize :full_data

  belongs_to :target, :polymorphic => true
  belongs_to :ext_management_system, :foreign_key => :ems_id
  belongs_to :generating_ems, :class_name => "ExtManagementSystem"

  belongs_to :vm_or_template
  alias_method :src_vm_or_template, :vm_or_template
  belongs_to :vm,           :foreign_key => :vm_or_template_id
  belongs_to :miq_template, :foreign_key => :vm_or_template_id
  belongs_to :host
  belongs_to :availability_zone
  alias_method :src_host, :host

  belongs_to :dest_vm_or_template, :class_name => "VmOrTemplate"
  belongs_to :dest_vm,             :class_name => "Vm",          :foreign_key => :dest_vm_or_template_id
  belongs_to :dest_miq_template,   :class_name => "MiqTemplate", :foreign_key => :dest_vm_or_template_id
  belongs_to :dest_host,           :class_name => "Host"

  belongs_to :service

  belongs_to :container_replicator
  belongs_to :container_group
  belongs_to :container_node

  belongs_to :middleware_server, :foreign_key => :middleware_server_id
  belongs_to :physical_server

  virtual_column :group,       :type => :string
  virtual_column :group_level, :type => :string
  virtual_column :group_name,  :type => :string

  after_commit :emit_notifications, :on => :create

  def emit_notifications
    Notification.emit_for_event(self)
  rescue => err
    _log.log_backtrace(err)
  end

  def self.event_groups
    core_event_groups = ::Settings.event_handling.event_groups.to_hash
    Settings.ems.each_with_object(core_event_groups) do |(_provider_type, provider_settings), event_groups|
      provider_event_groups = provider_settings.fetch_path(:event_handling, :event_groups)
      next unless provider_event_groups
      DeepMerge.deep_merge!(
        provider_event_groups.to_hash, event_groups,
        :preserve_unmergeables => false,
        :overwrite_arrays      => false
      )
    end
  end

  def self.group_and_level(event_type)
    group, v = event_groups.find { |_k, v| v[:critical].include?(event_type) || v[:detail].include?(event_type) }
    if group.nil?
      group, level = :other, :detail
    else
      level = v[:detail].include?(event_type) ? :detail : :critical
    end
    return group, level
  end

  def self.group_name(group)
    return nil if group.nil?
    group = event_groups[group.to_sym]
    return nil if group.nil?
    group[:name]
  end

  def group
    return @group unless @group.nil?
    @group, @group_level = self.class.group_and_level(event_type)
    @group
  end

  def group_level
    return @group_level unless @group_level.nil?
    @group, @group_level = self.class.group_and_level(event_type)
    @group_level
  end

  def group_name
    @group_name ||= self.class.group_name(group)
  end
end
