module Swiftcore
	class AnaloggerProtocol < EventMachine::Connection

		def setup
			@length = nil
			@logchunk = ''
			@authenticated = nil
		end

    def receive_data data
      @logchunk << data
      decompose = true
      while decompose
        unless @length
          if @logchunk.length > 7
     #       l = @logchunk[0..3].unpack(Ci).first
     #       ck = @logchunk[4..7].unpack(Ci).first
     #       if l == ck and l < MaxMessageLength
						l = @logchunk[0..3]
						ck = @logchunk[4..7]
						if l == ck and (ll = l.unpack(Ci).first)
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

        if @length and @logchunk.length > @length
          msg = @logchunk.slice!(0..@length).split(Rcolon,4)
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
		end
	end
end
