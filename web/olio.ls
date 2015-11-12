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

# Templates
require 'webcomponents.js'
window.jade = require 'jade/runtime'
m = require 'mithril'
m.convert = require \template-converter

# FRP
require! \kefir
window.s = ^^kefir
s.from-child-events = (target, query, event-name, transform = id) ->
  s.stream (emitter) ->
    handler = -> emitter.emit transform it
    q target .on event-name, query, handler
    -> q target .off event-name, query, handler

# Session
require! 'socket.io-client': socket-io
require! 'fast-json-patch/dist/json-patch-duplex.min': patch
require! 'baobab'
socket = socket-io!
window.$session = session = new baobab
receive-count = 0
receive-last = []
socket.on \session, ->
  new-session = session.serialize!
  patch.apply new-session, it
  receive-last := it |> map -> JSON.stringify it
  session.deep-merge new-session
  # Load the session only after we have received the initial stuff
  if not receive-count
    if id = session-storage.get-item \id
      session.set \id, id
  receive-count := receive-count + 1
  info \SESSION, receive-count, session.get!

session.root.start-recording 1
session.root.on \update, ->
  # Don't send session changes that were just received from server
  diff = patch.compare session.root.get-history!0, session.root.get!
  |> filter -> JSON.stringify(it) not in receive-last
  receive-last := []
  if diff.length
    info \EMIT, diff
    socket.emit \session, diff if diff.length
session.select \id
.on \update, ->
  return if not it.data.current-data
  session-storage.set-item \id, it.data.current-data

window.session = (path) ->
  map =
    cursor: session.select path.split \.
    stream: s.stream (emitter) ->
      if val = session.get path.split \.
        emitter.emit val
      # This isn't right, fix it (properly create/dispose)
      map.cursor.on \update, ->
        emitter.emit map.cursor.get!
      ->

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
  session.set \route, current-route!
q window .on \popstate, ->
  session.set \route, current-route!
session.select \route
.on \update, ->
  go session.root.get \route

# Disable all form submits
q document.body .on \submit, \form, false

register-component = (name, component) ->
  prototype = Object.create HTMLElement.prototype
  self = null
  prototype.merge = (what) ->
    what ?= state
    render = false
    for key, cursor of cursors
      if what[key]?
        cursor = cursor.up!
        object = { (key): what[key] }
        if cursor.get! is void
          cursor.set {}
        if (diff = patch.compare cursor.serialize!{(key)}, object).length
          render = true
          info \DIFF, @tag-name, cursor.serialize!{(key)}, object
        cursor.deep-merge object
    if render
      m.render this, (eval m.convert @view state)
  prototype.attached-callback = ->
    state = @start!
    cursors = {}
    info \RENDERING, @tag-name, state
    m.render this, (eval m.convert @view state)
    # Watchers
    @$watchers = @watch!
    wkeys = keys @$watchers
    wvals = values @$watchers
    [0 til wkeys.length] |> each (i) ->
      cursors[wkeys[i]] = wvals[i].cursor
      wvals[i] = wvals[i].stream.map -> (wkeys[i]): it
    @merge!
    @$watch-on-value = ~>
      old-state = {} <<< state
      state <<< it
      if (patch.compare old-state, state).length
        info \RE-RENDERING, @tag-name, state
        m.render this, (eval m.convert @view state)
        @react state, it
    @$watch-merge = s.merge wvals
    @$watch-merge.on-value @$watch-on-value
    # Appliers
    appliers = @apply state
    akeys = keys appliers
    avals = values appliers
    [0 til akeys.length] |> each (i) ~>
      akey = akeys[i].split \.
      if typeof! avals[i] != \Array
        avals[i] = [ avals[i] ]
      avals[i] |> each (aval) ~>
        if akey.0 is \react
          aval.on-value ~>
            @react state, it
        else
          aval.on-value ~>
            info \VALUE, it
            if cursor = cursors[head akey]
              cursor.set (tail akey), it
            else
              session.root.set akey, it
    @ready!
  prototype.detached-callback = ->
    info \DETACHED, @tag-name
    @$watch-merge.off-value @$watch-on-value
  prototype.map = (path, func) ->
    @$watchers[path].stream.map -> info \FIRING; func it

  prototype <<< do
    event: (query, name, transform) -> s.from-child-events this, query, name, transform
    event-value: (query, name) -> s.from-child-events this, query, name, -> q it.target .val!
    ready: ->
    watch: -> {}
    apply: -> null
    react: -> null
    start: -> {}
  prototype <<< component
  document.register-element name, prototype: prototype
