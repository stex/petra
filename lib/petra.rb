require 'require_all'
require_all File.join(File.dirname(__FILE__), 'petra')

module Petra
  def self.root
    File.expand_path(File.join(File.dirname(__FILE__), '..'))
  end

  def self.configuration
    @configuration ||= Petra::Configuration::Base.new
  end

  def self.configure
    yield configuration if block_given?
  end
end

# Load the ActiveRecord models in ActiveRecord itself is defined.
# TODO: Check for these includes when setting the persistence adapter
#       to ensure that ActiveRecord can only be used when it's available.
if defined?(ActiveRecord::Base)
  require_all File.join(Petra.root, 'app', 'models')
end

#----------------------------------------------------------------
#                       Core Extensions
#----------------------------------------------------------------

Object.class_eval do
  include Petra::CoreExt::Object
end
