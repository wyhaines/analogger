require 'async/io/protocol/generic'

module Swiftcore
  class AnaloggerProtocol < Async::IO::Protocol::Generic

    MaxMessageLength = 8192
    MaxLengthBytes = MaxMessageLength.to_s.length

    def initialize(stream, peer)
      super(stream)

      @length = nil
      @pos = 0
      @logchunk = ''
      @authenticated = nil
      @peer = peer
    end

    def receive
      while chunk = @stream.readpartial(8192)
        receive_data chunk
      end
    end

    def send_data data
      @stream.write data
    end

    # This is the key method for receiving messages and handling the protocol. The current protocol is a very
    # simple wire protocol. A packet of data contains an 8 byte header that encodes, in ASCII, the number of
    # characters that are in the message as a pair of 4 digit numbers. The repeated length represents a trivial
    # checksum on the received packet.
    def receive_data data
      @logchunk << data
      decompose = true
      while decompose
        unless @length
          if @logchunk.length - @pos > 7
            l = @logchunk[@pos + 0..@pos + 3].to_i
            ck = @logchunk[@pos + 4..@pos + 7].to_i
            if l == ck and l < MaxMessageLength
              @length = l
            else
              decompose = false
              peer = @peer ? ::Socket.unpack_sockaddr_in(@peer)[1] : 'UNK'
              if l == ck
                LoggerClass.add_log([:default, :error, "Max Length Exceeded from #{peer} -- #{l}/#{MaxMessageLength}"])
                send_data(-"error: max length exceeded\n")
                close_connection_after_writing
              else
                LoggerClass.add_log([:default, :error, "checksum failed from #{peer} -- #{l}/#{ck}"])
                send_data(-"error: checksum failed\n")
                close_connection_after_writing
              end
            end
          end
        end

        if @length && @length < 8
          decompose = false
        end

        if @length and @length > 0 and @logchunk.length - @pos >= @length
          msg = @logchunk[@pos..@length + @pos - 1].split(Rcolon, 4)
          @pos += @length
          unless @authenticated
            if msg.last == LoggerClass.key
              @authenticated = true
              send_data(-"accepted\n")
            else
              send_data(-"denied\n")
              close_connection_after_writing
            end
          else
            msg[0] = nil
            msg.shift
            LoggerClass.add_log(msg)
          end
          @length = nil
        else
          decompose = false
        end
      end
      if @pos >= @logchunk.length
        @logchunk.clear
        @pos = 0
      end
    end
  end
end
