# frozen_string_literal: true

require 'socket'
require 'swiftcore/Analogger/version'
require 'async'
require 'async/io/trap'
require 'async/io/host_endpoint'
require 'async/io/stream'
require 'benchmark'
require 'swiftcore/Analogger/AnaloggerProtocol'

module Async
  # Monkey Patch to add a convenience method for defining single use or periodic timers
  class Task
    def add_timer(interval: 0, periodic: true)
      async do |subtask|
        loop do
          subtask.sleep(interval)
          yield
          break unless periodic
        end
      end
    end
  end

  module IO
    # Monkey Patch because a Trap should be able to report what it's trapping.
    class Trap
      attr_reader :name

      def to_s
        "Async::IO::Trap(#{name})"
      end
    end
  end
end

module Swiftcore
  class Analogger
    EXEC_ARGUMENTS = [File.expand_path($PROGRAM_NAME), *ARGV].freeze

    DEFAULT_SEVERITY_LEVELS = [
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
      def handle_daemonize
        daemonize if @config[-'daemonize']
        File.open(@config[-'pidfile'], -'w+') { |fh| fh.puts Process.pid } if @config[-'pidfile']
      end

      def initialize_start_variables(config: {})
        @config = config
        @logs = Hash.new { |h, k| h[k] = new_log(facility: k) }
        @queue = Hash.new { |h, k| h[k] = [] }
        @rcount = 0
        @wcount = 0
        @server = nil
      end

      def install_int_term_trap(task: nil, server: nil)
        int_trap = Async::IO::Trap.new(:INT)
        term_trap = Async::IO::Trap.new(:TERM)
        [int_trap, term_trap].each do |trap|
          trap.install!
          task.async do |_handler_task|
            trap.wait

            write_queue if any_in_queue?
            flush_queue
            cleanup
            trap.default!
            Async.logger.info(server) do |buffer|
              buffer.puts "Caught #{trap}"
              buffer.puts 'Stopping all tasks...'
              task.print_hierarchy(buffer)
              buffer.puts '', 'Reactor Hierarchy'
              task.reactor.print_hierarchy(buffer)
            end
            task.stop
          end
        end
      end

      def install_hup_trap(task: nil)
        hup_trap = Async::IO::Trap.new(:HUP)
        hup_trap.install!
        task.async do |_handler_task|
          loop do
            hup_trap.wait
            cleanup_and_reopen
          end
        end
      end

      def install_usr2_trap(task: nil, server: nil)
        usr2_trap = Async::IO::Trap.new(:USR2)
        usr2_trap.install!
        task.async do |_handler_task|
          loop do
            usr2_trap.wait
            write_queue if any_in_queue?
            flush_queue
            cleanup
            Async.logger.info(server) do |buffer|
              buffer.puts "Caught #{usr2_trap}"
              buffer.puts 'Stopping all tasks...'
              task.print_hierarchy(buffer)
              buffer.puts '', 'Reactor Hierarchy'
              task.reactor.print_hierarchy(buffer)
              buffer.puts '', "Restarting with: #{EXEC_ARGUMENTS}"
            end
            exec(*EXEC_ARGUMENTS)
          end
        end
      end

      def start(config, protocol = AnaloggerProtocol)
        initialize_start_variables(config: config)
        handle_daemonize
        postprocess_config_load
        check_config_settings
        populate_logs
        set_config_defaults

        endpoint = Async::IO::Endpoint.tcp(@config[-'host'], @config[-'port'])

        Async do
          endpoint.bind do |server, task|
            install_int_term_trap(task: task, server: server)
            install_hup_trap(task: task)
            install_usr2_trap(task: task, server: server)

            task.add_timer(interval: 1) { Analogger.update_now }
            task.add_timer(interval: @config[-'interval']) { write_queue }
            task.add_timer(interval: @config[-'syncinterval']) { flush_queue }

            server.listen(128)

            server.accept_each do |peer|
              stream = Async::IO::Stream.new(peer)
              handler = protocol.new(stream: stream, peer: peer)
              handler.receive until stream.closed?
            end
          end
        end
      end

      def daemonize
        Daemons.daemonize
      rescue NotImplementedError
        puts "Platform (#{RUBY_PLATFORM}) does not appear to support fork/setsid; skipping"
      end

      def new_log(facility: -'default',
                  levels: @config[-'levels'] || DEFAULT_SEVERITY_LEVELS,
                  raw_destination: @config[-'default_log'],
                  destination: @config[-'default_log'],
                  cull: true,
                  type: -'file',
                  options: [-'ab+'])
        Log.new(service: facility, levels: levels, raw_destination: raw_destination, destination: destination, cull: cull, type: type, options: options)
      end

      def cleanup
        @logs.each do |_service, l|
          if !l.destination.closed? and l.destination.fileno > 2
            begin
              l.destination.fdatasync
            rescue Errno::EINVAL
              l.destination.flush
            end
          end
          l.destination.close unless l.destination.closed? or l.destination.fileno < 3
        end
      end

      def cleanup_and_reopen
        @logs.each do |_service, l|
          if !l.destination.closed? and l.destination.fileno > 2
            begin
              l.destination.fdatasync
            rescue Errno::EINVAL
              l.destination.flush
            end
          end
          l.destination.reopen(l.raw_destination, *l.options) if l.destination.fileno > 2
          l.destination.reopen(l.raw_destination, *l.options) if l.destination.fileno > 2
        end
      end

      def update_now
        @now = Time.now.strftime(-'%Y/%m/%d %H:%M:%S')
      end

      attr_reader :config

      attr_writer :config

      # Iterate through the logs entries in the configuration file, and create a log entity for each one.
      def populate_logs
        @config[-'logs'].each do |log|
          next unless log[-'service']

          if Array === log[-'service']
            log[-'service'].each do |loglog|
              @logs[loglog] = new_log(facility: loglog,
                                      levels: log[-'levels'],
                                      raw_destination: log[-'logfile'],
                                      destination: logfile_destination(log[-'logfile'], log[-'type'], log[-'options']),
                                      cull: log[-'cull'],
                                      type: log[-'type'],
                                      options: log[-'options'])
            end
          else
            @logs[log[-'service']] = new_log(facility: log[-'service'],
                                             levels: log[-'levels'],
                                             raw_destination: log[-'logfile'],
                                             destination: logfile_destination(log[-'logfile'], log[-'type'], log[-'options']),
                                             cull: log[-'cull'],
                                             type: log[-'type'],
                                             options: log[-'options'])
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
          DEFAULT_SEVERITY_LEVELS
        elsif !(Hash === levels)
          [levels.to_s => true]
        else
          levels
        end
      end

      def check_config_settings
        raise NoPortProvided unless @config[-'port']
        raise BadPort, @config[-'port'] unless @config[-'port'].to_i.positive?
      end

      def set_config_defaults
        @config[-'host'] ||= -'127.0.0.1'
        @config[-'interval'] ||= 1
        @config[-'syncinterval'] ||= 60
        @config[-'syncinterval'] = nil if @config[-'syncinterval'].zero?
        @config[-'default_log'] = @config[-'default_log'].nil? || @config[-'default_log'] == -'-' ? -'STDOUT' : @config[-'default_log']
        @config[-'default_log'] = logfile_destination(@config[-'default_log'])
        @logs[-'default'] = new_log
      end

      def logfile_destination(logfile, type = nil, options = nil)
        type ||= -'file'
        options ||= [-'ab+']
        return logfile if logfile == $stderr or logfile == $stdout
        return logfile.reopen(logfile.path, *options) if logfile.respond_to? :reopen

        if logfile =~ /^STDOUT$/i
          $stdout
        elsif logfile =~ /^STDERR$/i
          $stderr
        else
          klassname = "Swiftcore::Analogger::Destination::#{type.capitalize}"
          unless Object.const_defined?(klassname)
            requirename = "swiftcore/Analogger/destination/#{type.downcase}"
            require "#{requirename}"
          end
          obj = Object.const_get(klassname)
          obj.open(logfile, *options)
        end
      end

      def add_log(log)
        @queue[log.first] << log
        @rcount += 1
      end

      def any_in_queue?
        any = 0
        @queue.each do |service, q|
          next unless (log = @logs[service])

          levels = log.levels
          q.each do |m|
            next unless levels.key?(m[1])

            any += 1
          end
        end
        any.positive? ? any : false
      end

      def write_queue
        initial_state = [nil, nil, 0]
        @queue.each do |service, q|
          last_sv, last_m, last_count = initial_state
          next unless (log = @logs[service])

          lf = log.destination
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
          next unless l.destination.fileno > 2

          begin
            l.destination.fdatasync
          rescue Errno::EINVAL
            l.destination.flush
          end
        end
      end

      def key
        @config[-'key'].to_s
      end
    end

    class Log
      attr_reader :service, :levels, :raw_destination, :destination, :cull, :type, :options

      def initialize(service: nil, levels: [], raw_destination: nil, destination: nil, cull: true, type: -'file', options: [-'ab+'])
        @service = service
        @levels = levels
        @raw_destination = raw_destination
        @destination = destination
        @cull = cull
        @type = type
        @options = options
      end

      def to_s
        "service: #{@service}\nlevels: #{@levels.inspect}\nraw_destination: #{@raw_destination}\ndestination: #{@destination}\ncull: #{@cull}\ntype: #{@type}\noptions: #{@options.inspect}"
      end

      def ==(other)
        other.service == @service &&
            other.levels == @levels &&
            other.raw_destination == @raw_destination &&
            other.cull == @cull &&
            other.type == @type &&
            other.options == @options
      end
    end
  end

  class AnaloggerProtocol < Async::IO::Protocol::Generic
    REGEXP_COLON = /:/.freeze

    LoggerClass = Analogger

    def post_init
      setup
    end
  end
end
