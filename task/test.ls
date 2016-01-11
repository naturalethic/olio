Module = (require \module).Module
require! 'socket.io-client': socket-io
require! \co
require! \world
require! \rivulet
require! \stack-trace
require! \source-map
require! \nightmare
require! \wire

export test = ->*
  state = {}
  state.all-fails = []
  yield world.reset! unless olio.option.keep
  run-module = (path) ->*
    module = new Module
    module.paths = [ "#{process.cwd!}/lib", "#{process.cwd!}/node_modules", "#__dirname/../node_modules" ]
    source = fs.read-file-sync path, 'utf8'
    compiled = livescript.compile ([
      "module.exports.$var = (key, val) -> eval \"$\#key = val\""
      source
    ].join '\n'), { +bare, -header, map: 'linked', filename: path }
    map-consumer = new source-map.SourceMapConsumer compiled.map.to-string!
    module._compile compiled.code
    run = (name) ->*
      return run-next! if name.0 is \$
      info color(239, '=' * process.stdout.columns)
      info color(226, path), color(227, \:), color(214, dasherize name)
      info color(238, '-' * process.stdout.columns)
      if /^test\/web/.test path
        agent = nightmare show: true, width: (olio.config.test?web?width or 1000), height: (olio.config.test?web?height or 800), web-preferences: { partition: \nopersist }
        yield module.exports[name] agent
      else
        socket = socket-io 'http://localhost:8000', force-new: true
        session = wire socket: socket, channel: \session
        storage = rivulet {}, socket, \storage
        delete state.fail
        state.timeout-seconds = 3
        observers = []
        messages = []
        local = []
        module.exports.$var \session, (path, fn) -> observers.push path: path, fn: (fn and fn.bind local), type: \session
        module.exports.$var \invalid, (path, fn) -> observers.push path: path, fn: (fn and fn.bind local), type: \invalid
        module.exports.$var \world, world
        module.exports.$var \send, session.send
        module.exports.$var \timeout, -> state.timeout-seconds = it
        yield module.exports[name]!
        session.observe-all co.wrap (path, value) ->*
          messages.push path: path, value: value, type: \session
          yield run-next-observer!
        session.observe-all-validation co.wrap (path, value) ->*
          messages.push path: path, value: value, type: \invalid
          yield run-next-observer!
        locals = {}
        run-next-observer = ->*
          return if state.running or state.fail
          if empty observers
            return session.send \end, true
          if empty messages
            return
          message = messages.shift!
          observer = observers.shift!
          if message.path != observer.path or message.type != observer.type
            state.fail = [
              color 88 'Received '
              color 216 '['
              color 214 message.type
              color 216 ':'
              color 214 dasherize message.path
              color 216 ']'
              color 88 ' when the next observed was '
              color 216 '['
              color 214 observer.type
              color 216 ':'
              color 214 dasherize observer.path
              color 216 ']'
            ].join ''
            session.send \end, true
            return
          state.running = true
          info color(51, observer.path)
          info color(238, '-' * process.stdout.columns)
          try
            yield observer.fn message.value if observer.fn
          catch it
            if it.name is \AssertionError
              trace = stack-trace.parse it
              info "#{color(124, it.name)} #{color(88, it.message)}"
              position = map-consumer.original-position-for(line: trace.0.line-number, column: trace.0.column-number)
              try
                info "#{color(241, position.source)}:#{color(226, (position.line - 1).to-string!)}", color(158, source.split('\n')[position.line - 2].trim!)
              if is-array(it.expected) or is-object(it.expected)
                info color(220, 'Expected')
                pp it.expected
                info ''
                info color(222, 'Actual')
                pp it.actual
                info ''
              state.fail = 'Fail'
            else
              state.fail = color(88, it.to-string!)
            session.send \end, true
          state.running = false
          yield run-next-observer!
        state.timeout = set-timeout ->
          session.send \end, true
          state.fail = 'Timed out'
        , state.timeout-seconds * 1000
        socket.on \disconnect, ->
          clear-timeout state.timeout
          if state.fail
            info color(88, state.fail)
            state.all-fails.push path: path, name: (dasherize name), message: state.fail
          else
            info color(118, 'Success')
          run-next!
    names = keys module.exports
    run-next = co.wrap ->*
      delete state.fail
      if olio.task.2
        if olio.task.2 != \stop
          if (camelize olio.task.2) in names
            yield run camelize olio.task.2
            olio.task.2 = \stop
          else
            info color(88, "Subtest '#{olio.task.2}' does not exist.")
        else
          yield world.end!
      else
        if names.length
          yield run names.shift!
        else if paths.length
          yield run-module paths.shift!
        else
          yield world.end!
          if state.all-fails.length
            info ''
            info color(88, "Total failures: #{state.all-fails.length}")
            info color(52, '=' * process.stdout.columns)
            for fail in state.all-fails
              info color(124, "#{fail.path}: #{fail.name} - #{fail.message}")
            info ''
    run-next!
  paths = (require './test/seed.ls') |> map -> "test/#it.ls"
  if olio.task.1
    paths = paths |> filter -> //#{olio.task.1}//.test it
  yield run-module paths.shift! if paths.length
