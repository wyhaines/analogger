require 'tmpdir'
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
      
      ConnectionFailureTimeout = 600
      MaxFailureCount = (2**(0.size * 8 -2) -1) # Max integer -- i.e. really big
      PersistentQueueLimit = 10485760
      RamQueueLimit = 129152
      ReconnectThrottleInterval = 2
      
      UnauthenticatedLog = <<ECODE.freeze
def log(severity, msg)
  # 
File.open("/tmp/a.out","a+") {|fh| fh.puts "client: unauthenticated log"}
end
ECODE

      AuthenticatedLog = <<'ECODE'.freeze
def log(severity,msg)
File.open("/tmp/a.out","a+") {|fh| fh.puts "client: authenticated log"}
  len = [@service.length + severity.length + msg.length + 3].pack(Ci)
File.open("/tmp/a.out","a+") {|fh| fh.puts "client: authenticated log #{len}"}
  @socket.write "#{len}#{len}:#{@service}:#{severity}:#{msg}"
File.open("/tmp/a.out","a+") {|fh| fh.puts "client: authenticated log #{len}#{len}:#{@service}:#{severity}:#{msg}"}
rescue Exception => e
  @authenticated = false
  # TODO:  Add code to deal with connection failure
end
ECODE

    #----- Various class accessors -- use these to set defaults

      def self.connection_failure_timeout
        @connection_failure_timeout || ConnectionFailureTimeout
      end
      
      def self.connection_failure_timeout=(val)
        @connection_failure_timeout = val.to_i
      end

      def self.max_failure_count
        @max_failure_count || MaxFailureCount
      end

      def self.max_failure_count=(val)
        @max_failure_count = val.to_i
      end

      def self.ram_queue_limit
        @ram_queue_limit || RamQueueLimit
      end
      
      def self.ram_queue_limit=(val)
        @ram_queue_limit = val.to_i
      end
      
      def self.persistent_queue_limit
        @persistent_queue_limit || PersistentQueueLimit
      end
      
      def self.persistent_queue_limit=(val)
        @persistent_queue_limit = val.to_i
      end

      def self.tmpdir
        @tmpdir || Dir.tmpdir
      end
      
      def self.tmpdir=(val)
        @tmpdir = val
      end

      def self.reconnect_throttle_interval
        @reconnect_throttle_interval || ReconnectThrottleInterval
      end
      
      def self.reconnect_throttle_interval=(val)
        @reconnect_throttle_interval = val.to_i
      end

    #-----

      def initialize(service = 'default', host = '127.0.0.1' , port = 6766, key = nil)
        @service = service.to_s
        @key = key
        @host = host
        @port = port
        klass = self.class
        @connection_failure_timeout = klass.connection_failure_timeout
        @max_failure_count = klass.max_failure_count
        @ram_queue_limit = klass.ram_queue_limit
        @persistent_queue_limit = klass.persistent_queue_limit
        @tmpdir = klass.tmpdir
        @ram_queue_size = 0
        @authenticated = false

        clear_failure
        eval(AuthenticatedLog)

        connect(host,port)
      end

    #----- Various instance accessors

      def connection_failure_timeout
        @connection_failure_timeout
      end

      def connection_failure_timeout=(val)
        @connection_failure_timeout = val.to_i
      end

      def max_failure_count
        @max_failure_count
      end

      def max_failure_count=(val)
        @max_failure_count = val.to_i
      end

      def ram_queue_limit
        @ram_queue_limit
      end

      def ram_queue_limit=(val)
        @ram_queue_limit = val.to_i
      end

      def persistent_queue_limit
        @persistent_queue_limit
      end

      def persistent_queue_limit=(val)
        @persistent_queue_limit = val.to_i
      end

      def tmpdir
        @tmpdir
      end

      def tmpdir=(val)
        @tmpdir = val
      end

      def reconnect_throttle_interval
        @reconnect_throttle_interval
      end
      
      def reconnect_throttle_interval=(val)
        @reconnect_throttle_interval = val.to_i
      end

    #----- The meat of the client

      def connect(host,port)
puts "connect"
        @socket = open_connection(host, port)
puts "connect open"
        send_authentication
puts "connect send"
        clear_failure
      rescue Exception => e
puts "connect exception #{e}"
        register_failure
puts "connect register"
        close_connection
puts "connect close"
        raise e if fail_connect?
      end

      private

      def open_connection(host, port)
        socket = Socket.new(AF_INET,SOCK_STREAM,0)
        sockaddr = Socket.pack_sockaddr_in(port,host)
        socket.connect(sockaddr)
        socket
      end

      def close_connection
        @socket.close if @socket and !@socket.closed?
      end

      def register_failure
        @failed_at ||= Time.now
        @failure_count += 1
      end

      def fail_connect?
        failed_too_many? || failed_too_long?
      end

      def failed?
        !@failed_at.nil?
      end

      def failed_too_many?
        @failure_count > @max_failure_count
      end

      def failed_too_long?
        failed? && ( @failed_at + @connection_failure_timeout ) < Time.now
      end

      def clear_failure
        @failed_at = nil
        @failure_count = 0
      end

      def send_authentication
puts "send_authentication"
        log(Cauthentication, "#{@key}")
puts "send_authentication log"
        response = @socket.read
puts "send_authentication response"
        if response =~ /accepted/
puts "send_authentication parse authenticated"
          eval(AuthenticatedLog)
        else
puts "send_authentication parse unauthenticated"

          eval(UnauthenticatedLog)
        end
      end

      public

      def authenticated?
        @authenticated
      end

      def reconnect
        connect(@host,@port)
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
