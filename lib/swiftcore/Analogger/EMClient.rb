begin
	load_attempted ||= false
	require 'eventmachine'
rescue LoadError => e
	unless load_attempted
		load_attempted = true
		require 'rubygems'
		retry
	end
	raise e
end

module Swiftcore
	module Analogger
		class ClientProtocol < EventMachine::Connection
			Cauthentication = 'authentication'.freeze
			Ci = 'i'.freeze
			attr_accessor :key, :host, :port, :msg_queue, :connected, :sender

			def self.connect(service = 'default', host = '127.0.0.1', port = 6766, key = nil)
				connection = ::EventMachine.connect(host, port.to_i, self) do |conn|
					conn.connected = false
					conn.msg_queue ||= ''
					conn.service = service
					conn.host = host
					conn.port = port
					conn.key = key
				end
			end

			def connection_completed
				@connected = true
				pos = 0
				log(Cauthentication,"#{@key}",true)
#				send_data @msg_queue
				@sender = EM::Timer.new(1) {send_data @msg_queue if @connected; @msg_queue = ''}
#				while @msg_queue.length > pos
#					msg = @msg_queue[pos]
#					pos += 1
#					break unless log(*msg)
#				end
#				if pos > 0
#					@msg_queue.slice!(0..(pos - 1))
#				end
			end

			def service
				@service
			end

			def service=(val)
				@service = val
				@service_length = val.length
			end

			def close
				close_connection_after_writing
			end

			def closed?
				@connected
			end

			def unbind
				@connected = false
				@sender.cancel
				::EventMachine.add_timer(rand(2)) {self.class.connect(@service, @host, @port, @key)}
			end

			def log(severity,msg,immediate=false)
				len = [@service_length + severity.length + msg.length + 3].pack(Ci)
				fullmsg = "#{len}#{len}:#{@service}:#{severity}:#{msg}"
				if immediate && @connected
					send_data fullmsg
				else
					@msg_queue << fullmsg
				end
				#if @connected
					#send_data "#{len}#{len}:#{@service}:#{severity}:#{msg}"
				#else
				#	@msg_queue << fullmsg
				#	false
				#end
			rescue Exception => e
				puts e
				@msg_queue << fullmsg if msg and severity
				false
			end

		end

		class Client
			def self.new(*args)
				ClientProtocol.connect(*args)
			end
		end
	end
end
