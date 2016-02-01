Module = (require \module).Module
require! \node-static
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

create-logging-function = (name, socket) ->
  (...args) ->
    date = (new Date).toISOString!split \T
    if is-string(args.0)
      args.0 = color(198, args.0)
    args.unshift "#{color(81, date.0)}#{color(239, 'T')}#{color(81, date.1)} #{color(226, (socket?handshake?address or '0.0.0.0'))} #{color(22, 'INFO')}"
    if is-object(last args) or is-array(last args)
      obj = args.pop!
    console[name] ...args
    pp obj if obj

$info = create-logging-function \info

# Loads the source and compiles a module manually, so as to be able have multiple copies
# of it with different environments, allowing each session reaction to operate within its
# own transaction.
create-dynamic-module = (path, vars = []) ->
  source = """
    export $var = (key, val) ->
      throw \"Undeclared dynamic variable '\#key'\" if key not in <[ #{vars.join (' ')}]>
      eval \"$\#key = val\"
    #{fs.read-file-sync path, 'utf8'}
    """
  source = livescript.compile source, { +bare, -header }
  if vars.length
    source = """
      var #{(vars |> map -> '$' + it).join ', '};
      #source
    """
  module = new Module uuid!
  module.paths = [ "#{process.cwd!}/lib", "#{process.cwd!}/node_modules" ]
  module._compile source
  module.exports

read-schema = (schema) ->
  s = require "./schema/session/#schema"
  object-walk s, (v, k, o) ->
    if k is \required
      o[k] = (v |> map -> camelize it)
    if k is \type and v is \object
      o.additional-properties = false
  s

create-validator = ->
  validator = ajv all-errors: true, v5: true
  schemas = (glob.sync 'schema/session/**/*.ls') |> map -> /^schema\/session\/(.*)\.ls$/.exec(it).1
  for schema in schemas
    # $info 'Adding validation', color(207, (schema.replace /\//g, '.'))
    try
      validator.add-schema (read-schema schema), (schema.replace /\//g, '.')
    catch e
      $info 'Error reading schema', schema
      throw e
  validator

create-session-server = ->
  options = {}
  if olio.config.session.ssl
    http = require 'https'
    options.key = fs.read-file-sync olio.config.session.key, 'utf8'
    options.cert = fs.read-file-sync olio.config.session.cert, 'utf8'
  else
    http = require 'http'
  if olio.config.session.static
    $info 'Serving static files'
    file = new node-static.Server './public'
    server = http.create-server options, (request, response) ->
      if not fs.exists-sync "./public#{request.url}"
        $info "Unknown url '#{request.url}', sending index"
        request.url = '/'
      request.add-listener \end, ->
        file.serve request, response
      .resume!
  else
    server = http.create-server options, (request, response) ->
      request.add-listener \end, ->
        response.end 'Session'
      .resume!
  port = olio.option.port or olio.config.session?port or 8000
  $info 'Starting session server on port', color(78, port)
  server.listen port, '0.0.0.0'
  socket-io server

create-storage-agent = (socket) ->
  storage = rivulet {}, socket, \storage
  storage.$logger = create-logging-function \info, socket
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
              socket.wire.send "storage.#key", id

load-or-create-session = (tx, id) ->*
  if id and session = yield tx.get id
    tx.$info 'Loaded session', session.id
    return session
  session = yield tx.save \session
  tx.$info 'Created session', session.id
  session

create-session-agent = (socket, validator, promote) ->
  create-storage-agent socket
  socket.wire = wire socket: socket, channel: \session, validator: validator, logger: $info
  socket.wire.info = create-logging-function \info, socket
  socket.wire.promote = promote
  socket.wire.info 'Connection established'
  glob.sync 'react/session/**/*.ls' |> each (path) ->
    return if not session-reactors = (create-dynamic-module path).session
    for property of session-reactors
      create-session-observer socket.wire, path, property
  socket.wire.world-observers = glob.sync 'react/world/**/*.ls' |> map -> create-world-observer socket.wire, it

create-world-observer = (wire, path) ->
  module = create-dynamic-module path, <[ info world send session person ]>
  module.$var \info, $info
  module.$var \world, world
  module.$var \send, wire.send
  module

create-session-observer = (wire, path, property) ->
  wire.observe property, co.wrap ->*
    wire.info "Session reaction #{color 95, path}:#{color(32, property)}", it
    module = create-dynamic-module path, <[ info world send invalidate session person ]>
    sends = []
    tx = yield world.transaction!
    tx.$info = wire.info
    tx.$promote = wire.promote
    module.$var \info, wire.info
    module.$var \world, tx
    module.$var \send, (path, value) -> sends.push [ path, value ]
    module.$var \invalidate, wire.invalidate
    try
      if property is \id
        wire.session-id = it
      session = yield load-or-create-session tx, wire.session-id
      if session.id != wire.session-id
        wire.session-id = session.id
        if property != \id
          sends.push [ \id, session.id ]
      session.ip = wire.socket.handshake.address
      module.$var \session, session
      if session.person
        module.$var \person, (yield tx.get session.person)
      tx.$session = session.id
      yield module.session[property] it
      yield tx.commit!
    catch e
      yield tx.rollback!
      throw e
    for s in sends
      wire.send s.0, s.1

export session = ->*
  validator = create-validator!
  shell = create-shell-server!
  server = create-session-server!
  promotion-queue = []
  promote = -> promotion-queue.push it
  set-interval ->
    return if !promotion-queue.length
    items = promotion-queue.slice!
    promotion-queue.length = 0
    items |> each (item) ->
      (values server.sockets.connected) |> each (socket) ->
        return if !socket.wire.session-id or socket.wire.session-id == item.session
        socket.wire.world-observers |> each (observer) ->
          co ->*
            if socket.wire.session-id and session = yield world.get socket.wire.session-id
              observer.$var \session, session
              if session.person and person = yield world.get session.person
                observer.$var \person, person
            yield observer[item.kind] item.doc if observer[item.kind]
  , 200
  server.on \connection, (socket) ->
    create-session-agent socket, validator, promote

create-shell-server = ->
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
  shell

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
