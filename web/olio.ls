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
  convert:        require 'html-to-vdom'
  vnode:          require 'virtual-dom/vnode/vnode'
  vtext:          require 'virtual-dom/vnode/vtext'
  diff:           require 'virtual-dom/diff'
  patch:          require 'virtual-dom/patch'
  create-element: require 'virtual-dom/create-element'

# Session
require! 'socket.io-client': socket-io
require! \rivulet
require! \wire
if config.env
  socket = socket-io "http://session.#{config.env}.copsforhire.com"
else
  socket = socket-io!

socket.on \session-validation, ->
  warn \Validation, it.0, '\n', JSON.stringify(it.1, null, 2)

window.session = JSON.parse(session-storage.get-item(\session) or '{}')

session-wire = wire socket: socket, channel: \session, logger: (...args) ->
  info "#{args.0} %c#{args.1} %c#{JSON.stringify args.2, null, 2}", 'color: #D1843C', 'color: #D23A63'
session-watchers = {}
session-wire.observe-all (path, value) ->
  $set path, value, no-report: true
  report path, value, undefined

report = (path, value, old-value) ->
  if is-object(value) or is-array(value)
    paths = (object-path.list value)
    if path
      paths = paths |> map -> "#path.#it"
    for p in paths
      for fn in (session-watchers[camelize p] or [])
        fn $get(p), undefined
  for fn in (session-watchers[camelize path] or [])
    fn value, old-value

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
global.$send = (path, value) ->
  value ?= $get path
  session-wire.send path, value
global.$watch = (paths, fn) ->
  if is-array paths
    paths |> each (path) ->
      if !is-undefined(value = $get(path))
        fn path, value, undefined
      path = camelize path
      session-watchers[path] ?= []
      session-watchers[path].push (value, old-value) -> fn path, value, old-value
  else
    if !is-undefined(value = $get(paths))
      fn value, undefined
    path = camelize paths
    session-watchers[path] ?= []
    session-watchers[path].push fn
global.$get = (path) ->
  object-path.get session, (camelize path)
global.$del = (path) ->
  old-value = object-path.get session, (camelize path)
  return if is-undefined old-value
  object-path.del session, (camelize path)
  session-storage.set-item \session, JSON.stringify(session)
  # for fn in (session-watchers[path] or [])
  #   fn undefined, old-value

# XXX: Provide function to watch undefined

window.$storage = rivulet socket, \storage
$storage.logger = (...args) ->
  if is-object(last args) or is-array(last args)
    obj = args.pop!
    args.push JSON.stringify obj
  info ...args

$send \id, (session?id or '00000000-0000-0000-0000-000000000000')

window.destroy-session = ->
  for key of session
    $del key if key is not \route
  $set \route, ''

$watch \id, ->
  if it is null
    destroy-session!

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
$watch \route, (route) ->
  go route

# Disable all form submits
q document.body .on \submit, \form, false

register-component = (name, component) ->
  # return if (name not in <[ cfh-root cfh-login cfh-signup cfh-address-input cfh-content cfh-wizard cfh-image-upload cfh-file-upload ]>) and (not /cfh\-inception/.test name) and (not /cfh\-proposal/.test name)
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
    @get = (path)    ->
      object-path.get @local, (camelize path)
    @del = (path)    ->
      object-path.del @local, (camelize path)
    @find = ~> @q.find it
    @attr = ~> @q.attr it
    render-state = {}
    @render = ~>
      info "Rendering #{@tag-name}"
      data = (extend-new session, @local)
      html = @view data
      return if not html.trim!
      html = '<div>' + html + '</div>'
      last-tree = render-state.tree
      render-state.tree = vdom.convert(VNode: vdom.vnode, VText: vdom.vtext)(html)
      if not last-tree
        node = vdom.create-element(render-state.tree)
        while node.children.length
          @append-child node.children.0
      else
        vdom.patch this, vdom.diff(last-tree, render-state.tree)
    @start!
    @render!
    @ready!
    while attribute-queue.length
      @q.trigger 'attribute', attribute-queue.shift!

  # prototype.detached-callback = ->
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
        options.send-local and @send options.send-local
        options.send-path  and $send options.send-path
        options.render     and @render!
      if query
        @q.on name, query, fn
      else
        @q.on name, fn
    send: (path) ->
      $send path, @get path
    start: ->
    ready: ->
  prototype <<< component
  document.register-element name, prototype: prototype
