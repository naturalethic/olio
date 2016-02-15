Module = (require \module).Module
require! \node-static
require! 'socket.io': socket-io
require! 'socket.io-client': socket-io-client
require! 'rabbit.js' : rabbit
require! \co
require! \rivulet
require! \world
require! \gcloud
require! \ajv
require! \object-walk
require! \wire
require! \os

export watch = [ __filename, \olio.ls, \schema, \react, "#__dirname/../lib" ]

create-logging-function = (name, socket) ->
  (...args) ->
    date = (new Date).toISOString!split \T
    if is-string(args.0)
      args.0 = color(198, args.0)
    id = (socket?wire?session-id or '    ').substring 0, 4
    ip = '      '
    if address = socket?request.connection.remote-address
      ip = new Buffer(address.split('.') |> map parse-int).to-string(\base64).substring 0, 6
    # ip = ((socket?request.connection.remote-address or '') + (' ' * 15)).substring 0, 15
    args.unshift "#{color(22, name.to-upper-case!)} #{color(81, date.0)}#{color(239, 'T')}#{color(81, date.1)} #{color(226, ip)} #{color(39, id)}"
    if is-object(last args) or is-array(last args)
      obj = args.pop!
    if obj
      if olio.config.log?compact
        args.push JSON.stringify(obj)
        console[name] ...args
      else
        console[name] ...args
        pp obj
    else
      console[name] ...args

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
  if olio.config.session.ssl and not olio.option.disable-ssl
    options =
      key: fs.read-file-sync olio.config.session.key, 'utf8'
      cert: fs.read-file-sync olio.config.session.cert, 'utf8'
    create-server = ->
      (require 'https').create-server options, it
  else
    create-server = ->
      (require 'http').create-server it
  if olio.config.session.static
    $info 'Serving static files'
    file = new node-static.Server './public', cache: 1
    server = create-server (request, response) ->
      if not fs.exists-sync "./public#{request.url}"
        $info "Unknown url '#{request.url}', sending index"
        request.url = '/'
      request.add-listener \end, ->
        file.serve request, response
      .resume!
  else
    server = create-server (request, response) ->
      request.add-listener \end, ->
        response.end 'Session'
      .resume!
  if port = olio.config.session.ssl
    $info 'Starting redirect server on port', color(78, olio.config.session.port)
    (require 'http').create-server (request, response) ->
      response.write-head 302, Location: "https://#{request.headers.host.split(':').0}:#{port}"
      response.end!
    .listen olio.config.session.port, '0.0.0.0'
  else
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
  socket.wire = wire socket: socket, channel: \session, validator: validator, logger: (create-logging-function \info, socket)
  socket.wire.info = create-logging-function \info, socket
  socket.wire.promote = promote
  socket.wire.info 'Connection established'
  socket.wire.send \hostname, os.hostname!
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
      if e.stack
        wire.send \error, e.stack
      else
        wire.send e
      throw e
    for s in sends
      wire.send s.0, s.1

create-rabbit-agent = (socket) ->*
  new Promise (resolve, reject) ->
    context = rabbit.create-context "amqp://#{olio.config.rabbit.host}"
    context.on \ready, ->
      agent =
        pub: context.socket \PUB
        sub: context.socket \SUB
      agent.pub.connect \world
      agent.sub.connect \world
      agent.sub.set-encoding \utf8
      resolve agent

export session = ->*
  validator = create-validator!
  shell = create-shell-server! if olio.config.session.shell
  server = create-session-server!
  promotion-queue = []
  if olio.config.rabbit.enabled
    rabbit = yield create-rabbit-agent!
    rabbit.sub.on \data, ->
      promotion-queue.push JSON.parse it
    promote = -> rabbit.pub.write (JSON.stringify it), \utf8
  else
    promote = ->
      $info \ADDINGPROMOTE, JSON.stringify(it), it
      promotion-queue.push JSON.stringify(it)
  set-interval ->
    return if !promotion-queue.length
    try
      items = promotion-queue.slice!
      promotion-queue.length = 0
      items |> (map -> JSON.parse it) |> each (item) ->
        try
          (values server.sockets.connected) |> each (socket) ->
            try
              return if !socket.wire.session-id # or socket.wire.session-id == item.session
              socket.wire.world-observers |> each (observer) ->
                co ->*
                  try
                    if socket.wire.session-id and session = yield world.get socket.wire.session-id
                      observer.$var \session, session
                      if session.person and person = yield world.get session.person
                        observer.$var \person, person
                    yield observer[item.kind] item.doc if observer[item.kind]
                  catch e
                    $info 'Promotion failure (4)'
                    info e
            catch e
              $info 'Promotion failure (3)'
              info e
        catch e
          $info 'Promotion failure (2)'
          info e
    catch e
      $info 'Promotion failure (1)'
      info e
  , 200
  server.on \connection, (socket) ->
    create-session-agent socket, validator, promote

create-shell-server = ->
  port = olio.config.session.shell
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
