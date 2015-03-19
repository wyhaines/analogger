module Swiftcore
	class AnaloggerProtocol < EventMachine::Connection

		def setup
File.open("/tmp/a.out","a+") {|fh| fh.puts "connection: setup" }
			@length = nil
			@logchunk = ''
			@authenticated = nil
		end

    def receive_data data
File.open("/tmp/a.out","a+") {|fh| fh.puts "connection: received: #{data}" }
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
          
          unless @authenticated  ##### Handle authentication
            if msg.last == LoggerClass.key
              @authenticated = true
File.open("/tmp/a.out","a+") {|fh| fh.puts "connection: accepted"}
              send_data "accepted\n"
            else
File.open("/tmp/a.out","a+") {|fh| fh.puts "connection: denied"}
							send_data "denied\n"
              close_connection_after_writing
            end
          else ##### The client has been authenticated
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

# TODO:
#
#   The security key is pretty insecure right now.  Client and server should be
#   able to use SSL, and even when not using SSL, authentication should be more
#   secure.  Maybe client talks to server and gets a one-time key that is uses
#   to encrypt the security key.  It passes the security key to the server, which
#   compares it to it's own one-time-encrypted version.
