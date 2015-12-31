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
global.m = require 'mithril'
m.old-convert = require \template-converter

walk-children = (children, collection = []) ->
  for child in children
    if child.node-type is 1
      el =
        tag: child.tag-name.to-lower-case!
        attrs: {}
        children: walk-children(child.child-nodes)
      for i in [0 til child.attributes.length]
        el.attrs[child.attributes.item(i).name] = child.attributes.item(i).value
      collection.push el
    else if child.node-type is 3
      collection.push child.node-value
  collection

m.convert = (markup) ->
  walk-children (q markup)

# FRP
require! \kefir
window.s = ^^kefir
s.from-child-events = (target, query, event-name, transform = id) ->
  propagate = false
  if last(event-name) is \!
    event-name = event-name.substr(0, event-name.length - 1)
    propagate = true
  s.stream (emitter) ->
    handler = ->
      if !propagate
        it.stop-propagation!
        it.prevent-default!
      emitter.emit transform it
    q target .on event-name, query, handler
    -> q target .off event-name, query, handler

# Session
require! 'socket.io-client': socket-io
require! \rivulet
require! \wire
if config.env
  socket = socket-io "http://session.#{config.env}.copsforhire.com"
else
  socket = socket-io!
# window.$session = window.session = rivulet socket, \session

socket.on \session-validation, ->
  warn \Validation, it.0, '\n', JSON.stringify(it.1, null, 2)

if session-cache = session-storage.get-item(\session)
  session-cache = JSON.parse session-cache
window.session = {}
# if window.session
#   window.session = JSON.parse window.session
# else
#   window.session = {}

session-wire = wire socket: socket, channel: \session, logger: (...args) ->
  if is-object(last args) or is-array(last args)
    obj = args.pop!
    args.push JSON.stringify obj
  info ...args
session-watchers = {}
session-wire.observe-all (path, value) ->
  if path is \id and value
    window.session = session-cache
  $set path, value
  session-storage.set-item \session, JSON.stringify(session)

global.$set = (path, value) ->
  old-value = object-path.get session, (camelize path)
  if value != old-value
    object-path.set session, (camelize path), value
    for fn in (session-watchers[path] or [])
      fn value, old-value
global.$sset = (path, value) ->
  $set path, value
  session-wire.send path, value
global.$send = (path, value) ->
  session-wire.send path, value
global.$watch = (paths, fn) ->
  if is-array paths
    for path in paths
      path = camelize path
      session-watchers[path] ?= []
      session-watchers[path].push (value, old-value) -> fn path, value, old-value
  else
    path = camelize paths
    session-watchers[path] ?= []
    session-watchers[path].push fn
global.$get = (path) ->
  object-path.get session, (camelize path)
global.$del = (path) ->
  object-path.del session, (camelize path)
window.$storage = rivulet socket, \storage
$storage.logger = (...args) ->
  if is-object(last args) or is-array(last args)
    obj = args.pop!
    args.push JSON.stringify obj
  info ...args

$send \id, (session-cache.id or '00000000-0000-0000-0000-000000000000') #session-storage.get-item \id
# else
#   session.send \noId, true
# else
#   session.set \id, \nobody
# $watch \id, (id) ->
#   session-storage.set-item \id, id if id
  # if not (session.get \id)
  #   return session.set \noId, true
  # # return if (session.get \id) is \nobody
  # session-storage.set-item \id, session.get \id

window.destroy-session = ->
  session-storage.remove-item \id
  session.del \persistent
  session.del \id
  for key of session!
    session.del key

