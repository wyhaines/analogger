# frozen_string_literal: true

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
        def initialize(_hots = -'UNK', port = 6766)
          super("Failed to authenticate to the Analogger server at #{destination}:#{port}")
        end
      end

      MAX_MESSAGE_LENGTH = 8192
      MAX_LENGTH_BYTES = MAX_MESSAGE_LENGTH.to_s.length
      CONNECTION_FAILURE_TIMEOUT = 86_400 * 2 # Log locally for a long time if Analogger server goes down.
      MAX_FAILURE_COUNT = (2**(0.size * 8 - 2) - 1) # Max integer -- i.e. really big
      PERSISTENT_QUEUE_LIMIT = 10_737_412_742 # Default to allowing around 10GB temporary local log storage
      RECONNECT_THROTTLE_INTERVAL = 0.1

      def log(severity, msg)
        if @destination == :local
          _local_log(@service, severity, msg)
        else
          _remote_log(@service, severity, msg)
        end
      rescue StandardError
        @authenticated = false
        setup_local_logging
        setup_reconnect_thread
      end

      #----- Various class accessors -- use these to set defaults

      def self.connection_failure_timeout
        @connection_failure_timeout ||= CONNECTION_FAILURE_TIMEOUT
      end

      def self.connection_failure_timeout=(val)
        @connection_failure_timeout = val.to_i
      end

      def self.max_failure_count
        @max_failure_count ||= MAX_FAILURE_COUNT
      end

      def self.max_failure_count=(val)
        @max_failure_count = val.to_i
      end

      def self.persistent_queue_limit
        @persistent_queue_limit ||= PERSISTENT_QUEUE_LIMIT
      end

      def self.persistent_queue_limit=(val)
        @persistent_queue_limit = val.to_i
      end

      class << self
        attr_reader :tmplog
      end

      class << self
        attr_writer :tmplog
      end

      def self.reconnect_throttle_interval
        @reconnect_throttle_interval ||= RECONNECT_THROTTLE_INTERVAL
      end

      def self.reconnect_throttle_interval=(val)
        @reconnect_throttle_interval = val.to_i
      end

      #-----

      def initialize(service = -'default', host = -'127.0.0.1', port = 6766, key = nil)
        @service = service.to_s
        @key = key
        @host = host
        @port = port
        @socket = nil
        klass = self.class
        @connection_failure_timeout = klass.connection_failure_timeout
        @max_failure_count = klass.max_failure_count
        @persistent_queue_limit = klass.persistent_queue_limit
        @destination = nil
        @reconnection_thread = nil
        @authenticated = false
        @total_count = 0
        @logfile = nil
        @swamp_drainer = nil

        clear_failure

        connect
      end

      #----- Various instance accessors

      attr_reader :total_count

      attr_reader :connection_failure_timeout

      def connection_failure_timeout=(val)
        @connection_failure_timeout = val.to_i
      end

      attr_reader :max_failure_count

      def max_failure_count=(val)
        @max_failure_count = val.to_i
      end

      attr_reader :ram_queue_limit

      def ram_queue_limit=(val)
        @ram_queue_limit = val.to_i
      end

      attr_reader :persistent_queue_limit

      def persistent_queue_limit=(val)
        @persistent_queue_limit = val.to_i
      end

      def tmplog_prefix
        File.join(Dir.tmpdir, -'analogger-SERVICE-PID.log')
      end

      def tmplog
        @tmplog ||= tmplog_prefix.gsub(/SERVICE/, @service).gsub(/PID/, Process.pid.to_s)
      end

      def tmplogs
        Dir[tmplog_prefix.gsub(/SERVICE/, @service).gsub(/PID/, -'*')].sort_by { |f| File.mtime(f) }
      end

      attr_writer :tmplog

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
      rescue StandardError => e
        register_failure
        close_connection
        setup_reconnect_thread unless @reconnection_thread && Thread.current == @reconnection_thread
        setup_local_logging
        raise e if fail_connect?
      end

      private

      def setup_local_logging
        return if @logfile && !@logfile.closed?

        @logfile = File.open(tmplog, -'a+')
        @destination = :local
      end

      def setup_remote_logging
        @destination = :remote
      end

      def setup_reconnect_thread
        return if @reconnection_thread

        @reconnection_thread = Thread.new do
          loop do
            sleep reconnect_throttle_interval
            begin
              connect
            rescue StandardError
              nil
            end
            break if @socket && !closed?
          end
          @reconnection_thread = nil
        end
      end

      def _remote_log(service, severity, message)
        @total_count += 1
        len = MAX_LENGTH_BYTES + MAX_LENGTH_BYTES + service.length + severity.length + message.length + 3
        ll = format("%0#{MAX_LENGTH_BYTES}i%0#{MAX_LENGTH_BYTES}i", len, len)
        @socket.write "#{ll}:#{service}:#{severity}:#{message}"
      end

      def _local_log(service, severity, message)
        # Convert newlines to a different marker so that log messages can be stuffed onto a single file line.
        @logfile.flock File::LOCK_EX
        @logfile.puts "#{service}:#{severity}:#{message.gsub(/\n/, "\x00\x00")}"
      ensure
        @logfile.flock File::LOCK_UN
      end

      def open_connection(host, port)
        socket = Socket.new(AF_INET, SOCK_STREAM, 0)
        sockaddr = Socket.pack_sockaddr_in(port, host)
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
        failed? && (@failed_at + @connection_failure_timeout) < Time.now
      end

      def clear_failure
        @failed_at = nil
        @failure_count = 0
      end

      def authenticate
        begin
          _remote_log(@service, -'authentication', @key.to_s)
          response = @socket.gets
        rescue StandardError
          response = nil
        end

        @authenticated = if response && response =~ /accepted/
                           true
                         else
                           false
                         end
      end

      def there_is_a_swamp?
        tmplogs.each do |logfile|
          break true if FileTest.exist?(logfile) && File.size(logfile).positive?
        end
      end

      def drain_the_swamp
        @swap_drainer = Thread.new { _drain_the_swamp } unless @swamp_drainer
      end

      def non_blocking_lock_on_file_handle(file_handle)
        file_handle.flock(File::LOCK_EX | File::LOCK_NB) ? yield : false
      ensure
        file_handle.flock File::LOCK_UN
      end

      def _drain_the_swamp
        # As soon as we start emptying the local log file, ensure that no data
        # gets missed because of IO buffering. Otherwise, during high rates of
        # message sending, it is possible to get an EOF on file reading, and
        # assume all data has been sent, when there are actually records which
        # are buffered and just haven't been written yet.
        @logfile && (@logfile.sync = true)

        tmplogs.each do |logfile|
          buffer = +''

          FileTest.exist?(logfile) && File.open(logfile) do |fh|
            non_blocking_lock_on_file_handle(fh) do # Only one process should read a given file.
              begin; fh.fdatasync; rescue StandardError; fh.fsync; end
              logfile_not_empty = true
              while logfile_not_empty
                begin
                  buffer << fh.read_nonblock(8192) unless closed?
                rescue EOFError
                  logfile_not_empty = false
                end
                records = buffer.scan(/^.*?\n/)
                buffer = buffer[(records.inject(0) { |n, e| n + e.length })..] # truncate buffer
                records.each_index do |n|
                  record = records[n]
                  next if record =~ /^\#/

                  service, severity, msg = record.split(-':', 3)
                  msg = msg.chomp.gsub(/\x00\x00/, "\n")
                  begin
                    _remote_log(service, severity, msg)
                  rescue StandardError
                    # FAIL while draining the swamp. Just reset the buffer from wherever we are, and
                    # keep trying, after a short sleep to allow for recovery.
                    new_buffer = +''
                    records[n..].each { |r| new_buffer << r }
                    new_buffer << buffer
                    buffer = new_buffer
                    sleep 1
                  end
                end
              end
              File.unlink logfile
            end
            setup_remote_logging if tmplog == logfile
          end
        end

        @swamp_drainer = nil
      rescue StandardError => e
        warn "ERROR SENDING LOCALLY SAVED LOGS: #{e}\n#{e.backtrace.inspect}"
      end

      public

      def authenticated?
        @authenticated
      end

      def reconnect
        connect(@host, @port)
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
