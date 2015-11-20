require! 'socket.io-client': socket-io
require! co
require! 'fast-json-patch': patch
require! \prettyjson
Module = (require \module).Module

require! \db
require! \rivulet

prettyprint = ->
  info prettyjson.render it,
    keys-color: \grey
    dash-color: \white
    number-color: \blue

export test = ->*
  state = {}
  yield db.reset!
  run-module = (path) ->
    module = new Module
    module.paths = [ "#{process.cwd!}/node_modules", "#{process.cwd!}/lib" ]
    module._compile livescript.compile ([
      "export $local = {}"
      "$revise = -> $local.session it"
      (fs.read-file-sync path .to-string!)
    ].join '\n'), { +bare }
    run = (name) ->
      return run-next! if name.0 is \$
      info '=' * process.stdout.columns
      info path, \:, (dasherize name)
      info '-' * process.stdout.columns
      session = rivulet!
      socket = socket-io 'http://localhost:8000', force-new: true
      module.exports.$local.session = session
      receive-count = 0
      receive-last = []
      socket.on \session, ->
        reset-too-long!
        root-stream.pause = true
        session.patch it
        root-stream.pause = false
      root-stream = session.observe-deep ''
      root-stream.pause = false
      root-stream.on-value ->
        return if root-stream.pause
        socket.emit \session, session.last
      keys module.exports[name] |> each (key) ->
        return if key is \session
        module.exports[name][key] = co.wrap(module.exports[name][key])
        module.exports[name][key].bind module.exports[name]
        session.observe (dasherize key).replace(/-/, '.')
        .on-value ->
          set-timeout ->
            module.exports[name][key] session!
            .then ->
              info 'Success'.green
            .catch ->
              if it.name is \AssertionError
                info "#{it.name.red} (#{it.operator})"
                info 'Expected'.yellow
                prettyprint it.expected
                info 'Actual'.yellow
                prettyprint it.actual
              else
                info it.to-string!red
              session.set \end, true
      session module.exports[name].session
      reset-too-long = ->
        clear-timeout state.too-long
        return if session.get \end
        state.too-long = set-timeout ->
          session.set \end, true
          state.fail = 'took too long'
        , 1000
      socket.on \disconnect, ->
        clear-timeout state.too-long
        if state.fail
          info "Failed: #{state.fail}".red
        run-next!
    names = keys module.exports
    run-next = ->
      if olio.task.2
        if olio.task.2 != \stop
          if (camelize olio.task.2) in names
            run camelize olio.task.2
            olio.task.2 = \stop
          else
            info "Subtest '#{olio.task.2}' does not exist.".red
      else
        if names.length
          run names.shift!
        else if paths.length
          run-module paths.shift!
    run-next!
  paths = glob.sync 'test/*'
  if olio.task.1
    paths = paths |> filter -> //#{olio.task.1}\.ls$//.test it
  run-module paths.shift! if paths.length