# History
window.history = require \html5-history-api
current-route = ->
  /http(s)?\:\/\/[^\/]+\/([^\?\#]*)/.exec(history.location or window.location).2.replace(/\//g, '-')
window.go = ->
  if (it == '' or it) and current-route! != it
    info "Routing to: '#it'"
    history.push-state null, null, "/#{it.replace(/\-/g, '/')}"
# window.route = ->
#   session.root.set \route, it
# q window .on \load, ->
#   if !(session.get \route) and !(session.get \id)
#     session.set \route, current-route!
q window .on \popstate, ->
  session.set \route, current-route!
$watch \route, (route) ->
  go route

# Disable all form submits
q document.body .on \submit, \form, false

register-component = (name, component) ->
  return if name not in <[ cfh-root cfh-login cfh-signup cfh-address-input ]>
  prototype = Object.create HTMLElement.prototype
  prototype.initialize = ->
    return if @initialized
    @initialized = true
    local = {}
    @set = (path, value) ->
      object-path.set local, (camelize path), value
    @get = (path)    ->
      object-path.get local, (camelize path)
    @del = (path)    ->
      object-path.del local, (camelize path)
    # @$on-values = []
    @q = q this
    @find = ~> @q.find it
    @attr = ~> @q.attr it
    # @merge = -> session.merge it
    # @revise = ->
    #   warn '#{@tag-name}: @revise is deprecated, use $set'
    #   session it
    @render = ~>
      data = (extend-new session, local)
      info \Rendering, @tag-name, data
      # warn "#{@tag-name}: @dummy is deprecated.  Set @local in @start instead." if @dummy
      # locals = q.extend true, @dummy!, session!
      # locals = q.extend true, locals, @local
      # locals = q.extend true, locals, locals.trim
      tree = m.convert @view data
      m.render this, tree
      # @paint!
    @start!
    # stream = s.merge (@watch |> map (path) -> (session.observe path).map -> (path): session.get(path))
    # @$on-values.push [ stream, ~>
    #   @react session!, it
    #   @render!
    # ]
    # stream.on-value (last @$on-values).1
    # @watch = (obj, path, fn) ~>
    #   if &.length < 3
    #     fn = path
    #     path = obj
    #     obj = session
    #   if fn
    #     stream = (session.observe path).map -> session.get(path)
    #     @$on-values.push [ stream, fn ]
    #     stream.on-value (last @$on-values).1
    #   else
    #     stream = (session.observe path).map -> (path): session.get(path)
    #     @$on-values.push [ stream, ~>
    #       @react session!, it
    #       @render!
    #     ]
    #     stream.on-value (last @$on-values).1
    # obj-to-pairs @apply! |> each ([k, val]) ~>
    #   if not is-array val
    #     val = [ val ]
    #   for v in val
    #     @$on-values.push [ v, ~>
    #       if k is \react
    #         @react session!, it
    #       else
    #         session.set (camelize k), it
    #     ]
    #     v.on-value (last @$on-values).1
    # for key in keys @latch
    #   @q.on key, @latch[key] # kids!
    # @apply = (obj, k, v) ~>
    #   if &.length < 3
    #     v = k
    #     k = obj
    #     obj = session
    #   @$on-values.push [ v, ~>
    #     if obj is session
    #       session.set (camelize k), it
    #     else
    #       @set (camelize k), it
    #     @render!# if obj is @local
    #   ]
    #   v.on-value (last @$on-values).1
    # @reactx = (stream, fn) ->
    #   @$on-values.push [ stream, ~>
    #     fn it
    #   ]
    #   v.on-value (last @$on-values).1
  prototype.attached-callback = ->
    log \ATTACHED, @tag-name
    @initialize!
    @render!
    @ready!
    # @paint!
  # prototype.detached-callback = ->
  #   for on-value in @$on-values
  #     on-value.0.off-value on-value.1
  prototype.attribute-changed-callback = (name, old-value, new-value) ->
    # return if an is \id
    @initialize!
    @q.trigger 'attribute', [ name, new-value, old-value ]
    # @trait an, o, n
    # @render!

  prototype <<< do
    on: (name, query, options, fn) ->
      if is-object query
        options = query
        query = null
      if is-function query
        options = call: query
        query = null
      if is-function options
        options = call: options
      if fn
        options.call = fn
      fn = (event, data) ~>
        value = null
        if options.value
          value = options.value
        if options.extract is \value
          value = q(event.target).val!
        if options.extract is \truth
          value = q(event.target).prop \checked
        if data
          value = data
          if options.extract
            value = object-path.get value, (camelize options.extract)
        info name.to-upper-case!, (query or @tag-name.to-lower-case!), options, value
        if options.set-local
          @set options.set-local, value
        if options.set-session
          $set options.set-session, value
        if options.send-local
          @send options.send-local
        if options.call
          options.call value
        if options.render
          @render!
      if query
        @q.on name, query, fn
      else
        @q.on name, fn
    # click:  (query, fn) -> @q.on \click,  query, fn
    # change: (query, fn) -> @q.on \change, query, -> fn it.current-target.value
    # apply:  (query, path) -> @q.on \change, query, ~> @set path, it.current-target.value
    # on:              (query, event-name, fn) -> @q.on event-name, query, fn
    # event:           (query, name, transform) -> s.from-child-events this, query, name, transform
    # event-value:     (query, name) -> s.from-child-events this, query, name, -> q it.target .val!
    # value-on-change: (query) -> s.from-child-events this, query, \change, -> q it.target .val!
    # truth-on-click:  (query) -> s.from-child-events this, query, \click, ->
    #   return (q event.target .prop \checked) if event.target.type in <[ checkbox radio ]>
    #   true
    # action-on-click: (query, action) ->
    #   if this[camelize action]
    #     s.from-child-events this, query, \click, ~> this[camelize action] session!, it.current-target
    #   else
    #     s.from-child-events this, query, \click, -> action
    # action-on-event: (query, name, action) ->
    #   if this[camelize action]
    #     s.from-child-events this, query, name, ~> this[camelize action] session!, it.current-target
    #   else
    #     s.from-child-events this, query, name, -> action
    send: (path, value) ->
      $send path, @get path
    # watch: []
    # dummy: -> {}
    start: ->
    # apply: -> {}
    # react: ->
    # paint: ->
    ready: ->
    # trait: ->
    # latch: {}
  prototype <<< component
  document.register-element name, prototype: prototype
