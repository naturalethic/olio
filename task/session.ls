Module = (require \module).Module
require! \node-static
require! \http
require! 'socket.io': socket-io
require! 'socket.io-client': socket-io-client
require! \co
require! \rivulet
require! \world
require! \gcloud
require! \jsonschema
require! \object-path : \objectpath

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
  # Validation schemas are in ./schema
  # Examples: https://github.com/tdegrunt/jsonschema/blob/master/examples/all.js
  validator = new jsonschema.Validator
  schemas = (glob.sync 'schema/*.ls') |> map -> fs.path.basename(it).slice 0, -3
  for schema in schemas
    validator.add-schema (require("./schema/#schema") <<< additional-properties: false), "/" + schema
  root-schema =
    type: \object
    properties: {}
    additional-properties: false
  for schema in (schemas |> filter -> it.split('-').length is 1)
    root-schema.properties[schema] =
      $ref: schema
  validate = (root) ->
    validation = {}
    for error in (validator.validate root, root-schema).errors
      objectpath.set validation, error.property.replace('instance.', ''), error{schema, message}
    validation
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
        if command = objectpath.get command-tree, path
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
    session = rivulet {}, socket, \session
    storage = rivulet {}, socket, \storage
    validii = rivulet {}, socket, \validation
    session.$logger = $info
    session.$observe '$.end', ->
      $info 'Disconnecting'
      session.$socket.disconnect!
    glob.sync 'react/**/*' |> each ->
      module = new Module
      module.paths = [ "#{process.cwd!}/lib", "#{process.cwd!}/node_modules" ]
      module._compile livescript.compile ([
        "export $local = {}"
        "$info = -> $local.info ...&"
        (fs.read-file-sync it .to-string!)
      ].join '\n'), { +bare }
      module.exports.$local.info = $info
      return if not module.exports.session
      keys module.exports.session |> each (key) ->
        reactor = module.exports.session[key]
        reactor.bind module.exports
        $info 'Observing', color(206, key)
        session.$observe key, co.wrap ->*
          $info "Session reaction '#key'", it
          tx = yield world.transaction!
          tx.$info = $info
          try
            yield reactor tx, session, it
            yield tx.commit!
          catch e
            info e
            yield tx.rollback!
    session.$observe '$.id', co.wrap (id) ->*
      $info 'Session Id', id
      if id
        if not session.persistent
          record = yield world.get id
          if record
            $info 'Loading session', record
            session.persistent = true
            session <<< record
          else
            delete session.id
    session.$observe '$.route', co.wrap (route) ->*
      if (not session.persistent) and session.route and session.route not in <[ login signup]>
        session.route = ''
    session.$observe '$', debounce 300, co.wrap ->*
      return if not session.persistent
      validation = validate session: session
      if keys validation
        $info color(124, '*** VALIDATION FAULT ***'), validation
      yield world.save \session, session
      if shell.session-paths
        paths = world.path-values-from-object(session.$get!) |> map -> it.path
        shell.session-paths = unique shell.session-paths ++ paths
      # $info 'Session saved', session.$get!
    storage.$logger = $info
    storage.$observe '$', ->
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
                session.storage[key] = "#{olio.config.gcloud.bucket}.storage.googleapis.com/#id"

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
