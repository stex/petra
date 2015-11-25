require 'require_all'

# The engine definition has to be required first, otherwise Rails components like
# rake tasks are not built properly
require 'petra/engine'

module Petra
  def self.root
    File.expand_path(File.join(File.dirname(__FILE__), '..'))
  end

  def self.configuration
    @configuration ||= Petra::Configuration.new
  end

  def self.configure
    yield configuration if block_given?
  end
end

autoload_all File.join(File.dirname(__FILE__), 'petra')

# Load the ActiveRecord models in ActiveRecord itself is defined.
# TODO: Check for these includes when setting the persistence adapter to ensure that ActiveRecord can only be used when it's available.
if defined?(ActiveRecord::Base)
  require_all File.join(Petra.root, 'app', 'models')
end

Object.class_eval do
  include Petra::CoreExt::Object
end

NilClass.class_eval do
  include Petra::CoreExt::NilClass
end
