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

export watch = [ __filename, "#__dirname/../web/olio.ls" ]

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
            style.push(stylus(prop.value.value).use(nib!).import(\nib).render!)
          if prop = find (-> it.key.name == \view), it.properties
            it.properties.splice (it.properties.index-of prop), 1
            info 'Writing    -> public/index.html'
            fs.write-file-sync \public/index.html, jade.render(prop.value.value, pretty: true)
          continue
        if prop = find (-> it.key.name == \style), it.properties
          it.properties.splice (it.properties.index-of prop), 1
          style.push(stylus(indent-source state.component.name, prop.value.value).use(nib!).import(\nib).render!)
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
