require 'socket'
begin
	load_attempted ||= false
	require 'eventmachine'
	require 'benchmark'
rescue LoadError => e
	unless load_attempted
		load_attempted = true
		require 'rubygems'
		retry
	end
	raise e
end

module Swiftcore
	class Analogger
		C_colon = ':'.freeze
		C_bar = '|'.freeze
		Ccull = 'cull'.freeze
		Cdaemonize = 'daemonize'.freeze
		Cdefault = 'default'.freeze
		Cdefault_log = 'default_log'.freeze
		Cepoll = 'epoll'.freeze
		Chost = 'host'.freeze
		Cinterval = 'interval'.freeze
		Ckey = 'key'.freeze
		Ckqueue = 'kqueue'.freeze
		Clevels = 'levels'.freeze
		Clogfile = 'logfile'.freeze
		Clogs = 'logs'.freeze
		Cpidfile = 'pidfile'.freeze
		Cport = 'port'.freeze
		Croll = 'roll'.freeze
		Croll_interval = 'roll_interval'.freeze
		Croll_size = 'roll_size'.freeze
		Csecret = 'secret'.freeze
		Cservice = 'service'.freeze
		Csyncinterval = 'syncinterval'.freeze
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
				safe_trap(EXIT_SIGNALS) {cleanup;exit}
				safe_trap(RELOAD_SIGNALS) {cleanup;throw :hup}

				if @config[Cepoll] or @config[Ckqueue]
					EventMachine.epoll if @config[Cepoll]
					EventMachine.kqueue if @config[Ckqueue]

					EventMachine.set_descriptor_table_size(4096)
				end

				EventMachine.run {
					EventMachine.start_server @config[Chost], @config[Cport], protocol
					EventMachine.add_periodic_timer(1) {Analogger.update_now}
					EventMachine.add_periodic_timer(@config[Cinterval]) {write_queue}
					EventMachine.add_periodic_timer(@config[Csyncinterval]) {flush_queue}
				}
			end

			def daemonize
				if (child_pid = fork)
					puts "PID #{child_pid}" unless @config[Cpidfile]
					exit!
				end
				Process.setsid

			rescue Exception
				puts "Platform (#{RUBY_PLATFORM}) does not appear to support fork/setsid; skipping"
			end

			def new_log(facility = Cdefault, levels = @config[Clevels] || DefaultSeverityLevels, log = @config[Cdefault_log], cull = true, roll = @config[Croll], roll_interval = @config[Croll_interval], roll_size = @config[Croll_size])
				Log.new({Cservice => facility, Clevels => levels, Clogfile => log, Ccull => cull, Croll => roll, Croll_interval => roll_interval, Croll_size => roll_size})
			end

			def cleanup
				@logs.each do |service,l|
					l.logfile.fsync if !l.logfile.closed? and l.logfile.fileno > 2
					l.logfile.close unless l.logfile.closed? or l.logfile.fileno < 3
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
					roll = log[Croll] || log[Croll_interval] || log[Croll_size] ? true : false
					if Array === log[Cservice]
						log[Cservice].each do |loglog|
							@logs[loglog] = new_log(loglog,log[Clevels],logfile_destination(log[Clogfile]),log[Ccull],roll,log[Croll_interval],log[Croll_size])
						end
					else
						@logs[log[Cservice]] = new_log(log[Cservice],log[Clevels],logfile_destination(log[Clogfile]),log[Ccull],roll,log[Croll_interval],log[Croll_size])
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

			def write_queue
				@queue.each do |service,q|
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
				@logs.each_value {|l| l.logfile.fsync if l.logfile.fileno > 2}
			end

			def key
				@config[Ckey].to_s
			end

		end

	end

	class Log
		attr_reader :service, :levels, :logfile, :cull, :roll, :roll_interval, :roll_size

		def initialize(spec)
			@service = spec[Analogger::Cservice]
			@levels = spec[Analogger::Clevels]
			@logfile = spec[Analogger::Clogfile]
			@cull = spec[Analogger::Ccull]
			@roll = spec[Analogger::Croll]
			@roll_inteval = spec[Analogger::Croll_interval]
			@roll_size = spec[Analogger::Croll_size]
		end

		def to_s
			"service: #{@service}\nlevels: #{@levels.inspect}\nlogfile: #{@logfile}\ncull: #{@cull}\n"
		end
	end

	class AnaloggerProtocol < EventMachine::Connection
		Ci = 'i'.freeze
		Rcolon = /:/
		MaxMessageLength = 8192

		LoggerClass = Analogger

		def post_init
			setup
		end

	end
end

case RUBY_VERSION
when /^1.8/
	require 'swiftcore/Analogger/receive_data_18.rb'
else /^1.9/
	require 'swiftcore/Analogger/receive_data_19.rb'
end

