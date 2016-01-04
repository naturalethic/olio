Module = (require \module).Module
require! \node-static
require! \http
require! 'socket.io': socket-io
require! 'socket.io-client': socket-io-client
require! \co
require! \rivulet
require! \world
require! \gcloud
require! \ajv
require! \object-walk
require! \wire

export watch = [ __filename, \olio.ls, \schema, \react, "#__dirname/../lib" ]

$info = (...args) ->
  date = (new Date).toISOString!split \T
  if is-string(args.0)
    args.0 = color(198, args.0)
  args.unshift "#{color(81, date.0)}#{color(239, 'T')}#{color(81, date.1)} #{color(226, '0.0.0.0')} #{color(22, 'INFO')}"
  if is-object(last args) or is-array(last args)
    obj = args.pop!
  info ...args
  pp obj if obj

export session = ->*
  # --- Validation ---
  read-schema = (schema) ->
    s = require "./schema/session/#schema"
    object-walk s, (v, k, o) ->
      if k is \required
        o[k] = (v |> map -> camelize it)
      if k is \type and v is \object
        o.additional-properties = false
    s
  validator = ajv all-errors: true, v5: true
  schemas = (glob.sync 'schema/session/**/*.ls') |> map -> /^schema\/session\/(.*)\.ls$/.exec(it).1
  for schema in schemas
    $info 'Adding validation', color(207, (schema.replace /\//g, '.'))
    try
      validator.add-schema (read-schema schema), (schema.replace /\//g, '.')
    catch e
      $info 'Error reading schema', schema
      throw e
  # --- Shell
  port = olio.config.session?shell?port or 8001
  $info 'Starting session shell server on port', color(78, port)
  shell = socket-io port
  shell.on \connection, (socket) ->
    command-tree =
      collect:
        session:
          paths: ->
            shell.session-paths = []
            socket.emit \shell, 'Ok.'
      help: ->
        socket.emit \shell, command-help!
      list:
        session:
          paths: ->
            socket.emit \shell, map((-> dasherize it), shell.session-paths).join('\n')
    command-help = ->
      ((world.path-values-from-object command-tree) |> map -> it.path.replace(/\./g, ' ')).join '\n'
    socket.on \shell, ->
      if path = (it.split(' ') |> map -> it.trim!).join '.'
        if command = $get command-tree, path
          command!
        else
          socket.emit \shell, 'Unknown command.'
      else
        socket.emit \shell, ''
    socket.emit \completion, command-help!
  # --- Static
  if olio.config.session.static
    $info 'Serving static files'
    file = new node-static.Server './public'
    server = http.create-server (request, response) ->
      if not fs.exists-sync "./public#{request.url}"
        $info "Unknown url '#{request.url}', sending index"
        request.url = '/'
      request.add-listener \end, ->
        file.serve request, response
      .resume!
  else
    server = http.create-server (request, response) ->
      request.add-listener \end, ->
        response.end 'Session'
      .resume!
  port = olio.option.port or olio.config.session?port or 8000
  $info 'Starting session server on port', color(78, port)
  server.listen port, '0.0.0.0'
  server = socket-io server
  # --- Session
  server.on \connection, (socket) ->
    $info = (...args) ->
      date = (new Date).toISOString!split \T
      if is-string(args.0)
        args.0 = color(198, args.0)
      args.unshift "#{color(81, date.0)}#{color(239, 'T')}#{color(81, date.1)} #{color(226, socket.handshake.address)} #{color(22, 'INFO')}"
      if is-object(last args) or is-array(last args)
        obj = args.pop!
      info ...args
      pp obj if obj
    $info 'Connection established'
    # session = rivulet {}, socket, \session, validator
    session-wire = wire socket: socket, channel: \session, validator: validator, logger: $info
    session-wire.session-id = null
    # session = {}
    storage = rivulet {}, socket, \storage
    # session.$logger = $info
    session-wire.observe 'end', ->
      $info 'Disconnecting'
      socket.disconnect!
    glob.sync 'react/**/*.ls' |> each (path) ->
      module = new Module
      module.paths = [ "#{process.cwd!}/lib", "#{process.cwd!}/node_modules" ]
      module._compile livescript.compile ([
        # "export $local = {}"
        # "$info = -> $local.info ...&"
        (fs.read-file-sync path .to-string!)
      ].join '\n'), { +bare }
      # module.exports.$local.info = $info
      # reaction-state =
      #   $send: -> session.send ...&
      return if not module.exports.session
      keys module.exports.session |> each (key) ->
        # reactor = module.exports.session[key]
        # reactor.bind module.exports
        $info 'Observing', color(206, key)
        session-wire.observe key, co.wrap ->*
          $info "Session reaction '#key'", it
          module = new Module
          module.paths = [ "#{process.cwd!}/lib", "#{process.cwd!}/node_modules" ]
          module._compile livescript.compile ([
            "module.exports.$var = (key, val) -> eval \"$\#key = val\""
            # "$info = -> $local.info ...&"
            (fs.read-file-sync path .to-string!)
          ].join '\n'), { +bare }
          # module.exports.$local.info = $info
          # module.exports.$send = -> session.send ...&
          validation = {}
          # for path in (session.$validation-paths |> filter -> //^#{key}//.test it)
          #   $set validation, path, ($get session.validation, path)
          sends = []
          tx = yield world.transaction!
          tx.$info = $info
          module.exports.$var \info, $info
          module.exports.$var \world, tx
          module.exports.$var \send, (path, value) -> sends.push [ path, value ]
          module.exports.$var \invalidate, session-wire.invalidate
          # info module.exports.session[key].to-string!
          # state =
          #   # $call: eval(module.exports.session[key].to-string!)
          #   $world: tx
          #   $send: -> session.send ...&
          # info reactor.$call
          try
            if session-wire.session-id
              session = yield tx.get session-wire.session-id
            else
              session = yield tx.save \session, {}
              sends.push [ \id, session.id ]
              info \NEW-SESSION, session
              # session-wire.send \id, session.id
            # yield reactor tx, session, it
            module.exports.$var \session, session
            if session.person
              module.exports.$var \person, (yield tx.get session.person)
            yield module.exports.session[key] it
            # yield fn.apply state, [ it ]
            # id = session.id
            # # session-cache.public = clone session.cache
            # session-cache = clone(pairs-to-obj((keys session |> filter -> !is-function(session[it]) and it != \cache) |> map -> [ it, session[it] ]))
            # # delete session-cache.public.id
            # delete session-cache.private?id
            # yield tx.save \session, session
            # session.id = session-cache.id
            # if not id
            #   session-wire.send \id, session.id
            yield tx.commit!
          catch e
            yield tx.rollback!
            throw e
          session-wire.session-id = session.id
          for s in sends
            session-wire.send s.0, s.1

    # session.$observe 'no-id', co.wrap (id) ->*
    #   session.persistent = false
    session-wire.observe 'id', co.wrap (id) ->*
      if id
        if record = yield world.get id
          # session.send '', record.public
          session-wire.send \id, id
          session-wire.session-id = id
          # for key of session
          #   delete session[key]
          # extend session, record.$get!
        else
          session-wire.send \id, null
          session-wire.session-id = null
      else
        session.send \route, ''
          # session.send \route, \login
        # if not session.persistent
        #   if record
        #     $info 'Loading session', record
        #     session.persistent = true
        #     session <<< record
        #   else
        #     delete session.id
    # session.$observe 'route', co.wrap (route) ->*
    #   if (not session.persistent) and session.route and session.route not in <[ login signup]>
    #     session.route = ''
    # session.$observe '', debounce 300, co.wrap ->*
    #   return if not session.persistent
    #   yield world.save \session, session
    #   if shell.session-paths
    #     paths = world.path-values-from-object(session.$get!) |> map -> it.path
    #     shell.session-paths = unique shell.session-paths ++ paths
    #   # $info 'Session saved', session.$get!
    storage.$logger = $info
    storage.$observe '', ->
      (keys storage) |> each (key) ->
        val = storage[key]
        if m = /^data\:([\w\d\/]+)\;/.exec val
          type = m.1
          data = new Buffer (val.replace /^data\:([\w\d\/]+)\;base64\,/, ''), 'base64'
          delete storage[key]
          bucket = gcloud.storage project-id: olio.config.gcloud.project, key-filename: olio.config.gcloud.keyfile .bucket olio.config.gcloud.bucket
          file = bucket.file(id = uuid!)
          writer = file.create-write-stream!
          writer.end data
          writer.on \error, -> info it
          writer.on \finish, ->
            file.make-public (error) ->
              info error if error
              file.set-metadata content-type: type, (error) ->
                info error if error
                session.storage ?= {}
                session-wire.send "storage.#key", "#{olio.config.gcloud.bucket}.storage.googleapis.com/#id"
                # session.storage[key] = "#{olio.config.gcloud.bucket}.storage.googleapis.com/#id"

export shell = ->*
  require! \readline
  rl = readline.create-interface process.stdin, process.stdout, ->
    line = (it.split(' ') |> filter -> it).join(' ')
    matches = rl.completion |> filter -> //^#line//.test it
    [ matches, it ]
  rl.completion = []
  info \Hello.
  rl.set-prompt '> '
  rl.on \line, ->
    socket.emit \shell, it.trim!
  rl.on \close, ->
    info '\nGoodbye.'
    exit!
  socket = socket-io-client 'http://localhost:8001'
  socket.on \shell, ->
    info it if it
    rl.prompt!
  socket.on \completion, ->
    rl.completion = it.split('\n')
  rl.prompt!
