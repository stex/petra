require 'require_all'

# Load all of petra's core files
require_all File.join(File.dirname(__FILE__), 'petra')

# Load the ActiveRecord models only if ActiveRecord itself is defined.
require_all Petra::Engine.root.join('app', 'models') if defined?(ActiveRecord::Base)

module Petra

  #
  # @return [Petra::Configuration::Base] petra's configuration instance
  #
  def self.configuration
    @configuration ||= Petra::Configuration::Base.new
  end

  #
  # Executes the given block in the context of petra's configuration instance
  #
  def self.configure(&proc)
    configuration.instance_eval(&proc) if block_given?
  end

  #
  # Forward transaction handling to the Transaction class.
  # It's just for eye candy that you're able to use Petra.transaction
  # instead of Petra::Transaction.start
  #
  # @see Petra::Transaction#start
  #
  def self.transaction(*args, &block)
    Petra::Components::Transaction.start(*args, &block)
  end

  #
  # Logs the given +message+ if petra is configured to be verbose
  #
  def self.log(message, color = :yellow)
    return unless configuration.verbose

    colors = {:light_gray => 90, :yellow => 33, :green => 32, :red => 31}
    Rails.logger.debug "\e[#{colors[color.to_sym]}mPetra :: #{message}\e[0m"
  end

end

# Extend the Object class to add the `petra` proxy generator
Object.class_eval do
  include Petra::CoreExt::Object
end
