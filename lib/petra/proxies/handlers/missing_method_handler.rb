# frozen_string_literal: true
module Petra
  module Proxies
    module Handlers
      class MissingMethodHandler
        def initialize(proxy)
          @proxy = proxy
        end

        attr_reader :proxy
        delegate :transaction, :to => :@proxy

        class << self
          def constraints
            @constraints ||= []
          end

          #
          # Adds a constraint to this handler class regarding the position
          # it will end up in when actually executing the handlers.
          #
          # @param [:before, :after, :<, :>] position
          # @param [String, Symbol] other_handler
          #   The other handler's identifier
          #
          def add_constraint(position, other_handler)
            method = position.to_sym == :before ? :< : :>
            constraints << [method, other_handler.to_sym]
          end
        end

        def queue_constraints
          not_implemented
        end

        def applicable?
          not_implemented
        end

        def handle(*)
          not_implemented
        end
      end
    end
  end
end
