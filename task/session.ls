require! \node-static
require! \http
require! 'socket.io': socket-io
require! 'fast-json-patch': patch
require! \baobab
require! \co
require! \prettyjson
require! \rethinkdbdash
Module = (require \module).Module

export watch = [ __filename, \olio.ls, \session.ls, \react ]

export session = ->*
  try
    r = rethinkdbdash olio.config.db{host}
    if olio.config.db.name not in (yield r.db-list!)
      info "Creating database '#{olio.config.db.name}'"
      yield r.db-create olio.config.db.name
    r = r.db olio.config.db.name
    for table in  difference (olio.config.db.tables ++ <[ session ]>), (yield r.table-list!)
      info "Creating table '#table'"
      yield r.table-create table
  file = new node-static.Server './public'
  server = http.create-server (request, response) ->
    if not fs.exists-sync "./public#{request.url}"
      request.url = '/'
    request.add-listener \end, ->
      file.serve request, response
    .resume!
  port = olio.option.port or olio.config.web?port or 8000
  schema = require "#{process.cwd!}/session"
  server.listen port, '0.0.0.0'
  server = socket-io server
  server.on \connection, (socket) ->
    $info = (...args) ->
      date = (new Date).toISOString!split \T
      if is-string(args.0)
        args.0 = args.0.magenta
      args.unshift "#{date.0.blue}#{'T'.grey}#{date.1.blue} #{socket.handshake.address.yellow} #{'INFO'.green}"
      obj = ''
      if is-object(last args) or is-array(last args)
        obj = args.pop!
      info ...args
      info prettyjson.render obj,
        keys-color: \grey
        dash-color: \white
        number-color: \blue
      # info obj if obj
    $info 'Connection established'
    session = new baobab
    socket.emit \session, (patch.compare {}, session.get!)
    receive-last = []
    socket.on \session, ->
      $info 'Data received', it
      receive-last := it |> map -> JSON.stringify it
      new-session = session.serialize!
      try
        patch.apply new-session, it
        session.deep-merge new-session
    glob.sync 'react/**/*' |> each ->
      module = new Module
      module.paths = [ "#{process.cwd!}/node_modules", "#{process.cwd!}/lib" ]
      module._compile livescript.compile ([
        "export $local = {}"
        "$merge = -> $local.session.deep-merge it"
        "$unset = -> $local.session.unset it.split('.')"
        "r = -> $local.r"
        "$uuid = ->* yield r!_r.uuid!"
        "$info = -> $local.info ...&"
        "$shy = (obj, props) -> (props |> filter -> obj[camelize it]).length < props.length"
        (fs.read-file-sync it .to-string!)
      ].join '\n'), { +bare }
      module.exports.$local.session = session
      module.exports.$local.r = r
      module.exports.$local.info = $info
      keys module.exports |> each (key) ->
        return if key.0 is \$
        module.exports[key] = co.wrap(module.exports[key])
        module.exports[key].bind module.exports
        cursor = session.select (dasherize key).split \-
        cursor.on \update, ->
          return if it.data.current-data is undefined
          return if it.data.previous-data and !patch.compare(it.data.current-data, it.data.previous-data).length
          $info "Reaction: #key", session.serialize!
          module.exports[key] session.serialize!
    session.select \id
    .on \update, (event) ->
      (co.wrap ->*
        id = session.get \id
        return if id is undefined
        return if event.data.previous-data == event.data.current-data
        $info 'Session id changed', event.data.previous-data, event.data.current-data
        if id is \destroy
          info 'Session destroyed'
          session.set route: session.get(\route)
        else
          record = first (yield r.table(\session).filter(id: session.get(\id)))
          if record
            $info 'Loading session', record
            session.set record
          else if session.get \persistent
            $info 'Creating session', session.serialize!
            yield r.table(\session).insert session.serialize!
          else
            session.unset \id
      )!
    session.root.start-recording 1
    session.on \update, ->
      # Don't send session changes that were just received from client
      diff = patch.compare session.root.get-history!0, session.root.get!
      if diff.length and (id = session.get \id) and session.get \persistent
        $info 'Updating session', session.serialize!
        r.table(\session).get(id).update(session.serialize!).run!
      diff = diff |> filter -> JSON.stringify(it) not in receive-last
      receive-last := []
      if diff.length
        $info 'Sending data', diff
        socket.emit \session, diff if diff.length
      if session.get \end
        $info 'Disconnecting'
        socket.disconnect!
