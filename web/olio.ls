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
if config.env
  socket = socket-io "http://session.#{config.env}.copsforhire.com"
else
  socket = socket-io!
window.$session = session = rivulet socket, \session
window.$storage = rivulet socket, \storage
session.logger = (...args) ->
  if is-object(last args) or is-array(last args)
    obj = args.pop!
  args.push JSON.stringify obj
  info ...args
$storage.logger = (...args) ->
  if is-object(last args) or is-array(last args)
    obj = args.pop!
  args.push JSON.stringify obj
  info ...args

if id = session-storage.get-item \id
  session.set \id, id
else
  session.set \noId, true
# else
#   session.set \id, \nobody
session.observe \id, ->
  if not (session.get \id)
    return session.set \noId, true
  # return if (session.get \id) is \nobody
  session-storage.set-item \id, session.get \id

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
q window .on \load, ->
  if !(session.get \route) and !(session.get \id)
    session.set \route, current-route!
q window .on \popstate, ->
  session.set \route, current-route!
session.observe \route, ->
  go session.get \route

# Disable all form submits
q document.body .on \submit, \form, false

register-component = (name, component) ->
  prototype = Object.create HTMLElement.prototype
  prototype.initialize = ->
    return if @initialized
    @initialized = true
    @local = {}
    @$on-values = []
    @q = q this
    @find = ~> @q.find it
    @merge = -> session.merge it
    @revise = -> session it
    @render = ~>
      info \Rendering, @tag-name
      locals = q.extend true, @dummy!, session!
      locals = q.extend true, locals, @local
      locals = q.extend true, locals, locals.trim
      tree = m.convert @view locals
      # info \NEW, JSON.stringify(new-code, null, 2)
      # code = m.old-convert @view locals
      # info \OLD, JSON.stringify((eval code), null, 2)
      # return if code == '[)]'
      m.render this, tree
      @paint session!
    if @start
      warn "START no longer merges its return value, update '#{@tag-name}' to use $session.set instead."
      @start!
    stream = s.merge (@watch |> map (path) -> (session.observe path).map -> (path): session.get(path))
    @$on-values.push [ stream, ~>
      @react session!, it
      @render!
    ]
    stream.on-value (last @$on-values).1
    @watch = (path, fn) ~>
      if fn
        stream = (session.observe path).map -> session.get(path)
        @$on-values.push [ stream, fn ]
        stream.on-value (last @$on-values).1
      else
        stream = (session.observe path).map -> (path): session.get(path)
        @$on-values.push [ stream, ~>
          @react session!, it
          @render!
        ]
        stream.on-value (last @$on-values).1
    obj-to-pairs @apply! |> each ([k, val]) ~>
      if not is-array val
        val = [ val ]
      for v in val
        @$on-values.push [ v, ~>
          if k is \react
            @react session!, it
          else
            session.set (camelize k), it
        ]
        v.on-value (last @$on-values).1
    for key in keys @latch
      @q.on key, @latch[key] # kids!
  prototype.attached-callback = ->
    @initialize!
    @render!
    @ready session!
    @paint session!
  prototype.detached-callback = ->
    for on-value in @$on-values
      on-value.0.off-value on-value.1
  prototype.attribute-changed-callback = (an, o, n) ->
    return if an is \id
    @initialize!
    @trait an, o, n
    @render!

  prototype <<< do
    event:           (query, name, transform) -> s.from-child-events this, query, name, transform
    event-value:     (query, name) -> s.from-child-events this, query, name, -> q it.target .val!
    value-on-change: (query) -> s.from-child-events this, query, \change, -> q it.target .val!
    truth-on-click:  (query) -> s.from-child-events this, query, \click, ->
      return (q event.target .prop \checked) if event.target.type in <[ checkbox radio ]>
      true
    action-on-click: (query, action) ->
      if this[camelize action]
        s.from-child-events this, query, \click, ~> this[camelize action] session!, it.current-target
      else
        s.from-child-events this, query, \click, -> action
    action-on-event: (query, name, action) ->
      if this[camelize action]
        s.from-child-events this, query, name, ~> this[camelize action] session!, it.current-target
      else
        s.from-child-events this, query, name, -> action
    watch: []
    dummy: -> {}
    start: null
    apply: -> {}
    react: ->
    paint: ->
    ready: ->
    trait: ->
    latch: {}
  prototype <<< component
  document.register-element name, prototype: prototype
