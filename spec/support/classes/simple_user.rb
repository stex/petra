# frozen_string_literal: true

module Classes
  class SimpleUser
    attr_accessor :first_name
    attr_accessor :last_name

    def initialize(first_name = nil, last_name = nil)
      @first_name = first_name || Faker::Name.first_name
      @last_name = last_name || Faker::Name.last_name
    end

    def name
      "#{first_name} #{last_name}"
    end

    def save
      # Do nothing, we just want an explicit save method.
      # We could also set every attribute write to also be a persistence method
    end
  end
end

Petra.configure do
  configure_class 'Classes::SimpleUser' do
    proxy_instances true

    attribute_reader? do |method_name|
      %w[first_name last_name].include?(method_name.to_s)
    end

    attribute_writer? do |method_name|
      %w[first_name= last_name=].include?(method_name.to_s)
    end

    dynamic_attribute_reader? do |method_name|
      %w[name].include?(method_name.to_s)
    end

    persistence_method? do |method_name|
      %w[save].include?(method_name.to_s)
    end
  end
end
