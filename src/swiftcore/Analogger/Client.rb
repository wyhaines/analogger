require 'socket'
include Socket::Constants

module Swiftcore
	module Analogger

		# Swift::Analogger::Client is the client library for writing logging
		# messages to the Swift Analogger asynchronous logging server.
		#
		# To use the Analogger client, instantiate an instance of the Client
		# class.  
		#
		#   logger = Swift::Analogger::Client.new(:myapplog,'127.0.0.1',12345)
		#
		# Four arguments are accepted when a new Client is created.  The first
		# is the name of the logging facility that this Client will write to.
		# The second is the hostname where the Analogger process is running,
		# and the third is the port number that it is listening on for
		# connections.
		#
		# The fourth argument is optional.  Analogger can require an
		# authentication key before it will allow logging clients to use its
		# facilities.  If the Analogger that one is connecting to requires
		# an authentication key, it must be passed to the new() call as the
		# fourth argument.  If the key is incorrect, the connection will be
		# closed.
		#
		# If a Client connects to the Analogger using a facility that is
		# undefined in the Analogger, the log messages will still be accepted,
		# but they will be dumped to the default logging destination.
		#
		# Once connected, the Client is ready to deliver messages to the
		# Analogger.  To send a messagine, the log() method is used:
		#
		#   logger.log(:debug,"The logging client is now connected.")
		#
		# The log() method takes two arguments.  The first is the severity of
		# the message, and the second is the message itself.  The default
		# Analogger severity levels are the same as in the standard Ruby
		# 
		class Client
			Cauthentication = 'authentication'.freeze
			Ci = 'i'.freeze

			def initialize(service = 'default', host = '127.0.0.1' , port = 6766, key = nil)
				@service = service.to_s
				@key = key
				@host = host
				@port = port
				connect(host,port)
			end

			def connect(host,port)
				tries ||= 0
				@socket = Socket.new(AF_INET,SOCK_STREAM,0)
				sockaddr = Socket.pack_sockaddr_in(port,host)
				@socket.connect(sockaddr)
				log(Cauthentication,"#{@key}")
			rescue Exception => e
				if tries < 3
					tries += 1
					@socket.close if @socket and !@socket.closed?
					@socket = nil
					select(nil,nil,nil,tries * 0.2) if tries > 0
					retry
				else
					raise e
				end
			end

			def reconnect
				connect(@host,@port)
			end

			def log(severity,msg)
				tries ||= 0
				len = [@service.length + severity.length + msg.length + 3].pack(Ci)
				@socket.write "#{len}#{len}:#{@service}:#{severity}:#{msg}"
			rescue Exception => e
				if tries < 3
					tries += 1
					@socket.close if @socket and !@socket.closed?
					@socket = nil
					select(nil,nil,nil,tries) if tries > 0
					reconnect
					retry
				else
					raise e
				end
			end

			def close
				@socket.close
			end

			def closed?
				@socket.closed?
			end

		end
	end
end
