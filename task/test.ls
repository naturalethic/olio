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
  yield world.reset! unless olio.option.keep
  run-module = (path) ->*
    module = new Module
    module.paths = [ "#{process.cwd!}/lib", "#{process.cwd!}/node_modules", "#__dirname/../node_modules" ]
    source = fs.read-file-sync path, 'utf8'
    compiled = livescript.compile source, { +bare, -header, map: 'linked', filename: path }
    map-consumer = new source-map.SourceMapConsumer compiled.map.to-string!
    module._compile compiled.code
    run = (name) ->*
      info name
      return run-next! if name.0 is \$
      info color(239, '=' * process.stdout.columns)
      info color(226, path), color(227, \:), color(214, dasherize name)
      info color(238, '-' * process.stdout.columns)
      info path
      if /^test\/web/.test path
        agent = nightmare show: true, width: (olio.config.test?web?width or 1000), height: (olio.config.test?web?height or 800), web-preferences: { partition: \nopersist }
        yield module.exports[name] agent
      else
        socket = socket-io 'http://localhost:8000', force-new: true
        session = wire socket: socket, channel: \session
        storage = rivulet {}, socket, \storage
        delete state.fail
        state.timeout-seconds = 10
        observers = []
        yield module.exports[name] world, session, (path, fn) -> observers.push [ path, fn ]
        session.observe-all co.wrap (path, value) ->*
          return if state.fail
          if observers.0
            observer = observers.shift!
            if observer.0 != path
              state.fail = "Unexpected path '#path' should be '#{observer.0}'"
              return session.send \end, true
            info color(51, observer.0)
            info color(238, '-' * process.stdout.columns)
            try
              yield observer.1 value
            catch it
              if it.name is \AssertionError
                trace = stack-trace.parse it
                info "#{color(124, it.name)} #{color(88, it.message)}"
                position = map-consumer.original-position-for(line: trace.0.line-number, column: trace.0.column-number)
                try
                  info "#{color(241, position.source)}:#{color(226, position.line.to-string!)}", color(158, source.split('\n')[position.line - 1].trim!)
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
        state.timeout = set-timeout ->
          session.send \end, true
          state.fail = 'Timed out'
        , state.timeout-seconds * 1000
        socket.on \disconnect, ->
          clear-timeout state.timeout
          if state.fail
            info color(88, state.fail)
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
    run-next!
  paths = (require './test/seed.ls') |> map -> "test/#it.ls"
  if olio.task.1
    paths = paths |> filter -> //#{olio.task.1}//.test it
  yield run-module paths.shift! if paths.length
