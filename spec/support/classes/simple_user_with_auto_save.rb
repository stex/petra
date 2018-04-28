# frozen_string_literal: true

module Classes
  #
  # Behaves like SimpleUser, but will treat setting an attribute as persisting the object as well.
  #
  class SimpleUserWithAutoSave < SimpleUser
    Petra.configure do
      configure_class 'Classes::SimpleUserWithAutoSave' do
        persistence_method? do |method_name|
          %w[first_name= last_name=].include?(method_name.to_s)
        end
      end
    end
  end
end
