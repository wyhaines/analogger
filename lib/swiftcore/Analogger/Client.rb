require 'tmpdir'
require 'socket'

include Socket::Constants

module Swiftcore
  class Analogger

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

      class FailedToAuthenticate < StandardError
        def initialize(hots = "UNK", port = 6766)
          super("Failed to authenticate to the Analogger server at #{destination}:#{port}")
        end
      end

      Cauthentication = 'authentication'.freeze
      Ci = 'i'.freeze

      MaxMessageLength = 8192
      MaxLengthBytes = MaxMessageLength.to_s.length
      Semaphore = "||"
      ConnectionFailureTimeout = 86400 * 2 # Log locally for a long time if Analogger server goes down.
      MaxFailureCount = (2**(0.size * 8 - 2) - 1) # Max integer -- i.e. really big
      PersistentQueueLimit = 10737412742 # Default to allowing around 10GB temporary local log storage
      ReconnectThrottleInterval = 0.1

      def log(severity, msg)
        if @destination == :local
          # Log locally. The reason can be authentication failure or connection failure.
          # The end result is the same. We can't send logs to the server, so we write them
          # locally. The default behavior is to push them into a local queue.
          # If a connection is established, but the local log still has content, a thread
          # will be started to drain the local log as quickly as possible. When it is
          # fully drained, the client will switch to logging remotely directly.
          # For this reason, logging to a local log is synchronized by a mutex so that the
          # log writing to the local file can be paused when necessary.
          @log_throttle.synchronize do
            _local_log(@service, severity, msg)
          end
        else
          _remote_log(@service, severity, msg)
        end
      rescue Exception
        @authenticated = false
        setup_local_logging
        setup_reconnect_thread
      end

    #----- Various class accessors -- use these to set defaults

      def self.connection_failure_timeout
        @connection_failure_timeout ||= ConnectionFailureTimeout
      end

      def self.connection_failure_timeout=(val)
        @connection_failure_timeout = val.to_i
      end

      def self.max_failure_count
        @max_failure_count ||= MaxFailureCount
      end

      def self.max_failure_count=(val)
        @max_failure_count = val.to_i
      end

      def self.persistent_queue_limit
        @persistent_queue_limit ||= PersistentQueueLimit
      end

      def self.persistent_queue_limit=(val)
        @persistent_queue_limit = val.to_i
      end

      def self.tmplog
        @tmplog
      end

      def self.tmplog=(val)
        @tmplog = val
      end

      def self.reconnect_throttle_interval
        @reconnect_throttle_interval ||= ReconnectThrottleInterval
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
        @persistent_queue_limit = klass.persistent_queue_limit
        @authenticated = false
        @log_throttle = Mutex.new
        @total_count = 0
        @logfile = nil
        @swamp_drainer = nil

        clear_failure

        connect
      end

    #----- Various instance accessors

      def total_count
        @total_count
      end

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

      def tmplog_prefix
        File.join(Dir.tmpdir, "analogger-SERVICE-PID.log")
      end

      def tmplog
        @tmplog ||= tmplog_prefix.gsub(/SERVICE/, @service).gsub(/PID/,$$.to_s)
      end

      def tmplogs
        Dir[tmplog_prefix.gsub(/SERVICE/, @service).gsub(/PID/,'*')].sort_by {|f| File.mtime(f)}
      end

      def tmplog=(val)
        @tmplog = val
      end

      def reconnect_throttle_interval
        @reconnect_throttle_interval ||= self.class.reconnect_throttle_interval
      end

      def reconnect_throttle_interval=(val)
        @reconnect_throttle_interval = val.to_i
      end

    #----- The meat of the client

      def connect
        @socket = open_connection(@host, @port)
        authenticate
        raise FailedToAuthenticate(@host, @port) unless authenticated?
        clear_failure
        if there_is_a_swamp?
          drain_the_swamp
        else
          setup_remote_logging
        end
      rescue Exception => e
        register_failure
        close_connection
        setup_local_logging
        raise e if fail_connect?
      end

      private

      def setup_local_logging
        @log_throttle.synchronize do
          unless @logfile && !@logfile.closed?
            @logfile = File.open(tmplog,"a+")
            @logfile.puts "##### START"
            @destination = :local
          end
        end
      end

      def setup_remote_logging
        @destination = :remote
      end

      def setup_reconnect_thread
        @reconnection_thread = Thread.new do
          while true
            sleep reconnect_throttle_interval
            connect rescue nil
            break if @socket && !closed?
          end
          @reconnection_thread = nil
        end
      end

      def _remote_log(service, severity, message)
        @total_count += 1
        len = MaxLengthBytes + MaxLengthBytes + service.length + severity.length + message.length + 3
        ll = sprintf("%0#{MaxLengthBytes}i%0#{MaxLengthBytes}i", len, len)
        @socket.write "#{ll}:#{service}:#{severity}:#{message}"
      end

      def _local_log(service, severity, message)
        # Convert newlines to a different marker so that log messages can be stuffed onto a single file line.
        @logfile.puts "#{service}:#{severity}:#{message.gsub(/\n/,"\x00\x00")}"
      end

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

      def authenticate
        begin
          _remote_log(@service, Cauthentication, "#{@key}")
          response = @socket.gets
        rescue Exception
          response = nil
        end

        if response && response =~ /accepted/
          @authenticated = true
        else
          @authenticated = false
        end
      end

      def there_is_a_swamp?
        tmplogs.each do |logfile|
          break true if FileTest.exist?(logfile) && File.size(logfile) > 0
        end
      end

      def drain_the_swamp
        unless @swamp_drainer
          @swap_drainer = Thread.new { _drain_the_swamp }
        end
      end

      def _drain_the_swamp
        # As soon as we start emptying the local log file, ensure that no data
        # gets missed because of IO buffering. Otherwise, during high rates of
        # message sending, it is possible to get an EOF on file reading, and
        # assume all data has been sent, when there are actually records which
        # are buffered and just haven't been written yet.
        @logfile && ( @logfile.sync = true )
        @logfile && @logfile.fdatasync rescue @logfile.fsync

        # Guard against race conditions or other weird cases where the local
        # log file may unexpectedly have gone missing.
        return unless File.exist? tmplog

        tmplogs.each do |logfile|
          buffer = ''

          File.open(logfile) do |fh|
            logfile_not_empty = true
            while logfile_not_empty
              @log_throttle.synchronize do
                begin
                  buffer << fh.read_nonblock(8192) unless closed?
                rescue EOFError
                  File.unlink(tmplog)
                  setup_remote_logging
                  logfile_not_empty = false
                end
              end
              records = buffer.scan(/^.*?\n/)
              buffer = buffer[(records.inject(0){|n,e| n += e.length})..-1] # truncate buffer
              records.each_index do |n|
                record = records[n]
                next if record =~ /^\#/
                service, severity, msg = record.split(":",3)
                msg = msg.chomp.gsub(/\x00\x00/,"\n")
                begin
                  _remote_log(service, severity, msg)
                rescue
                  # FAIL while draining the swamp. Just reset the buffer from wherever we are, and
                  # keep trying, after a short sleep to allow for recovery.
                  new_buffer = ''
                  records[n..-1].each {|r| new_buffer << r}
                  new_buffer << buffer
                  buffer = new_buffer
                  sleep 1
                end
              end
            end
          end
          if tmplog != logfile
            File.unlink logfile
          end
        end

        @swamp_drainer = nil
      rescue Exception => e
          puts "ERROR SENDING LOCALLY SAVED LOGS: #{e}\n#{e.backtrace.inspect}"
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
