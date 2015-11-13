require! \stylus
require! \nib
require! \browserify
require! \inflection
require! \livescript
require! \node-notifier
require! \watchify
require! \jade
require! \esprima
require! \esprima-walk
require! \escodegen
require! \http
require! \node-static
require! \http
require! 'socket.io': socket-io
require! 'fast-json-patch': patch
require! \baobab
require! \rethinkdbdash
require! \co

export watch = [ __filename, \olio.ls, \session.ls, \react, "#__dirname/../web/olio.ls" ]

compile-snippet = ->
  it = livescript.compile (camelize it), { +bare, -header } .slice 0, -1
  if m = /^function [a-zA-Z]+\$\(/m.exec it
    it = it.substr 0, m.index
  it = it.replace /\n/g, '' .trim!
  it = it.slice 0, -1 if it[it.length - 1] == \;
  it

indent-source = (preamble, source, indent = 2) ->
  "#preamble\n#{' ' * indent}#{source.split('\n').join('\n' + ' ' * indent)}"

prep = ->
  info 'Syncing    -> tmp'
  exec "rsync -maz --exclude '*.ls' web/ tmp/"
  info 'Syncing    -> public'
  exec "rsync -maz --exclude '*.js' --exclude '*.css' tmp/ public/"

stitch = ->
  style = []
  script = [
    fs.read-file-sync("#__dirname/../web/olio.ls").to-string!
  ]
  try
    for it in glob.sync 'web/**/*.ls'
      name = it.replace(/\//g, '-').substring(4, it.length - 3)
      info "Writing    -> component/#name.js"
      syntax = esprima.parse livescript.compile(fs.read-file-sync(it).to-string!)
      state =
        component: null
        components: []
      esprima-walk.walk-add-parent syntax, ->
        if it.type is \MemberExpression and it.object?name == \out$
          state.component = name: dasherize it.property.name
          state.components.push state.component
          if state.component.name != \index
            script.push "register-component '#{state.component.name}', require('./component/#{name}').#{state.component.name}"
        if state.component and it.type is \ObjectExpression and it.parent.left?name and (dasherize it.parent.left.name) == state.component.name
          state.component.object = it
      for component in state.components
        it = component.object
        if component.name == \index
          if prop = find (-> it.key.name == \style), it.properties
            it.properties.splice (it.properties.index-of prop), 1
            style.unshift(prop.value.value.trim!)
          if prop = find (-> it.key.name == \view), it.properties
            it.properties.splice (it.properties.index-of prop), 1
            info 'Writing    -> public/index.html'
            fs.write-file-sync \public/index.html, jade.render(prop.value.value, pretty: true)
          continue
        if prop = find (-> it.key.name == \style), it.properties
          it.properties.splice (it.properties.index-of prop), 1
          style.push(indent-source state.component.name, prop.value.value.trim!) if prop.value.value.trim!
        if prop = find (-> it.key.name == \view), it.properties
          view = esprima.parse jade.compile-client(prop.value.value)
          prop.value =
            type: 'FunctionExpression'
            id: null
            params: [ { type: 'Identifier', name: 'locals' } ]
            defaults: []
            body: { type: 'BlockStatement', body: view.body.0.body.body }
            generator: false
            expression: false
      fs.write-file-sync "tmp/component/#name.js", escodegen.generate syntax, format: { indent: { style: '  ' } }
  catch e
    info e.stack
  # info '\nLIVESCRIPT'
  # info script.join '\n'
  # info '\nJAVASCRIPT'
  # info livescript.compile(script.join('\n'), { -header})
  script.unshift "window.config = #{JSON.stringify olio.config.web}"
  info 'Writing    -> tmp/index.ls'
  fs.write-file-sync \tmp/index.ls, script.join('\n')
  info 'Writing    -> tmp/index.js'
  # XXX: chop out livescript utilities from this compile output
  fs.write-file-sync \tmp/index.js, livescript.compile(script.join('\n'), { -header })
  info 'Writing    -> tmp/index.styl'
  style = style.join '\n'
  fs.write-file-sync \tmp/index.styl, style
  info 'Writing    -> public/index.css'
  style = stylus(style)
  style.use(nib!).import(\nib)
  style.get('paths').push \tmp
  style.set 'include css', true
  fs.write-file-sync \public/index.css, style.render!

setup-bundler = ->*
  no-parse = []
  # try
  #   no-parse.push require.resolve("#{process.cwd!}/node_modules/jquery")
  # info "#__dirname/node_modules/olio/node_modules"
  bundler = watchify browserify <[ ./tmp/index.js ]>, {
    paths:
      fs.realpath-sync "#__dirname/../node_modules"
      fs.realpath-sync "#__dirname/../web"
    no-parse: no-parse
    detect-globals: false
    cache: {}
    package-cache: {}
  }
  bundle = ->
    info 'Browserify -> public/index.js'
    bundler.bundle (err, buf) ->
      return info err if err
      fs.write-file-sync 'public/index.js', buf
      info "--- Done in #{(Date.now! - bundler.time) / 1000} seconds ---"
      node-notifier.notify title: \Olio, message: "Site Rebuilt: #{(Date.now! - bundler.time) / 1000}s"
      process.exit 0 if olio.option.exit
  bundler.on \update, bundle
  bundler.build = ->
    try
      bundler.time = Date.now!
      prep!
      stitch!
    catch e
      info e
    bundle! if not bundler._bundled
  bundler

export web = ->*
  exec "mkdir -p tmp/component"
  exec "mkdir -p public"
  bundler = yield setup-bundler!
  build = debounce bundler.build
  watcher.watch <[ validate.ls olio.ls host.ls web ]>, persistent: true, ignore-initial: true .on 'all', (event, path) ->
    info "Change detected in '#path'..."
    build!
  build!

export service = ->*
  try
    r = null
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
  $uuid = ->* yield r._r.uuid!
  port = olio.option.port or olio.config.web?port or 8000
  schema = require "#{process.cwd!}/session"
  server.listen port, '127.0.0.1'
  server = socket-io server
  server.on \connection, (socket) ->
    info socket.handshake.address, \CONNECTION
    session = new baobab
    socket.emit \session, (patch.compare {}, session.get!)
    receive-last = []
    socket.on \session, ->
      info socket.handshake.address, \RECV, it
      receive-last := it |> map -> JSON.stringify it
      new-session = session.serialize!
      patch.apply new-session, it
      session.deep-merge new-session
    glob.sync 'react/**/*' |> each ->
      $require = require
      module = {}
      # XXX: port this to esprima?
      eval livescript.compile [
        "out$ = module"
        "require = $require.cache['#{fs.realpath-sync './olio.ls'}'].require"
        "$merge = -> session.deep-merge it"
        "$unset = -> session.unset it.split('.')"
        (fs.read-file-sync it .to-string!)
      ].join '\n'
      keys module |> each (key) ->
        module[key] = co.wrap(module[key])
        module[key].bind module
        cursor = session.select (dasherize key).split \-
        cursor.on \update, ->
          return if it.data.current-data is undefined
          return if it.data.previous-data and !patch.compare(it.data.current-data, it.data.previous-data).length
          module[key] session.serialize!
    session.select \id
    .on \update, (event) ->
      (co.wrap ->*
        id = session.get \id
        return if id is undefined
        return if event.data.previous-data == event.data.current-data
        info socket.handshake.address, \IDCHANGE, event.data.previous-data, event.data.current-data
        if id
          record = first (yield r.table(\session).filter(id: session.get(\id)))
          if record
            info socket.handshake.address, \LOAD-SESSION, record
            session.set record
          else if session.get \persistent
            info socket.handshake.address, \INSERT-SESSION, session.serialize!
            yield r.table(\session).insert session.serialize!
        else if event.data.previous-data
          session.root.set <[ person authentic ]>, false
          yield r.table(\session).get(event.data.previous-data).delete!
      )!
    session.root.start-recording 1
    session.root.on \update, ->
      # Don't send session changes that were just received from client
      diff = patch.compare session.root.get-history!0, session.root.get!
      if diff.length and (id = session.get \id) and session.get \persistent
        info socket.handshake.address, \UPDATE-SESSION, session.serialize!
        r.table(\session).get(id).update(session.serialize!).run!
      diff = diff |> filter -> JSON.stringify(it) not in receive-last
      receive-last := []
      if diff.length
        info socket.handshake.address, \EMIT, diff
        socket.emit \session, diff if diff.length
      if session.get \end
        socket.disconnect!

export seed = ->*
  r = null
  r = rethinkdbdash olio.config.db{host}
  try
    yield r.db-drop olio.config.db.name
  if olio.config.db.name not in (yield r.db-list!)
    info "Creating database '#{olio.config.db.name}'"
    yield r.db-create olio.config.db.name
  r = r.db olio.config.db.name
  for table in  difference (olio.config.db.tables ++ <[ session ]>), (yield r.table-list!)
    info "Creating table '#table'"
    yield r.table-create table
  seed = require fs.realpath-sync './seed.ls'
  for key, val of seed
    for item in val
      uuid = yield r._r.uuid!
      info "Adding '#key' #uuid"
      yield r.table(key).insert { id: uuid } <<< item
  process.exit!

export list = ->*
  r = rethinkdbdash olio.config.db{host}
  r = r.db olio.config.db.name
  info yield r.table(olio.task.2)
  process.exit!
