require! \stylus
require! \nib
require! \browserify
require! \browserify-css
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

export watch = [ __filename, \session.ls, \session, "#__dirname/../web/olio.ls" ]

olio.config.web ?= {}
olio.config.web.app ?= 'test'

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

stitch = ->*
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
            style.unshift(stylus(prop.value.value).use(nib!).import(\nib).render!) if prop.value.value.trim!
          if prop = find (-> it.key.name == \view), it.properties
            it.properties.splice (it.properties.index-of prop), 1
            info 'Writing    -> public/index.html'
            fs.write-file-sync \public/index.html, jade.render(prop.value.value, pretty: true)
          continue
        if prop = find (-> it.key.name == \style), it.properties
          it.properties.splice (it.properties.index-of prop), 1
          style.push(stylus(indent-source state.component.name, prop.value.value).use(nib!).import(\nib).render!) if prop.value.value.trim!
        if prop = find (-> it.key.name == \view), it.properties
          view = esprima.parse jade.compile-client(prop.value.value, pretty: true).to-string!replace(/(^|\s)\s*\/\/.*$/gm, '').split(/\s+/m).join(' ')
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
  info 'Writing    -> tmp/index.ls'
  fs.write-file-sync \tmp/index.ls, script.join('\n')
  info 'Writing    -> tmp/index.js'
  # XXX: chop out livescript utilities from this compile output
  fs.write-file-sync \tmp/index.js, livescript.compile(script.join('\n'), { -header })
  info 'Writing    -> tmp/index.css'
  fs.write-file-sync \tmp/index.css, style.join('\n')

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
  bundler
  .transform browserify-css, {
    auto-inject-options: { verbose: false }
    process-relative-url: (url) ->
      path = /([^\#\?]*)/.exec(url).1
      base = fs.path.basename path
      exec "cp #path public/#base"
      "#base"
  }
  bundle = ->
    info 'Browserify -> public/index.js'
    bundler.bundle (err, buf) ->
      return info err if err
      fs.write-file-sync 'public/index.js', buf
      info "--- Done in #{(Date.now! - bundler.time) / 1000} seconds ---"
      node-notifier.notify title: (inflection.capitalize olio.config.web.app), message: "Site Rebuilt: #{(Date.now! - bundler.time) / 1000}s"
      process.exit 0 if olio.option.exit
  bundler.on \update, bundle
  bundler.build = ->*
    try
      bundler.time = Date.now!
      prep!
      yield stitch!
    catch e
      info e
    bundle! if not bundler._bundled
  bundler

export web = ->*
  exec "mkdir -p tmp/component"
  exec "mkdir -p public"
  bundler = yield setup-bundler!
  watcher.watch <[ validate.ls olio.ls host.ls web ]>, persistent: true, ignore-initial: true .on 'all', (event, path) ->
    info "Change detected in '#path'..."
    co bundler.build
  co bundler.build

export service = ->*
  file = new node-static.Server './public'
  server = http.create-server (request, response) ->
    if not fs.exists-sync "./public#{request.url}"
      request.url = '/'
    request.add-listener \end, ->
      file.serve request, response
    .resume!
  port = olio.option.port or olio.config.web?port or 8000
  server.listen port
  server = socket-io server
  server.on \connection, (socket) ->
    info 'New Connection'
    session = new baobab require fs.realpath-sync './session.ls'
    # session = new baobab do
    #   # route: 'login'
    #   person:
    #     identifier: ''
    #     secret: ''
    #     authentic: false
    socket.emit \session, (patch.compare {}, session.get!)
    socket.on \session, ->
      info \RECV, it
      new-session = session.serialize!
      patch.apply new-session, it
      session.deep-merge new-session
    glob.sync 'session/**/*' |> each ->
      session-module = require fs.realpath-sync it
      keys session-module |> each (key) ->
        cursor = session.select key
        cursor.on \update, ->
          return if not patch.compare(it.data.current-data, it.data.previous-data).length
          info \UPDATE
          sdata = session.root.serialize!
          cdata = cursor.serialize!
          session-module[key] sdata, cdata
          session.root.deep-merge sdata
          cursor.deep-merge cdata
    session.root.start-recording 1
    session.root.on \update, ->
      diff = patch.compare session.root.get-history!0, session.root.get!
      info \EMIT, diff
      socket.emit \session, diff if diff.length
    # session-observer = patch.observe session
    # squash = ->
    #   patch.generate session-observer
    # flush = ->
    #   patches = patch.generate session-observer
    #   info \FLUSH, JSON.stringify patches
    #   socket.emit \session, patches
    # socket.on \session, ->
    #   patch.apply session, it
    #   squash!
    #   for p in it
    #     info p
    #     pathmod = require fs.realpath-sync "./session#{p.path}.ls"
    #     if p.op == \add
    #       result = pathmod.self session
    #     extend session, result
    #     flush!
  info 'Serving on port', port


export test = ->*
  # session = (new baobab session: {}).select \session
  # session = session.set \foo, \bar
  # info session.get!
  session = new baobab { foo: {}, bar: {} } #, auto-commit: false
  # session.set \foo, {}
  # session.set \bar, {}
  (session.watch [ \zap ]).on \update, -> info \WATCH, it
  cursor = session.select <[ zap zip ]>
  cursor.set \bim, \bam
  info session.get!