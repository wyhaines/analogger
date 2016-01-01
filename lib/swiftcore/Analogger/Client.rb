require 'socket'
require 'thread'
require 'tmpdir'

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
		# Analogger severity levels are the same as in the standard Ruby.

    DrainTimeslice = 0.005
    DrainMinimum = 2

    # TODO: This whole mess isn't remotely threadsafe a the moment.

		class Client
			Cauthentication = 'authentication'.freeze
			Ci = 'i'.freeze

			def initialize( service = 'default', host = '127.0.0.1' , port = 6766, key = nil, local_log_file = File.join(Dir.tmpdir,"analogger_#{$$}_#{Time.now.to_i}.log") )
				@service = service.to_s
				@key = key
				@host = host
				@port = port
				@local_log_file = local_log_file
				@local_log_position_file = File.join( File.dirname(local_log_file), "#{File.basename(local_log_file).gsub(/#{File.extname(local_log_file)}/,'')}.pos")
				@socket = nil
				@connected = false
				@drain_mutex = Mutex.new
        @file_mutex = Mutex.new
				@local_log_is_drained = true
        open_local_log if File.exist?(@local_log_file) && File.size(@local_log_file) > 0 && read_local_log_pos > 0
				connect( host, port )
			end

			def connect( host, port )
				tries ||= 0
				@socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
				sockaddr = Socket.pack_sockaddr_in( port, host )
				@socket.connect( sockaddr )
				log( Cauthentication, "#{@key}" )
				@connected = true
			rescue Exception => e
				@connected = false
				if tries < 3
					tries += 1
					@socket.close if @socket and !@socket.closed?
					@socket = nil
					select( nil, nil, nil, tries * 0.2 ) if tries > 0
					retry
				else
					if @local_log_file
						open_local_log
					else
					  raise e
					end
				end
			end

			def reconnect
				connect( @host, @port )
			end

			def open_local_log
				@local_log = FIle.open( @local_log_file, "a+" ) unless @local_log
				@local_log_pos = read_local_log_pos
			end

      def read_local_log_pos
        @file_mutex.synchronize do
          File.exist?( @local_log_file_pos ) ? File.read( @local_log_file_pos ).chomp.to_i : 0
        end
      end

      def write_local_log_pos( pos )
        @file_mutex.synchronize do
          File.open( @local_log_file_pos, "w+" ) {|fh| fh.write pos}
        end
      end

			def log( severity, msg )
				tries ||= 0
				len = [ @service.length + severity.length + msg.length + 3 ].pack( Ci )
				message = "#{len}#{len}:#{@service}:#{severity}:#{msg}"
				if @local_log
          @file_mutex.synchronize do
					  @local_log.write message
          end
				end

				if @socket && @local_log
					drain_local_log
				elsif @socket
				  @socket.write message
				end
			rescue Exception => e
				if tries < 3
					tries += 1
					@socket.close if @socket and !@socket.closed?
					@socket = nil
					select( nil, nil, nil, tries ) if tries > 0
					reconnect
					retry
				else
					raise e
				end
			end

			def drain_local_log
				@drain_mutex.synchronize do
          pos = read_local_log_pos
          if @local_log && ( pos < @local_log.pos )
            @local_log.seek pos
            now = Time.now.to_f
            count = 0
            while ( count < DrainMinimum ) && ( Time.now.to_f < ( now + DrainTimeslice ) )
              rec = @local_log.readline.chomp
              @socket.write rec
              count += 1
              if @local_log.pos == @local_log.size
                write_local_log_pos 0
                @local_log.close
                @local_log = nil
                break
              else
                write_local_log_pos @local_log.pos
              end
            end
          end

          if @local_log # It must not have been drained
            Thread.new do
              sleep 0.1
              drain_local_log
            end
          end
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
