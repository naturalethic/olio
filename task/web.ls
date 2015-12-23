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

export watch = [ __filename, \olio.ls, "#__dirname/../web", "#__dirname/../lib" ]

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

$info = (action, path) ->
  info color(112, action) + (' ' * (14 - action.length)) + color(231, '-> ') + color(220, path)

prep = ->
  $info \Syncing, \tmp
  exec "rsync -maz --exclude '*.ls' web/ tmp/"
  $info \Syncing, \public
  exec "rsync -maz --exclude '*.js' --exclude '*.css' tmp/ public/"

stitch = (path) ->
  fs.write-file-sync('tmp/rivulet.js', livescript.compile fs.read-file-sync("#__dirname/../web/rivulet.ls").to-string!)
  if path
    components = JSON.parse(fs.read-file-sync 'tmp/components.json', 'utf8')
  else
    components = {}
  try
    for it in glob.sync 'web/**/*.ls'
      continue if path and it is not path
      name = it.replace(/\//g, '-').substring(4, it.length - 3)
      $info \Writing, "component/#name"
      syntax = esprima.parse livescript.compile(fs.read-file-sync(it).to-string!)
      component = {}
      esprima-walk.walk-add-parent syntax, ->
        if it.type is \MemberExpression and it.object?name == \out$
          component <<< name: dasherize it.property.name
        if component.name and it.type is \ObjectExpression and it.parent.left?name and (dasherize it.parent.left.name) == component.name
          component.object = it
      style = []
      if component.name == \index
        if prop = find (-> it.key.name == \style), component.object.properties
          style.unshift(prop.value.value.trim!)
          fs.write-file-sync "tmp/component/#name.styl", style.join '\n'
        if prop = find (-> it.key.name == \view), component.object.properties
          $info \Writing, 'public/index.html'
          fs.write-file-sync \public/index.html, jade.render(prop.value.value, pretty: true)
        continue
      components[component.name] = name
      style.push component.name
      style.push '  display: block'
      if prop = find (-> it.key.name == \style), component.object.properties
        component.object.properties.splice (component.object.properties.index-of prop), 1
        style.push(indent-source null, prop.value.value.trim!) if prop.value.value.trim!
      style.push ''
      if prop = find (-> it.key.name == \view), component.object.properties
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
      fs.write-file-sync "tmp/component/#name.styl", style.join '\n'
  catch e
    info e.stack
  fs.write-file-sync 'tmp/components.json', JSON.stringify(components)
  script = [livescript.compile([
    "window.config = #{JSON.stringify olio.config.web};"
    fs.read-file-sync("#__dirname/../web/olio.ls").to-string!
  ].join('\n'), { +bare, -header })]
  for n, p of components
    script.push "registerComponent('#{n}', require('./component/#{p}').#{camelize n});"
  $info \Writing, 'tmp/index.js'
  # XXX: chop out livescript utilities from this compile output
  fs.write-file-sync 'tmp/index.js', script.join('\n')
  $info \Writing, 'public/index.css'
  style = [ fs.read-file-sync 'tmp/component/index.styl', 'utf8' ]
  for it in glob.sync 'tmp/component/**/*.styl'
      continue if it is 'tmp/component/index.styl'
      style.push "@import \"#{it.replace(/^tmp\/component\//, '')}\""
  style = stylus(style.join '\n')
  style.use(nib!).import(\nib)
  style.get('paths').push 'tmp'
  style.get('paths').push 'tmp/component'
  style.set 'include css', true
  fs.write-file-sync \public/index.css, style.render!

setup-bundler = ->*
  # no-parse =
  #   * require.resolve 'jquery'
  #   * require.resolve 'prelude-ls'
  #   * require.resolve 'uuid'
  #   * require.resolve 'webcomponents.js/CustomElements'
  #   * require.resolve 'jade/runtime'
  #   * require.resolve 'mithril'
  b = browserify <[ ./tmp/index.js ]>, {
    paths: [
      fs.realpath-sync "#__dirname/../node_modules"
      fs.realpath-sync "#__dirname/../web"
      fs.realpath-sync "tmp"
    ]
    # no-parse: no-parse
    detect-globals: false
    cache: {}
    package-cache: {}
  }
  bundler = watchify b
  bundle = ->
    $info \Browserifying, 'public/index.js'
    bundler.bundle (err, buf) ->
      return info err if err
      fs.write-file-sync 'public/index.js', buf
      info color(123, "--- Done in #{(Date.now! - bundler.time) / 1000} seconds ---")
      node-notifier.notify title: \Olio, message: "Site Rebuilt: #{(Date.now! - bundler.time) / 1000}s"
      process.exit 0 if olio.option.exit
  bundler.on \update, bundle
  bundler.build = (path) ->
    try
      bundler.time = Date.now!
      prep!
      stitch path
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
    build path
  build!
