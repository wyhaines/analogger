require 'socket'
require 'swiftcore/Analogger/version'
require 'eventmachine'
require 'benchmark'
require 'swiftcore/Analogger/AnaloggerProtocol'

module Swiftcore
  class Analogger
    EXEC_ARGUMENTS = [File.expand_path(Process.argv0), *ARGV]

    C_colon = ':'.freeze
    C_bar = '|'.freeze
    Ccull = 'cull'.freeze
    Cdaemonize = 'daemonize'.freeze
    Cdefault = 'default'.freeze
    Cdefault_log = 'default_log'.freeze
    Chost = 'host'.freeze
    Cinterval = 'interval'.freeze
    Ckey = 'key'.freeze
    Clogfile = 'logfile'.freeze
    Clogs = 'logs'.freeze
    Cport = 'port'.freeze
    Csecret = 'secret'.freeze
    Cservice = 'service'.freeze
    Clevels = 'levels'.freeze
    Csyncinterval = 'syncinterval'.freeze
    Cpidfile = 'pidfile'.freeze
    DefaultSeverityLevels = ['debug','info','warn','error','fatal'].inject({}){|h,k|h[k]=true;h}
    TimeFormat = '%Y/%m/%d %H:%M:%S'.freeze

    class NoPortProvided < Exception; def to_s; "The port to bind to was not provided."; end; end
    class BadPort < Exception
      def initialize(port)
        @port = port
      end

      def to_s; "The port provided (#{@port}) is invalid."; end
    end

    EXIT_SIGNALS = %w[INT TERM]
    RELOAD_SIGNALS = %w[HUP]
    RESTART_SIGNALS = %w[USR2]

    class << self
      def safe_trap(siglist, &operation)
        (Signal.list.keys & siglist).each {|sig| trap(sig, &operation)}
      end

      def start(config,protocol = AnaloggerProtocol)
        @config = config
        daemonize if @config[Cdaemonize]
        File.open(@config[Cpidfile],'w+') {|fh| fh.puts $$} if @config[Cpidfile]
        @logs = Hash.new {|h,k| h[k] = new_log(k)}
        @queue = Hash.new {|h,k| h[k] = []}
        postprocess_config_load
        check_config_settings
        populate_logs
        set_config_defaults
        @rcount = 0
        @wcount = 0
        @server = nil
        safe_trap(EXIT_SIGNALS) {handle_pending_and_exit}
        safe_trap(RELOAD_SIGNALS) {cleanup_and_reopen}
        safe_trap(RESTART_SIGNALS) {exec(*EXEC_ARGUMENTS)}

        #####
        # This is gross.  EM needs to change so that it defaults to the faster
        # platform specific methods, allowing the user the option to downgrade
        # to a simple select() loop if they have a good reason for it.
        #
        EventMachine.epoll rescue nil
        EventMachine.kqueue rescue nil
        #
        # End of gross.
        #
        # TODO: The above was written YEARS ago. See if EventMachine is smarter, now.
        #####

        EventMachine.set_descriptor_table_size(4096)
        EventMachine.run {
          EventMachine.add_shutdown_hook do
            write_queue
            flush_queue
            cleanup
          end
          @server = EventMachine.start_server @config[Chost], @config[Cport], protocol
          EventMachine.add_periodic_timer(1) {Analogger.update_now}
          EventMachine.add_periodic_timer(@config[Cinterval]) {write_queue}
          EventMachine.add_periodic_timer(@config[Csyncinterval]) {flush_queue}
        }
        exit
      end

      def daemonize
        if (child_pid = fork)
          puts "PID #{child_pid}" unless @config[Cpidfile]
          exit!
        end
        Process.setsid

        exit if fork

      rescue NotImplementedError
        puts "Platform (#{RUBY_PLATFORM}) does not appear to support fork/setsid; skipping"
      end

      def new_log(facility = Cdefault, levels = @config[Clevels] || DefaultSeverityLevels, log = @config[Cdefault_log], cull = true)
        Log.new({Cservice => facility, Clevels => levels, Clogfile => log, Ccull => cull})
      end

      # Before exiting, try to get any logs that are still in memory handled and written to disk.
      def handle_pending_and_exit
        EventMachine.stop_server(@server)
        EventMachine.add_timer(1) do
          _handle_pending_and_exit
        end
      end

      def _handle_pending_and_exit
        if any_in_queue?
          write_queue
          EventMachine.next_tick {_handle_pending_and_exit}
        else
          EventMachine.stop
        end
      end

      def cleanup
        @logs.each do |service,l|
          l.logfile.fsync if !l.logfile.closed? and l.logfile.fileno > 2
          l.logfile.close unless l.logfile.closed? or l.logfile.fileno < 3
        end
      end

      def cleanup_and_reopen
        @logs.each do |service,l|
          l.logfile.fsync if !l.logfile.closed? and l.logfile.fileno > 2
          #l.logfile.close unless l.logfile.closed? or l.logfile.fileno < 3
          l.logfile.reopen(l.logfile.path, 'ab+') if l.logfile.fileno > 2
        end
      end

      def update_now
        @now = Time.now.strftime(TimeFormat)
      end

      def config
        @config
      end

      def config=(conf)
        @config = conf
      end

      def populate_logs
        @config[Clogs].each do |log|
          next unless log[Cservice]
          if Array === log[Cservice]
            log[Cservice].each do |loglog|
              @logs[loglog] = new_log(loglog,log[Clevels],logfile_destination(log[Clogfile]),log[Ccull])
            end
          else
            @logs[log[Cservice]] = new_log(log[Cservice],log[Clevels],logfile_destination(log[Clogfile]),log[Ccull])
          end
        end
      end

      def postprocess_config_load
        @config[Clogs] ||= []
        if @config[Clevels]
          @config[Clevels] = normalize_levels(@config[Clevels])
        end

        @config[Clogs].each do |log|
          log[Clevels] = normalize_levels(log[Clevels])
        end
      end

      def normalize_levels(levels)
        if String === levels and levels =~ /,/
          levels.split(/,/).inject({}) {|h,k| h[k.to_s] = true; h}
        elsif Array === levels
          levels.inject({}) {|h,k| h[k.to_s] = true; h}
        elsif levels.nil?
          DefaultSeverityLevels
        elsif !(Hash === levels)
          [levels.to_s => true]
        else
          levels
        end
      end

      def check_config_settings
        raise NoPortProvided unless @config[Cport]
        raise BadPort.new(@config[Cport]) unless @config[Cport].to_i > 0
      end

      def set_config_defaults
        @config[Chost] ||= '127.0.0.1'
        @config[Cinterval] ||= 1
        @config[Csyncinterval] ||= 60
        @config[Csyncinterval] = nil if @config[Csyncinterval] == 0
        @config[Cdefault_log] = @config[Cdefault_log].nil? || @config[Cdefault_log] == '-' ? 'STDOUT' : @config[Cdefault_log]
        @config[Cdefault_log] = logfile_destination(@config[Cdefault_log])
        @logs['default'] = new_log
      end

      def logfile_destination(logfile)
        # We're reloading if it's already an IO.
        if logfile.is_a?(IO)
          return $stdout if logfile == $stdout
          return $stderr if logfile == $stderr
          return logfile.reopen(logfile.path, 'ab+')
        end

        if logfile =~ /^STDOUT$/i
          $stdout
        elsif logfile =~ /^STDERR$/i
          $stderr
        else
          File.open(logfile,'ab+')
        end
      end

      def add_log(log)
        @queue[log.first] << log
        @rcount += 1
      end

      def any_in_queue?
        any = 0
        @queue.each do |service, q|
          q.each do |m|
            next unless levels.has_key?(m[1])
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
            next unless levels.has_key?(m[1])
            if cull
              if m.last == last_m and m[0..1] == last_sv
                last_count += 1
                next
              elsif last_count > 0
                lf.write_nonblock "#{@now}|#{last_sv.join(C_bar)}|Last message repeated #{last_count} times\n"
                last_sv = last_m = nil
                last_count = 0
              end
              lf.write_nonblock "#{@now}|#{m.join(C_bar)}\n"
              last_m = m.last
              last_sv = m[0..1]
            else
              lf.write_nonblock "#{@now}|#{m.join(C_bar)}\n"
            end
            @wcount += 1
          end
          lf.write_nonblock "#{@now}|#{last_sv.join(C_bar)}|Last message repeated #{last_count} times\n" if cull and last_count > 0
        end
        @queue.each {|service,q| q.clear}
      end

      def flush_queue
        @logs.each_value do |l|
          #if !l.logfile.closed? and l.logfile.fileno > 2
          if l.logfile.fileno > 2
            l.logfile.fdatasync rescue l.logfile.fsync
          end
        end
      end

      def key
        @config[Ckey].to_s
      end

    end

    class Log
      attr_reader :service, :levels, :logfile, :cull

      def initialize(spec)
        @service = spec[Analogger::Cservice]
        @levels = spec[Analogger::Clevels]
        @logfile = spec[Analogger::Clogfile]
        @cull = spec[Analogger::Ccull]
      end

      def to_s
        "service: #{@service}\nlevels: #{@levels.inspect}\nlogfile: #{@logfile}\ncull: #{@cull}\n"
      end

      def ==(n)
        n.service == @service &&
          n.levels == @levels &&
          n.logfile == @logfile &&
          n.cull == @cull
      end

    end
  end

  class AnaloggerProtocol < EventMachine::Connection
    Ci = 'i'.freeze
    Rcolon = /:/

    LoggerClass = Analogger

    def post_init
      setup
    end

  end
end



