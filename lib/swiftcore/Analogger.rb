# frozen_string_literal: true

require 'socket'
require 'swiftcore/Analogger/version'
require 'async'
require 'async/io/trap'
require 'async/io/host_endpoint'
require 'async/io/stream'
require 'benchmark'
require 'swiftcore/Analogger/AnaloggerProtocol'

module Swiftcore
  class Analogger
    EXEC_ARGUMENTS = [File.expand_path($PROGRAM_NAME), *ARGV].freeze

    DefaultSeverityLevels = [
      -'debug',
      -'info',
      -'warn',
      -'error',
      -'fatal'
    ].each_with_object({}) { |k, h| h[k] = true }

    class NoPortProvided < RuntimeError
      def to_s
        'The port to bind to was not provided.'
      end
    end

    class BadPort < RuntimeError
      def initialize(port)
        @port = port
      end

      def to_s
        "The port provided (#{@port}) is invalid."
      end
    end

    EXIT_SIGNALS = %i[INT TERM].freeze
    RELOAD_SIGNALS = %i[HUP].freeze
    RESTART_SIGNALS = %i[USR2].freeze

    class << self
      def safe_trap(siglist, &operation)
        (Signal.list.keys & siglist).each { |sig| trap(sig, &operation) }
      end

      def start(config, protocol = AnaloggerProtocol)
        @config = config
        daemonize if @config[-'daemonize']
        File.open(@config[-'pidfile'], -'w+') { |fh| fh.puts Process.pid } if @config[-'pidfile']
        @logs = Hash.new { |h, k| h[k] = new_log(k) }
        @queue = Hash.new { |h, k| h[k] = [] }
        postprocess_config_load
        check_config_settings
        populate_logs
        set_config_defaults
        @rcount = 0
        @wcount = 0
        @server = nil
        int_trap = Async::IO::Trap.new(:INT)
        term_trap = Async::IO::Trap.new(:TERM)
        hup_trap = Async::IO::Trap.new(:HUP)
        usr2_trap = Async::IO::Trap.new(:USR2)
        endpoint = Async::IO::Endpoint.tcp(@config[-'host'], @config[-'port'])
        Async do
          # EventMachine.add_shutdown_hook do
          #  write_queue
          #  flush_queue
          #  cleanup
          # end    Is there an equivalent with Async that runs when the reactor shuts down?

          [int_trap, hup_trap, usr2_trap].each(&:install!)

          endpoint.bind do |server, task|
            # Repeating Tasks
            task.async do |subtask|
              loop do
                subtask.sleep 1
                Analogger.update_now
              end
            end

            task.async do |subtask|
              loop do
                subtask.sleep(@config[-'interval'])
                write_queue
              end
            end

            task.async do |subtask|
              loop do
                subtask.sleep(@config[-'syncinterval'])
                flush_queue
              end
            end

            server.listen(128)

            server.accept_each do |peer|
              stream = Async::IO::Stream.new(peer)
              handler = protocol.new(stream, peer)
              handler.receive until stream.closed?
            end
          end
        end
      end

      def daemonize
        if (child_pid = fork)
          puts "PID #{child_pid}" unless @config[-'pidfile']
          exit!
        end
        Process.setsid

        exit if fork
      rescue NotImplementedError
        puts "Platform (#{RUBY_PLATFORM}) does not appear to support fork/setsid; skipping"
      end

      def new_log(facility = -'default', levels = @config[-'levels'] || DefaultSeverityLevels, log = @config[-'default_log'], cull = true)
        Log.new({ -'service' => facility, -'levels' => levels, -'logfile' => log, -'cull' => cull })
      end

      # # Before exiting, try to get any logs that are still in memory handled and written to disk.
      # def handle_pending_and_exit
      #   EventMachine.stop_server(@server)
      #   EventMachine.add_timer(1) do
      #     _handle_pending_and_exit
      #   end
      # end
      #
      # def _handle_pending_and_exit
      #   if any_in_queue?
      #     write_queue
      #     EventMachine.next_tick {_handle_pending_and_exit}
      #   else
      #     EventMachine.stop
      #   end
      # end

      def cleanup
        @logs.each do |_service, l|
          l.logfile.fsync if !l.logfile.closed? and l.logfile.fileno > 2
          l.logfile.close unless l.logfile.closed? or l.logfile.fileno < 3
        end
      end

      def cleanup_and_reopen
        @logs.each do |_service, l|
          l.logfile.fsync if !l.logfile.closed? and l.logfile.fileno > 2
          l.logfile.reopen(l.logfile.path, -'ab+') if l.logfile.fileno > 2
        end
      end

      def update_now
        @now = Time.now.strftime(-'%Y/%m/%d %H:%M:%S')
      end

      attr_reader :config

      attr_writer :config

      def populate_logs
        @config[-'logs'].each do |log|
          next unless log[-'service']

          if Array === log[-'service']
            log[-'service'].each do |loglog|
              @logs[loglog] = new_log(loglog, log[-'levels'], logfile_destination(log[-'logfile']), log[-'cull'])
            end
          else
            @logs[log[-'service']] = new_log(log[-'service'], log[-'levels'], logfile_destination(log[-'logfile']), log[-'cull'])
          end
        end
      end

      def postprocess_config_load
        @config[-'logs'] ||= []
        @config[-'levels'] = normalize_levels(@config[-'levels']) if @config[-'levels']

        @config[-'logs'].each do |log|
          log[-'levels'] = normalize_levels(log[-'levels'])
        end
      end

      def normalize_levels(levels)
        if String === levels and levels =~ /,/
          levels.split(/,/).each_with_object({}) { |k, h| h[k.to_s] = true; }
        elsif Array === levels
          levels.each_with_object({}) { |k, h| h[k.to_s] = true; }
        elsif levels.nil?
          DefaultSeverityLevels
        elsif !(Hash === levels)
          [levels.to_s => true]
        else
          levels
        end
      end

      def check_config_settings
        raise NoPortProvided unless @config[-'port']
        raise BadPort, @config[-'port'] unless @config[-'port'].to_i > 0
      end

      def set_config_defaults
        @config[-'host'] ||= -'127.0.0.1'
        @config[-'interval'] ||= 1
        @config[-'syncinterval'] ||= 60
        @config[-'syncinterval'] = nil if @config[-'syncinterval'] == 0
        @config[-'default_log'] = @config[-'default_log'].nil? || @config[-'default_log'] == -'-' ? -'STDOUT' : @config[-'default_log']
        @config[-'default_log'] = logfile_destination(@config[-'default_log'])
        @logs[-'default'] = new_log
      end

      def logfile_destination(logfile)
        # We're reloading if it's already an IO.
        if logfile.is_a?(IO)
          return $stdout if logfile == $stdout
          return $stderr if logfile == $stderr

          return logfile.reopen(logfile.path, -'ab+')
        end

        if logfile =~ /^STDOUT$/i
          $stdout
        elsif logfile =~ /^STDERR$/i
          $stderr
        else
          File.open(logfile, -'ab+')
        end
      end

      def add_log(log)
        @queue[log.first] << log
        @rcount += 1
      end

      def any_in_queue?
        any = 0
        @queue.each do |_service, q|
          q.each do |m|
            next unless levels.key?(m[1])

            any += 1
          end
        end
        any > 0 ? any : false
      end

      def write_queue
        @queue.each do |service, q|
          last_sv = nil
          last_m = nil
          last_count = 0
          next unless log = @logs[service]

          lf = log.logfile
          cull = log.cull
          levels = log.levels
          q.each do |m|
            next unless levels.key?(m[1])

            if cull
              if m.last == last_m and m[0..1] == last_sv
                last_count += 1
                next
              elsif last_count.positive?
                lf.write_nonblock "#{@now}|#{last_sv.join(-'|')}|Last message repeated #{last_count} times\n"
                last_sv = last_m = nil
                last_count = 0
              end
              lf.write_nonblock "#{@now}|#{m.join(-'|')}\n"
              last_m = m.last
              last_sv = m[0..1]
            else
              lf.write_nonblock "#{@now}|#{m.join(-'|')}\n"
            end
            @wcount += 1
          end
          if cull and last_count.positive?
            lf.write_nonblock "#{@now}|#{last_sv.join(-'|')}|Last message repeated #{last_count} times\n"
          end
        end
        @queue.each { |_service, q| q.clear }
      end

      def flush_queue
        @logs.each_value do |l|
          # if !l.logfile.closed? and l.logfile.fileno > 2
          next unless l.logfile.fileno > 2

          begin
            l.logfile.fdatasync
          rescue StandardError
            l.logfile.fsync
          end
        end
      end

      def key
        @config[-'key'].to_s
      end
    end

    class Log
      attr_reader :service, :levels, :logfile, :cull

      def initialize(spec)
        @service = spec[-'service']
        @levels = spec[-'levels']
        @logfile = spec[-'logfile']
        @cull = spec[-'cull']
      end

      def to_s
        "service: #{@service}\nlevels: #{@levels.inspect}\nlogfile: #{@logfile}\ncull: #{@cull}\n"
      end

      def ==(other)
        other.service == @service &&
            other.levels == @levels &&
            other.logfile == @logfile &&
            other.cull == @cull
      end
    end
  end

  class AnaloggerProtocol < Async::IO::Protocol::Generic
    Rcolon = /:/.freeze

    LoggerClass = Analogger

    def post_init
      setup
    end
  end
end
