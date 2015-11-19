require! 'socket.io-client': socket-io
require! co
require! baobab
require! 'fast-json-patch': patch
Module = (require \module).Module

require! \db

baobab::trim = (other, tree, path = []) ->
  tree ?= @serialize!
  for key, val of tree
    if not other[key]?
      @unset path ++ [ key ]
    else if is-object val
      @trim other[key], val, path ++ [ key ]

export test = ->*
  yield db.reset!
  run-module = (path) ->
    module = new Module
    module.paths = [ "#{process.cwd!}/node_modules", "#{process.cwd!}/lib" ]
    module._compile livescript.compile ([
      "export $local = {}"
      "$merge = -> $local.session.deep-merge it"
      "$unset = -> $local.session.unset it.split('.')"
      (fs.read-file-sync path .to-string!)
    ].join '\n'), { +bare }
    run = (name) ->
      return if name.0 is \$
      info '=' * 40
      info path, \:, (dasherize name)
      info '-' * 40
      session = new baobab
      socket = socket-io 'http://localhost:8000', force-new: true
      module.exports.$local.session = session
      receive-count = 0
      receive-last = []
      socket.on \session, ->
        reset-too-long!
        new-session = session.serialize!
        patch.apply new-session, it
        receive-last := it |> map -> JSON.stringify it
        session.deep-merge new-session
        session.trim new-session
        receive-count := receive-count + 1
      session.root.start-recording 1
      session.on \update, ->
        reset-too-long!
        # Don't send session changes that were just received from server
        diff = patch.compare session.root.get-history!0, session.root.get!
        |> filter -> JSON.stringify(it) not in receive-last
        receive-last := []
        if diff.length
          # info \EMIT, diff
          socket.emit \session, diff if diff.length
      keys module.exports[name] |> each (key) ->
        return if key is \session
        module.exports[name][key] = co.wrap(module.exports[name][key])
        module.exports[name][key].bind module.exports[name]
        cursor = session.select key.split('.')
        cursor.on \update, ->
          reset-too-long!
          return if it.data.current-data is undefined
          return if it.data.previous-data and !patch.compare(it.data.current-data, it.data.previous-data).length
          module.exports[name][key] session.serialize!
      session.deep-merge(module.exports[name].session or {})
      fail = null
      too-long = null
      reset-too-long = ->
        clear-timeout too-long
        too-long := set-timeout ->
          session.deep-merge end: true
          fail := 'took too long'
        , 1000
      socket.on \disconnect, ->
        clear-timeout too-long
        if fail
          info "Failed: #fail".red
        if names.length
          run names.pop!
        else if paths.length
          run-module paths.pop!
    names = keys module.exports
    if names.length
      run names.pop!
    else if paths.length
      run-module paths.pop!
  paths = glob.sync 'test/**/*'
  if olio.task.1
    paths = paths |> filter -> //#{olio.task.1}\.ls$//.test it
  run-module paths.pop! if paths.length
