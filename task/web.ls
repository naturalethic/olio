require! \stylus
require! \nib
require! \browserify
require! \livescript
require! \node-notifier
require! \watchify
require! \jade
require! \esprima
require! \esprima-walk
require! \escodegen

export watch = [ __filename, \olio.ls, "#__dirname/../web/olio.ls" ]

compile-snippet = ->
  it = livescript.compile (camelize it), { +bare, -header } .slice 0, -1
  if m = /^function [a-zA-Z]+\$\(/m.exec it
    it = it.substr 0, m.index
  it = it.replace /\n/g, '' .trim!
  it = it.slice 0, -1 if it[it.length - 1] == \;
  it

indent-source = (preamble, source, indent = 2) ->
  if preamble
    "#preamble\n#{' ' * indent}#{source.split('\n').join('\n' + ' ' * indent)}"
  else
    "#{' ' * indent}#{source.split('\n').join('\n' + ' ' * indent)}"

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
        style.push state.component.name
        style.push '  display: block'
        if prop = find (-> it.key.name == \style), it.properties
          it.properties.splice (it.properties.index-of prop), 1
          style.push(indent-source null, prop.value.value.trim!) if prop.value.value.trim!
        style.push ''
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
      # fs.realpath-sync "#__dirname/../node_modules"
      fs.realpath-sync "#__dirname/../web"
      ...
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
