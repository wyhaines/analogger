# frozen_string_literal: true

require 'socket'

module Swiftcore
  class Analogger
    class Destination
      class Socket < ::TCPSocket

        def self.open(*args)
          super
        end
      end
    end
  end
end
