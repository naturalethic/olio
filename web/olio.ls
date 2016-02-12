window.global = window
window.q = require \jquery

window <<< require 'prelude-ls'
require \livescript-utilities
if console.log.apply
  <[ log info warn error ]> |> each (key) -> window[key] = -> console[key] ...&
else
  <[ log info warn error ]> |> each (key) -> window[key] = console[key]

window <<< do
  is-array:     -> typeof! it is \Array
  is-function:  -> typeof! it is \Function
  is-number:    -> typeof! it is \Number
  is-object:    -> typeof! it is \Object
  is-string:    -> typeof! it is \String
  is-undefined: -> typeof! it is \Undefined
  clone: require 'clone'

window.uuid = require('uuid').v4

global.debounce = ->
  return if &.length < 1
  wait = 1
  if is-function &0
    func = &0
  else
    wait = &0
  if &.length > 1
    if is-function &1
      func = &1
    else
      wait = &1
  timeout = null
  ->
    args = arguments
    clear-timeout timeout
    timeout := set-timeout (~>
      timeout := null
      func.apply this, args
    ), wait

require! \object-path

global.extend = (...args) ->
  args.unshift true
  q.extend ...args
  args.1

global.extend-new = (...args) ->
  args.unshift {}
  extend ...args

# Templates
require 'webcomponents.js/CustomElements'
window.jade = require 'jade/runtime'

vdom =
  vnode:          require 'virtual-dom/vnode/vnode'
  vtext:          require 'virtual-dom/vnode/vtext'
  diff:           require 'virtual-dom/diff'
  patch:          require 'virtual-dom/patch'
  create-element: require 'virtual-dom/create-element'
  convert:        require 'html-to-vdom'

# Session
require! 'socket.io-client': socket-io
require! \rivulet
require! \wire
socket = socket-io transports: <[ websocket ]>

window.session = JSON.parse(session-storage.get-item(\session) or '{}')
session-cached-id = delete session.id

session-wire = wire socket: socket, channel: \session, logger: (...args) ->
  info "#{args.0} %c#{args.1} %c#{JSON.stringify args.2, null, 2}", 'color: #D1843C', 'color: #D23A63'
session-watchers = {}
session-wire.observe-all (path, value) ->
  $set path, value, no-report: true
  report path, value, undefined
window.validation = require('./lib/validation')
validation.tree = {}
session-wire.observe-all-validation (path, value) ->
  for key in keys(validation.tree)
    delete validation.tree[key]
  validation.tree <<< value
  $set \validation, validation.tree
  q '.invalid' .remove-class \invalid
  for [ path, keyword ] in (object-path.list validation.tree |> (filter -> /keyword$/.test it) |> map -> [ /(.*)\.keyword$/.exec(it).1, object-path.get validation.tree, it ])
    object-path.set validation.tree, "#path.message", validation.message ((object-path.get validation.tree, path) <<< path: path)
    for el in q "[set='#{dasherize path}']"
      q(el).add-class \invalid
      el.find 'input' .add-class \invalid
      el.find 'label' .add-class \invalid
    for el in q "[validation-text='#{dasherize path}']"
      q(el).add-class \invalid
      q(el).text object-path.get validation.tree, "#path.message"

report-match = (path, search) ->
  //^#{search.replace(/\./g, '\\.').replace(/\*/g, '\\d+')}$//.test path

report-impl = (path, value, old-value) ->
  for watchers in (keys session-watchers |> (filter -> report-match (camelize path), it) |> map -> session-watchers[it])
    if not empty watchers
      info '$on:', path, value, old-value
    # XXX: why are watchers turning into undefined, see splice in detached callback
    for watcher in watchers
      watcher.fn value, old-value if watcher?fn
      watcher?options.render?render!

report = (path, value, old-value) ->
  report-impl path, value, old-value
  if is-object(value) or is-array(value)
    for child-path in (object-path.list value)
      child-path = "#path.#child-path" if path
      report-impl child-path, $get(child-path), undefined

global.$set = (path, value, options) ->
  old-value = object-path.get session, (camelize path)
  if value != old-value
    object-path.set session, (camelize path), value
    session-storage.set-item \session, JSON.stringify(session)
    report path, value, old-value if not options?no-report
global.$setq = (path, value, options) ->
  old-value = object-path.get session, (camelize path)
  if is-undefined old-value
    $set path, value, options
global.$push = (path, value, options) ->
  $set "#path.#{$get(path).length}", value, options
global.$sset = (path, value) ->
  $set path, value
  session-wire.send path, value
global.$send = (path, value, as) ->
  value ?= $get path
  as ?= path
  session-wire.send as, value

global.$on = (paths, ...args) ->
  options = first(args |> filter -> is-object it) or {}
  fn      = first(args |> filter -> is-function it)
  warn "$on called without clean: this" if not options.clean
  if is-array paths
    paths |> each (path) ->
      if !is-undefined(value = $get(path)) and fn
        info '$on:', path, value, undefined
        fn path, value, undefined
        options.render.render! if options.render
      path = camelize path
      session-watchers[path] ?= []
      session-watchers[path].push fn: (fn and ((value, old-value) -> fn path, value, old-value)), options: options
  else
    if !is-undefined(value = $get(paths)) and fn
      info '$on:', paths, value, undefined
      fn value, undefined
      options.render.render! if options.render
    path = camelize paths
    session-watchers[path] ?= []
    session-watchers[path].push fn: fn, options: options

global.$watch = (...args) ->
  warn '$watch is deprecated, use $on'
  $on ...args
