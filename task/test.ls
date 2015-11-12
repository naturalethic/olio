require! 'socket.io-client': socket-io
require! co
require! baobab
require! 'fast-json-patch/dist/json-patch-duplex.min': patch

export test = ->*
  for path in glob.sync 'test/**/*'
    module = require fs.realpath-sync path
    run = (name) ->
      info '=' * 40
      info name
      info '-' * 40
      session = new baobab
      socket = socket-io 'http://localhost:8000'
      receive-count = 0
      receive-last = []
      socket.on \session, ->
        new-session = session.serialize!
        patch.apply new-session, it
        receive-last := it |> map -> JSON.stringify it
        info \NEW-SESSION, new-session
        session.deep-merge new-session
        receive-count := receive-count + 1
        info \SESSION, receive-count, session.get!
      session.root.start-recording 1
      session.on \update, ->
        # Don't send session changes that were just received from server
        diff = patch.compare session.root.get-history!0, session.root.get!
        |> filter -> JSON.stringify(it) not in receive-last
        receive-last := []
        if diff.length
          info \EMIT, diff
          socket.emit \session, diff if diff.length
      keys module[name] |> each (key) ->
        return if key is \session
        cursor = session.select key.split('.')
        cursor.on \update, ->
          return if it.data.current-data is undefined
          return if it.data.previous-data and !patch.compare(it.data.current-data, it.data.previous-data).length
          sdata = session.root.serialize!
          cdata = cursor.serialize!
          if is-array (result = module[name][key] sdata, cdata)
            [ sdata, cdata ] = result
            if sdata
              session.root.deep-merge sdata
            if cdata
              cursor.deep-merge cdata
            session.trim!
      session.deep-merge(module[name].session or {})
    names = keys module
    run names.pop! if names.length
