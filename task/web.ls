require! \stylus
require! \nib
require! \browserify
require! \browserify-css
require! \inflection
require! \livescript
require! \node-notifier
require! \watchify
require! \jade

promisify-all stylus!__proto__

export watch = [ __filename ]

olio.config.web ?= {}
olio.config.web.app ?= 'test'

compile-snippet = ->
  it = livescript.compile (camelize it), { +bare, -header } .slice 0, -1
  if m = /^function [a-zA-Z]+\$\(/m.exec it
    it = it.substr 0, m.index
  it = it.replace /\n/g, '' .trim!
  it = it.slice 0, -1 if it[it.length - 1] == \;
  it

component-tree = (tree, lines = [], indent = 2) ->
  for key, val of tree
    if typeof! val == \Function
      lines.push "#{' ' * indent}#key: ``#{val.to-string!replace /\n\s*/g, ''}``"
    else if typeof! val == \Object
      lines.push "#{' ' * indent}#key:"
      component-tree val, lines, indent + 2
    else
      lines.push "#{' ' * indent}#key: #{JSON.stringify val}"

indent-source = (preamble, source, indent = 2) ->
  "#preamble\n#{' ' * indent}#{source.split('\n').join('\n' + ' ' * indent)}"

prep = ->
  info 'Syncing    -> tmp'
  exec "rsync --exclude '*.ls' -u web/* tmp/"
  info 'Syncing    -> public'
  exec "rsync -v -u #{glob.sync('web/**/*.!(ls)').join(' ')} public"

stitch = ->*
  style = []
  script = []
  script.push """
    window.q = require 'jquery'
    require 'webcomponents.js'
    jade = require 'jade/runtime'
    m = require 'mithril'
    m.convert = require 'template-converter'
    kefir = require 'kefir'
    s = ^^kefir
    s.from-child-events = (target, event-name, query, transform = id) ->
      s.stream (emitter) ->
        handler = -> emitter.emit transform it
        q target .on event-name, query, handler
        -> q target .off event-name, query, handler
    history = require 'html5-history-api'
    window.current-route = -> ((history.location || window.location).href.split '#').1?substr(1) or ''
    q window .on 'load', ->
      q window .trigger q.Event 'route', route: current-route!
    q window .on 'popstate', ->
      q window .trigger q.Event 'route', route: current-route!
    # window.deepstream = require 'deepstream.io-client-js/dist/deepstream'
    require './index.css'
    require 'livescript-utilities'
    window <<< require 'prelude-ls'
    if console.log.apply
      <[ log info warn error ]> |> each (key) -> window[key] = -> console[key] ...&
    else
      <[ log info warn error ]> |> each (key) -> window[key] = console[key]
  """
  for it in glob.sync 'web/lib/**/*.ls'
    script.push "require '.#{it.substring 7, it.length - 3}'"
    fs.write-file-sync "tmp/#{it.substring 7, it.length - 3}.js", livescript.compile(fs.read-file-sync(it).to-string!, { -header })
  for it in glob.sync 'web/**/*.ls'
    continue if /^web\/lib/.test it
    delete require.cache["#{process.cwd!}/#it"]
    for key, component of require "#{process.cwd!}/#it"
      if key is \index
        html = jade.render(delete component.view, pretty: true)
        info 'Writing    -> public/index.html'
        fs.write-file-sync \public/index.html, html
        if component.style
          style.push(yield stylus(delete component.style).use(nib()).import("nib").render-async!)
        continue
      if component.style
        component.style = indent-source (dasherize key), component.style
        style.push(yield stylus(delete component.style).use(nib()).import("nib").render-async!)
      view = jade.compile-client(delete component.view, pretty: true).to-string!replace(/(^|\s)\s*\/\/.*$/gm, '').split(/\s+/m).join(' ')
      script.push "(->"
      script.push "  view-function = ``#{view}``"
      script.push "  prototype = Object.create HTMLElement.prototype"
      script.push "  prototype.attached-callback = ->"
      script.push "    m.render this, (eval m.convert view-function @start!)"
      script.push "    s.merge @intent!"
      script.push "    .map ~>"
      script.push "      info 'INTENT', it"
      script.push "      @model it"
      script.push "    .on-value ~>"
      script.push "      info 'MODEL', it"
      script.push "      m.render this, (eval m.convert view-function it)"
      script.push "    @ready!"
      script.push "  prototype <<<"
      component.module ?= ->
      component.ready ?= ->
      component.start ?= -> {}
      component.intent ?= -> {}
      component.model ?= -> s.constant {}
      component-tree component, script, 4
      script.push "  document.register-element '#{dasherize key}', prototype: prototype"
      script.push ")!"
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
  exec "mkdir -p tmp"
  exec "mkdir -p public"
  bundler = yield setup-bundler!
  watcher.watch <[ validate.ls olio.ls host.ls web ]>, persistent: true, ignore-initial: true .on 'all', (event, path) ->
    info "Change detected in '#path'..."
    co bundler.build
  co bundler.build
