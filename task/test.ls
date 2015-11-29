Module = (require \module).Module
require! 'socket.io-client': socket-io
require! \co
# require! \db
require! \rivulet

export test = ->*
  state = {}
  # yield db.reset! unless olio.option.keep
  # r = db.r!
  run-module = (path) ->
    info path
    module = new Module
    module.paths = [ "#{process.cwd!}/node_modules", "#{process.cwd!}/lib" ]
    module._compile livescript.compile ([
      "export $local = {}"
      "$revise = -> $local.session it"
      "$merge = -> $local.session.merge it"
      # "r = -> $local.r"
      "$done = -> $merge { +end }"
      (fs.read-file-sync path .to-string!)
    ].join '\n'), { +bare }
    # module.exports.$local.r = r
    run = (name) ->
      return run-next! if name.0 is \$
      info '=' * process.stdout.columns
      info path, \:, (dasherize name)
      info '-' * process.stdout.columns
      socket = socket-io 'http://localhost:9000', force-new: true
      session = rivulet socket, \session
      module.exports.$local.session = session
      keys module.exports[name] |> each (key) ->
        return if key is \session
        module.exports[name][key] = co.wrap(module.exports[name][key])
        module.exports[name][key].bind module.exports[name]
        session.observe (camelize key), (it, diff) ->
          it = it!
          module.exports[name][key] it, diff
          .catch ->
            if it.name is \AssertionError
              info "#{it.name.red} (#{it.operator})"
              info 'Expected'.yellow
              pp it.expected
              info 'Actual'.yellow
              pp it.actual
            else
              info it.to-string!red
            session.set \end, true
      session module.exports[name].session
      state.timeout = set-timeout ->
        session.set \end, true
        state.fail = 'Timed out'
      , 3000
      session.socket.on \disconnect, ->
        clear-timeout state.timeout
        if state.fail
          info state.fail.red
        else
          info 'Success'.green
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
        # else
        #   r._r.get-pool-master!drain!
    run-next!
  paths = glob.sync 'test/*'
  if 'test/seed.ls' in paths
    paths = (require './test/seed.ls') |> map -> "test/#it.ls"
  if olio.task.1
    paths = paths |> filter -> //#{olio.task.1}\.ls$//.test it
  run-module paths.shift! if paths.length
