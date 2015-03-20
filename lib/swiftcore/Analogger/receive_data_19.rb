module Swiftcore
  class AnaloggerProtocol < EventMachine::Connection

    def setup
      @length = nil
      @pos = 0
      @logchunk = ''
      @authenticated = nil
    end

    def receive_data data
      @logchunk << data
      decompose = true
      while decompose
        unless @length
          if @logchunk.length - @pos > 7
#           l = @logchunk[@pos + 0..@pos + 3].unpack(Ci).first
#           ck = @logchunk[@pos + 4..@pos + 7].unpack(Ci).first
            l = @logchunk[@pos + 0..@pos + 3]
            ck = @logchunk[@pos + 4..@pos + 7]
#           if l == ck and l < MaxMessageLength
            if l == ck and (ll = l.unpack(Ci).first) < MaxMessageLength
              @length = ll + 7
            else
              decompose = false
              peer = get_peername
              peer = peer ? ::Socket.unpack_sockaddr_in(peer)[1] : 'UNK'
              if l == ck
                LoggerClass.add_log([:default,:error,"Max Length Exceeded from #{peer} -- #{l}/#{MaxMessageLength}"])
                close_connection
              else
                LoggerClass.add_log([:default,:error,"checksum failed from #{peer} -- #{l}/#{ck}"])
                close_connection
              end
            end
          end
        end

        if @length and @logchunk.length - @pos > @length
          msg = nil
          msg = @logchunk[@pos..@length+@pos].split(Rcolon,4)
          @pos += @length + 1
          unless @authenticated
            if msg.last == LoggerClass.key
              @authenticated = true
            else
              close_connection
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
        @logchunk = ''
        @pos = 0
      end
    end
  end
end
