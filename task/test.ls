Module = (require \module).Module
require! 'socket.io-client': socket-io
require! \co
require! \world
require! \rivulet
require! \stack-trace
require! \source-map

export test = ->*
  state = {}
  yield world.reset! unless olio.option.keep
  run-module = (path) ->
    module = new Module
    module.paths = [ "#{process.cwd!}/lib", "#{process.cwd!}/node_modules", "#__dirname/../node_modules" ]
    source = fs.read-file-sync path, 'utf8'
    compiled = livescript.compile source, { +bare, -header, map: 'linked', filename: path }
    map-consumer = new source-map.SourceMapConsumer compiled.map.to-string!
    module._compile compiled.code
    run = (name) ->
      return run-next! if name.0 is \$
      info color(239, '=' * process.stdout.columns)
      info color(226, path), color(227, \:), color(214, dasherize name)
      info color(238, '-' * process.stdout.columns)
      socket = socket-io 'http://localhost:8000', force-new: true
      session = rivulet {}, socket, \session
      storage = rivulet {}, socket, \storage
      keys module.exports[name] |> each (key) ->
        return if key in <[ session timeout ]>
        reactors = module.exports[name][key]
        reactors = [ reactors ] if !is-array reactors
        for reactor in reactors
          reactor.bind module.exports[name]
        observe-func = co.wrap ->*
          info color(51, key)
          info color(238, '-' * process.stdout.columns)
          reactor = reactors.shift!
          if empty reactors
            session.$forget key, observe-func
          tx = yield world.transaction!
          tx.storage = storage
          try
            yield reactor tx, session, it
            yield tx.commit!
          catch it
            yield tx.rollback!
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
            session.end = true
        session.$observe key, observe-func
      state.timeout-seconds = module.exports[name]?timeout or 10
      session <<< module.exports[name].session
      state.timeout = set-timeout ->
        session.end = true
        state.fail = 'Timed out'
      , state.timeout-seconds * 1000
      session.$socket.on \disconnect, ->
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
            run camelize olio.task.2
            olio.task.2 = \stop
          else
            info color(88, "Subtest '#{olio.task.2}' does not exist.")
        else
          yield world.end!
      else
        if names.length
          run names.shift!
        else if paths.length
          run-module paths.shift!
        else
          yield world.end!
    run-next!
  paths = glob.sync 'test/*'
  if 'test/seed.ls' in paths
    paths = (require './test/seed.ls') |> map -> "test/#it.ls"
  if olio.task.1
    paths = paths |> filter -> //#{olio.task.1}\.ls$//.test it
  run-module paths.shift! if paths.length
