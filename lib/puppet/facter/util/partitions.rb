require 'facter/util/partitions/linux'

module Facter::Util::Partitions
  IMPLEMENTATIONS = {
    'Linux' => Linux
  }

  module NoImplementation
    def self.list
      []
    end
  end

  def self.implementation
    IMPLEMENTATIONS[Facter.fact(:kernel).value] || NoImplementation
  end

  def self.list
    implementation.list
  end

  def self.uuid(partition)
    implementation.uuid(partition)
  end

  def self.size(partition)
    implementation.size(partition)
  end

  def self.mount(partition)
    implementation.mount(partition)
  end

  def self.filesystem(partition)
    implementation.filesystem(partition)
  end

  def self.available?
    !self.list.empty?
  end
end
