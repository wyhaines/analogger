# Analogger

## Overview

Analogger is a fast asynchronous logging service and client library. It is
implemented in Ruby, and currently uses [async] in the server, a pure Ruby
event reactor.

Analogger was originally written over a decade ago, in response to a need to
maintain a central logging server to accumulate logs from numerous web
applications to a single location. It takes very little time to send a logging
message, making it a very low impact logger for performance sensitive
applications. It has been continuously used in production since then, albeit
in a version not released publicly.

## Usage

Analogger is configured through a YAML formatted file:

```yaml
host: mycompany-logger-1-nyc1.private
port: 6766
default_log: /var/log/analogger_default
daemonize: true
syncinterval: 5
logs:
- service:
  - default
  logfile: /var/log/analogger/default
  cull: true
- service:
  - project-development
  logfile: /var/log/analogger/project-development.log
- service:
  - project-production
  logfile: /var/log/analogger/project-production.log
  cull: true
```

### Configuration Variables

* port

  The port to listen for connections on. 6766 is the default.

* host

  The hostname or IP to bind to when listening for connections.

* default_log: /var/log/analogger_default

  This is the file to send logs to which don't appear to match any named service in the configuration.

* daemonize

  Whether or not to detach an analogger process as a daemon process. You normally want this to be true.

* syncinterval

  Analogger will run a thread every X seconds to ensure that any currently buffered log contents are synchronized to disk. Analogger tries to write any buffered logs before it exits if it receives a signal which would cause the process to die. However, in the event that this is not possible, only the logs received since the last sync interval would be at risk.

* logs

  This is a list of defined logging services. Each consists of a service label, a logging destination (the path to the log file for that service), and optionally a `cull` attribute which, if true, causes analogger to deduplicate logs, eliminating consecutive repeats of the same message and instead emitting a summary of how many records like the one above the summary were culled.

[async]: https://github.com/socketry/async/
