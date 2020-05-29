# frozen_string_literal: true

# Originally Created by James Tucker <jftucker@gmail.com> on 2008-01-07.
# Code for the Logger interface taken from Logger itself now, instead of being generated.
require 'logger'

# = LoggerInterface.rb
#
# Simple logging utility wrapper.
#
# Author:: James Tucker <jftucker@gmail.com>, NAKAMURA, Hiroshi  <nakahiro@sarion.co.jp> (logger)
# Documentation:: James Tucker, NAKAMURA, Hiroshi and Gavin Sinclair
# License::
#   You can redistribute it and/or modify it under the same terms of Ruby's
#   license; either the dual license version in 2003, or any later version.
#
# See LoggerInterface for documentation.
#

module Swiftcore
  module Analogger
    class Client
      #
      # == Description
      #
      # LoggerInterface provides a module which may be used to extend an Analogger
      # Client interface, and provide a dual-mode interface, supporting both the
      # analogger client api, and the logger api.
      #
      # === Description From logger.rb:
      # The Logger class provides a simple but sophisticated logging utility that
      # anyone can use because it's included in the Ruby 1.8.x standard library.
      #
      # The HOWTOs below give a code-based overview of Logger's usage, but the basic
      # concept is as follows.  You create a Logger object (output to a file or
      # elsewhere), and use it to log messages.  The messages will have varying
      # levels (+info+, +error+, etc), reflecting their varying importance.  The
      # levels, and their meanings, are:
      #
      # +FATAL+:: an unhandleable error that results in a program crash
      # +ERROR+:: a handleable error condition
      # +WARN+::  a warning
      # +INFO+::  generic (useful) information about system operation
      # +DEBUG+:: low-level information for developers
      #
      # So each message has a level, and the Logger itself has a level, which acts
      # as a filter, so you can control the amount of information emitted from the
      # logger without having to remove actual messages.
      #
      # For instance, in a production system, you may have your logger(s) set to
      # +INFO+ (or +WARN+ if you don't want the log files growing large with
      # repetitive information).  When you are developing it, though, you probably
      # want to know about the program's internal state, and would set them to
      # +DEBUG+.
      #
      # === Example
      #
      # A simple example demonstrates the above explanation:
      #
      #   log = Swiftcore::Analogger::Client.new('logger_interface','127.0.0.1','47990')
      #   log.extend(Swiftcore::Analogger::Client::LoggerInterface)
      #   log.level = Logger::WARN
      #
      #   log.debug("Created logger")
      #   log.info("Program started")
      #   log.warn("Nothing to do!")
      #
      #   begin
      #     File.each_line(path) do |line|
      #       unless line =~ /^(\w+) = (.*)$/
      #         log.error("Line in wrong format: #{line}")
      #       end
      #     end
      #   rescue => err
      #     log.fatal("Caught exception; exiting")
      #     log.fatal(err)
      #   end
      #
      # Because the Logger's level is set to +WARN+, only the warning, error, and
      # fatal messages are recorded.  The debug and info messages are silently
      # discarded.
      #
      # === How to log a message
      #
      # Notice the different methods (+fatal+, +error+, +info+) being used to log
      # messages of various levels.  Other methods in this family are +warn+ and
      # +debug+.  +add+ is used below to log a message of an arbitrary (perhaps
      # dynamic) level.
      #
      # 1. Message in block.
      #
      #      logger.fatal { "Argument 'foo' not given." }
      #
      # 2. Message as a string.
      #
      #      logger.error "Argument #{ @foo } mismatch."
      #
      # 3. With progname.
      #
      #      logger.info('initialize') { "Initializing..." }
      #
      # 4. With severity.
      #
      #      logger.add(Logger::FATAL) { 'Fatal error!' }
      #
      # === Setting severity threshold
      #
      # 1. Original interface.
      #
      #      logger.sev_threshold = Logger::WARN
      #
      # 2. Log4r (somewhat) compatible interface.
      #
      #      logger.level = Logger::INFO
      #
      #      DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
      #
      #
      module LoggerInterface
        include Logger::Severity
        MapUnknownTo = 'info'

        # A severity is the worded name for a log level
        # A level is the numerical value given to a severity
        SeverityToLevel = {}.freeze
        LevelToSeverity = {}.freeze

        Logger::Severity.constants.each do |const|
          # N.B. All severities mapped to lower case!
          severity = const.downcase
          level = Logger::Severity.const_get(const)
          SeverityToLevel[severity] = level
          LevelToSeverity[level] = severity
        end

        SeverityToLevel.default = SeverityToLevel[MapUnknownTo]
        LevelToSeverity.default = MapUnknownTo

        def self.extend_object(log_client)
          class <<log_client
            include ::Swiftcore::Analogger::Client::LoggerInterface
            alias_method :analog, :log

            # The interface supports string names, symbol names and levels as the first
            # argument. It therefrore covers both the standard analogger api, and the
            # logger api, and some other string based log level api.
            # N.B. This adds one main limitation - all levels are commonly downcased
            # by this interface.
            def add(severity, message = nil, progname = nil)
              level = severity

              case severity
              when Numeric
                severity = LevelToSeverity[level]
              when Symbol
                severity = severity.to_s.downcase
                level = SeverityToLevel[severity]
              when String
                severity = severity.to_s.downcase
                level = SeverityToLevel[severity]
              else
                raise ArgumentError, '#add accepts either Numeric, Symbol or String'
              end
              return true unless @level <= level

              # We map severity unknown to info by default. MapUnknownTo.replace('mylevel')
              # to change that.
              severity = MapUnknownTo if severity == 'unknown'

              progname ||= @service
              if message.nil?
                if block_given?
                  message = yield
                else
                  message = progname
                  progname = @service
                end
              end

              analog(severity, message)
              true
            end
            alias_method :log, :add
          end

          # Default log level for logger is 0, maybe a good idea to fetch from logger itself.
          log_client.level ||= 0
          log_client
        end

        # As there is no notion of a raw message for an analogger client, this sends messages
        # at the default log level (unknown, which is mapped to MapUnknownTo).
        def <<(raw)
          add(nil, raw)
        end

        def progname=(name)
          @service = name
        end

        def progname
          @service
        end

        #
        # The following code has been taken from logger.rb in the standard ruby distribution
        # Author:: NAKAMURA, Hiroshi  <nakahiro@sarion.co.jp>
        # Documentation:: NAKAMURA, Hiroshi and Gavin Sinclair
        # License::
        #   You can redistribute it and/or modify it under the same terms of Ruby's
        #   license; either the dual license version in 2003, or any later version.
        #

        # Logging severity threshold (e.g. <tt>Logger::INFO</tt>).
        attr_accessor :level

        alias sev_threshold level
        alias sev_threshold= level=

        # Returns +true+ iff the current severity level allows for the printing of
        # +DEBUG+ messages.
        def debug?
          @level <= DEBUG
        end

        # Returns +true+ iff the current severity level allows for the printing of
        # +INFO+ messages.
        def info?
          @level <= INFO
        end

        # Returns +true+ iff the current severity level allows for the printing of
        # +WARN+ messages.
        def warn?
          @level <= WARN
        end

        # Returns +true+ iff the current severity level allows for the printing of
        # +ERROR+ messages.
        def error?
          @level <= ERROR
        end

        # Returns +true+ iff the current severity level allows for the printing of
        # +FATAL+ messages.
        def fatal?
          @level <= FATAL
        end

        #
        # Log a +DEBUG+ message.
        #
        # See #info for more information.
        #
        def debug(message = nil, &block)
          add(DEBUG, message, nil, &block)
        end

        #
        # Log an +INFO+ message.
        #
        # The message can come either from the +progname+ argument or the +block+.  If
        # both are provided, then the +block+ is used as the message, and +progname+
        # is used as the program name.
        #
        # === Examples
        #
        #   logger.info("MainApp") { "Received connection from #{ip}" }
        #   # ...
        #   logger.info "Waiting for input from user"
        #   # ...
        #   logger.info { "User typed #{input}" }
        #
        # You'll probably stick to the second form above, unless you want to provide a
        # program name (which you can do with <tt>Logger#progname=</tt> as well).
        #
        # === Return
        #
        # See #add.
        #
        def info(message = nil, &block)
          add(INFO, message, nil, &block)
        end

        #
        # Log a +WARN+ message.
        #
        # See #info for more information.
        #
        def warn(message = nil, &block)
          add(WARN, message, nil, &block)
        end

        #
        # Log an +ERROR+ message.
        #
        # See #info for more information.
        #
        def error(message = nil, &block)
          add(ERROR, message, nil, &block)
        end

        #
        # Log a +FATAL+ message.
        #
        # See #info for more information.
        #
        def fatal(message = nil, &block)
          add(FATAL, message, nil, &block)
        end

        #
        # Log an +UNKNOWN+ message.  This will be printed no matter what the logger
        # level.
        #
        # See #info for more information.
        #
        def unknown(message = nil, &block)
          add(UNKNOWN, message, nil, &block)
        end
      end
    end
  end
end
