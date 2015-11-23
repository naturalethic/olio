Module = (require \module).Module
require! \node-static
require! \http
require! 'socket.io': socket-io
require! \co
require! \rethinkdbdash
require! \rivulet

export watch = [ __filename, \olio.ls, \session.ls, \react, "#__dirname/../lib/rivulet.ls" ]

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
      if is-object(last args) or is-array(last args)
        obj = args.pop!
      info ...args
      pp obj if obj
    $info 'Connection established'
    session = rivulet socket, \session
    session.observe \end, ->
      $info 'Disconnecting'
      session.socket.disconnect!
    glob.sync 'react/**/*' |> each ->
      module = new Module
      module.paths = [ "#{process.cwd!}/node_modules", "#{process.cwd!}/lib" ]
      module._compile livescript.compile ([
        "export $local = {}"
        "$revise = -> $local.session it"
        "$merge = -> $local.session.merge it"
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
        session.observe ((dasherize key).replace /-/, '.'), ->
          $info "Reaction: #key", it
          module.exports[key] it
    # XXX: Now we can change the semantics of this to just delete the id on the client instead
    #      of setting to destroy
    session.observe \id, co.wrap ->*
      id = session.get \id
      # return if id is undefined
      if id is \destroy
        info 'Session destroyed'
        session.set route: session.get(\route)
      else
        record = first (yield r.table(\session).filter(id: id))
        if record
          $info 'Loading session', record
          session record
        else if session.get \persistent
          $info 'Creating session', it
          yield r.table(\session).insert it
        else
          $info 'Deleting session id'
          session.del \id
