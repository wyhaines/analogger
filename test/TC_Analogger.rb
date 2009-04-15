require 'test/unit'
require 'rbconfig'
require 'logger'
require 'external/test_support'
SwiftcoreTestSupport.set_src_dir
require 'swiftcore/Analogger/Client'

class TC_Analogger < Test::Unit::TestCase

	@@testdir = SwiftcoreTestSupport.test_dir(__FILE__)

	def setup
		assert_nothing_raised("setup failed") do
			Dir.chdir(@@testdir)
			SwiftcoreTestSupport.announce(:analogger,"Analogger Tests")
	
			@rubybin = File.join(::Config::CONFIG['bindir'],::Config::CONFIG['ruby_install_name'])
			@rubybin << ::Config::CONFIG['EXEEXT']

			@rubybin19 = '/usr/local/ruby19/bin/ruby'
			@rubybin18 = '/usr/local/ruby185/bin/ruby'
		end
	end

	def test_analogger
		@analogger_pid = SwiftcoreTestSupport::create_process(:dir => '.',:cmd => ["#{@rubybin} ../bin/analogger -c analogger.cnf"])
		sleep 1
		logger = nil
		
		pid = File.read('log/analogger.pid').chomp

		assert_equal(@analogger_pid.to_s,pid)

		puts "Delivering test messages."

		levels = ['debug','info','warn']

		assert_nothing_raised { logger = Swiftcore::Analogger::Client.new('idontmatch','127.0.0.1','47990') }

		levels.each do |level|
			assert_nothing_raised { logger.log(level,'abc123') }
		end

		levels = ['a','b','c']

		assert_nothing_raised { logger = Swiftcore::Analogger::Client.new('a','127.0.0.1','47990') }

		levels.each do |level|
			assert_nothing_raised { logger.log(level,'abc123') }
		end

		assert_nothing_raised { logger = Swiftcore::Analogger::Client.new('b','127.0.0.1','47990') }

		levels.each do |level|
			assert_nothing_raised { logger.log(level,'abc123') }
		end

		levels = ['info','warn','fatal']

		assert_nothing_raised { logger = Swiftcore::Analogger::Client.new('c','127.0.0.1','47990') }

		levels.each do |level|
			assert_nothing_raised { logger.log(level,'abc123') }
		end

		levels = ['info','junk']

		assert_nothing_raised { logger = Swiftcore::Analogger::Client.new('d','127.0.0.1','47990') }

		levels.each do |level|
			assert_nothing_raised { logger.log(level,'abc123') }
		end

		assert_nothing_raised { logger = Swiftcore::Analogger::Client.new('stderr','127.0.0.1','47990') }

		5.times {|x| assert_nothing_raised { logger.log('info',"Logging to STDERR ##{x}") }}

		puts "Waiting for log sync.\n\n"
		sleep 2

		puts "\nChecking results.\n\n"
		logfile = ''
		assert_nothing_raised { logfile = File.read('log/default.log') }
		assert(logfile =~ /idontmatch|debug|abc123/,"Default log doesn't appear to have the expected message: idontmatch|debug|abc123")
		assert(logfile =~ /idontmatch|debug|Last message repeated 2 times/,"Default log doesn't appear to have the expected message: idontmatch|debug|Last message repeated 2 times")

		logfile = ''
		assert_nothing_raised { logfile = File.read('log/a.log') }
		assert(logfile =~ /a|a|abc123/,"Log doesn't appear to have the expected message: a|a|abc123")
		assert(logfile =~ /a|b|abc123/,"Log doesn't appear to have the expected message: a|b|abc123")
		assert(logfile =~ /a|c|abc123/,"Log doesn't appear to have the expected message: a|c|abc123")
		assert(logfile =~ /b|a|abc123/,"Log doesn't appear to have the expected message: b|a|abc123")
		assert(logfile =~ /b|b|abc123/,"Log doesn't appear to have the expected message: b|b|abc123")
		assert(logfile =~ /b|c|abc123/,"Log doesn't appear to have the expected message: b|c|abc123")

		logfile = ''
		assert_nothing_raised { logfile = File.read('log/c.log') }
		assert(logfile =~ /c|info|abc123/,"Log doesn't appear to have the expected message: c|info|abc123")
		assert(logfile =~ /c|warn|abc123/,"Log doesn't appear to have the expected message: c|warn|abc123")
		assert(logfile =~ /c|fatal|abc123/,"Log doesn't appear to have the expected message: c|fatal|abc123")

		logfile = ''
		assert_nothing_raised { logfile = File.read('log/d.log') }
		assert(logfile =~ /d|info|abc123/,"Log doesn't appear to have the expected message: d|info|abc123")
		assert(logfile !~ /junk/,"Log file has a message in it that should have been dropped.")
		teardown

		require 'benchmark'

		speedtest('short messages','0123456789')
		speedtest('larger messages','0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789')
		logger_speedtest('short messages','0123456789')
		logger_speedtest('larger messages','0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789')
	end

	def speedtest(label,message)
		puts "Analogger Speedtest -- #{label}"
		@analogger_pid = SwiftcoreTestSupport::create_process(:dir => '.',:cmd => ["#{@rubybin} ../bin/analogger -c analogger2.cnf"])
		#@analogger_pid = SwiftcoreTestSupport::create_process(:dir => '.',:cmd => ["#{@rubybin18} ../bin/analogger -c analogger2.cnf"])
		logger = nil
		assert_nothing_raised { logger = Swiftcore::Analogger::Client.new('speed','127.0.0.1','47990') }
		lvl = 'info'
		puts "Testing 50000 messages of #{message.length} bytes each."
		start = total = nil
#		Benchmark.bm do |bm|
#			bm.report { start = Time.now; 100000.times { logger.log(lvl,message) }; total = Time.now - start}
#		end
		start = Time.now; 50000.times { logger.log(lvl,message) }; total = Time.now - start
	  total = Time.now - start
		rate = 50000 / total
		puts "\nMessage rate: #{rate}/second (#{total})\n\n"
		teardown
	end

	def logger_speedtest(label,message)
		puts "Ruby Logger Speedtest -- #{label}"
		puts "Testing 100000 messages of #{message.length} bytes each."
		logger = Logger.new('log/ra')
		start = total = nil
		Benchmark.bm do |bm|
			bm.report { start = Time.now; 100000.times { logger.info(message) }; total = Time.now - start}
		end
		rate = 100000 / total
		puts "\nMessage rate: #{rate}/second (#{total})\n\n"
		logger.close
		File.delete('log/ra')
	end

	def teardown
		Process.kill "SIGTERM",@analogger_pid
		Process.wait @analogger_pid
		Dir['log/*'].each {|fn| File.delete(fn)}
	rescue
	end

end
