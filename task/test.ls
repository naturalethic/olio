Module = (require \module).Module
require! 'socket.io-client': socket-io
require! \co
require! \world
require! \rivulet

export test = ->*
  state = {}
  yield world.reset! unless olio.option.keep
  run-module = (path) ->
    module = new Module
    module.paths = [ "#{process.cwd!}/lib", "#{process.cwd!}/node_modules" ]
    module._compile livescript.compile ([
      (fs.read-file-sync path .to-string!)
    ].join '\n'), { +bare }
    run = (name) ->
      return run-next! if name.0 is \$
      info '=' * process.stdout.columns
      info path.yellow, \:, (dasherize name).cyan
      info '-' * process.stdout.columns
      socket = socket-io 'http://localhost:8000', force-new: true
      session = rivulet {}, socket, \session
      keys module.exports[name] |> each (key) ->
        return if key is \session
        reactor = module.exports[name][key]
        reactor.bind module.exports[name]
        observe-func = co.wrap ->*
          info key
          info '-' * process.stdout.columns
          session.$forget key, observe-func
          tx = yield world.transaction!
          try
            yield reactor tx, session, it
            yield tx.commit!
          catch it
            yield tx.rollback!
            if it.name is \AssertionError
              info "#{it.name.red} (#{it.operator})"
              info 'Expected'.yellow
              pp it.expected
              info ''
              info 'Actual'.yellow
              pp it.actual
              info ''
              state.fail = 'Fail'
            else
              state.fail = it.to-string!red
            session.end = true
        session.$observe key, observe-func
      session <<< module.exports[name].session
      state.timeout = set-timeout ->
        session.end = true
        state.fail = 'Timed out'
      , 3000
      session.$socket.on \disconnect, ->
        clear-timeout state.timeout
        if state.fail
          info state.fail.red
        else
          info 'Success'.green
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
            info "Subtest '#{olio.task.2}' does not exist.".red
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