global.$get = (path) ->
  object-path.get session, (camelize path)
global.$has = (path) ->
  object-path.has session, (camelize path)
global.$del = (path, options) ->
  old-value = object-path.get session, (camelize path)
  return if is-undefined old-value
  object-path.del session, (camelize path)
  session-storage.set-item \session, JSON.stringify(session)
  report path, undefined, old-value if not options?no-report

window.$storage = rivulet socket, \storage
$storage.logger = (...args) ->
  if is-object(last args) or is-array(last args)
    obj = args.pop!
    args.push JSON.stringify obj
  info ...args

window.destroy-session = (new-id) ->
  window.session = {}
  session-storage.set-item \session, JSON.stringify(session)
  if new-id
    session.id = new-id
  else
    $send \id, '00000000-0000-0000-0000-000000000000'

# History
window.history = require \html5-history-api
current-route = ->
  /http(s)?\:\/\/[^\/]+\/([^\?\#]*)/.exec(history.location or window.location).2.replace(/\//g, '-')
window.go = ->
  if (it == '' or it) and current-route! != it
    info "Routing to: '#it'"
    history.push-state null, null, "/#{it.replace(/\-/g, '/')}"
q window .on \popstate, ->
  $set \route, current-route!

socket.on \connect, ->
  return if session.id
  log \CONNECTED!
  $send \id, (session-cached-id or '00000000-0000-0000-0000-000000000000')
socket.on \reconnect, ->
  log \RECONNECTED!
  session-cached-id := session.id
  $send \id, session.id
socket.on \disconnect, ->
  log \DISCONNECTED!

$on \id, ->
  if it != session-cached-id
    destroy-session it

$on \route, (route) ->
  go route

# Disable all form submits
q document.body .on \submit, \form, false

register-component = (name, component) ->
  info "Registering %c#name", 'color: #B184A1'
  prototype = Object.create HTMLElement.prototype
  attribute-queue = []
  prototype.attached-callback = ->
    @q = q this
    if parent = (@q.parents() |> find -> it.__olio__)
      @local = Object.create parent.local
    else
      @local = {}
    @set = (path, value) ->
      object-path.set @local, (camelize path), value
    @setq = (path, value) ->
      old-value = object-path.get @local, (camelize path)
      if is-undefined old-value
        @set path, value
    @get = (path)    ->
      object-path.get @local, (camelize path)
    @del = (path)    ->
      object-path.del @local, (camelize path)
    @push = (path, value) ->
      @set "#path.#{@get(path).length}", value
    @find = ~> @q.find it
    @attr = ~> @q.attr it
    render-state = {}
    @render = ~>
      return if not @view
      info "Rendering #{@tag-name}"
      @original-content = @innerHTML
      data = (extend-new session, @local)
      data.content = @original-content
      data.uuid = -> data._lastuuid = uuid!
      data.lastuuid = -> data._lastuuid
      html = @view data
      return if not html.trim!
      html = '<div>' + html + '</div>'
      last-tree = render-state.tree
      render-state.tree = vdom.convert(VNode: vdom.vnode, VText: vdom.vtext)(html)
      if not last-tree
        @innerHTML = ''
        node = vdom.create-element(render-state.tree)
        while node.children.length
          @append-child node.children.0
      else
        vdom.patch this, vdom.diff(last-tree, render-state.tree)
      @find 'form' .attr \novalidate, ''
    @start!
    @render!
    @ready!
    while attribute-queue.length
      @q.trigger 'attribute', attribute-queue.shift!
    @q.trigger q.Event \component

  prototype.detached-callback = ->
    for path, watchers of session-watchers
      for watcher in watchers.slice!
        if watcher.options?clean == this
          watchers.splice (watchers.index-of watcher), 1

  prototype.attribute-changed-callback = (name, old-value, new-value) ->
    if @q
      @q.trigger 'attribute', [ name, new-value, old-value ]
    else
      attribute-queue.push [ name, new-value, old-value ]

  prototype <<< do
    __olio__: true
    on: (name, ...args) ->
      query   = first(args |> filter -> is-string it)
      options = first(args |> filter -> is-object it) or {}
      fn      = first(args |> filter -> is-function it)
      if fn
        options.call = fn
      if name is \attribute
        options.stop-propagation = true
      fn = (event, ...data) ~>
        event.prevent-default! if options.prevent-default
        event.stop-propagation! if options.stop-propagation
        value = null
        if options.value
          value = options.value
        if options.extract
          value = switch options.extract
          | \target   => q(event.current-target)
          | \value    => q(event.current-target).val!
          | \truth    => q(event.current-target).prop \checked
          | otherwise => q(event.current-target).attr options.extract
        if data.length
          value = data
          value = data.0 if data.length == 1
          if options.extract
            value = object-path.get data.0, (camelize options.extract)
        value ?= event
        if options.as
          value = switch options.as
          | \number => Number value
        info name.to-upper-case!, (query or @tag-name.to-lower-case!), options, value
        options.set-local  and @set options.set-local, value
        options.set        and $set options.set, value
        options.call       and (if is-array value then options.call ...value else options.call value)
        options.send       and $send options.send, value
        options.send-local and @send options.send-local, options.send-as
        options.send-path  and $send options.send-path, undefined, options.send-as
        options.render     and @render!
      if query
        @q.on name, query, fn
      else
        @q.on name, fn
    send: (path, as) ->
      as ?= path
      $send as, @get path
    start: ->
    ready: ->
  prototype <<< component
  document.register-element name, prototype: prototype
