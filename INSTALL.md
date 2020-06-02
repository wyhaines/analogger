# Swiftcore Analogger

Analogger is a fast, simple log aggregator service. The current architecture features a central server that receives
logging messages from N clients, and aggregates them into one or more destinations, depending on their origin. Clients
maintain persistent connections with the server, feeding it a stream of log messages using a simple protocol. The
server is written in Ruby, and is capable of handling arbitrarily high connection counts feeding it tens of thousands
of messages per second from a single process.

The Ruby client library that is part of this package has support for locally buffering logging messages in the event
that the Analogger server is unreachable. It can write those logs to a local file, and will then stream those logs back
to the server when the server becomes available again, being careful to maintain the time ordering of the logs, and
streaming them in time boxed chunks to avoid overwhelming either the client process/system or the server with the
deluge of old logs.

Libraries written in other languages may or may not do this. Refer to their documentation for details.

## Installation

To install analogger:

gem install analogger

It should run on Ruby 2.3 and up, as well as JRuby and TruffleRuby. If you need to run it on an earlier version of Ruby,
take a look at version 1.1.0. That version uses EventMachine, and should be compatible with any MRI Ruby back to 1.8.6.

## Quickstart

To start an Analogger instance, first create a configuration file:

```yaml
port: 6766
host: 127.0.0.1
default_log: /var/log/weblogs/default
daemonize: true
syncinterval: 60
logs:
- service: bigapp
  logfile:  /var/log/bigapp
  cull: true
- service:
  - smallapp1
  - smallapp2
  logfile: /var/log/smallapps
  cull: true
- service: newsletter_sender
  logfile: /var/log/newsletter.log
  cull: false
```

Then start the analogger:

`analogger -c config_file`

To use the client library to connect to an Analogger instance and send
logging messages to it:

```ruby
require 'swiftcore/Analogger/Client'
logger = Swiftcore::Analogger::Client.new('smallapp1','127.0.0.1','6766')
logger.log('info','This is a log message.')
```
## TODO

- 

Homepage::  http://analogger.swiftcore.org
Copyright:: (C) 2007-2020 by Kirk Haines. All Rights Reserved.
Email:: wyhaines@gmail.com