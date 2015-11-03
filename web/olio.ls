window.global = window
window.q = require \jquery
window.merge  = require \deepmerge
window.extend = q.extend

require './index.css'
window <<< require 'prelude-ls'
require \livescript-utilities
if console.log.apply
  <[ log info warn error ]> |> each (key) -> window[key] = -> console[key] ...&
else
  <[ log info warn error ]> |> each (key) -> window[key] = console[key]

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
# session = {}
# session-observer = patch.observe session
session = new baobab
socket.on \session, ->
  info \PATCH, it
  new-session = session.serialize!
  patch.apply new-session, it
  session.deep-merge new-session
  info \SESSION, session.get!
  # if typeof! it == \Object
  #   # init
  #   info \SESSION-INIT, it
  #   session :=
  # else
  #   # patch
  #   info \SESSION-PATCH, it
  #   patch.apply session, it
  #   patch.generate session-observer
  #   if session-emitter
  #     session-emitter.emit session: session
session.root.start-recording 1
session.root.on \update, ->
  diff = patch.compare session.root.get-history!0, session.root.get!
  info diff
  socket.emit \session, diff if diff.length

# window.session = (path) ->
#   map =
#     cursor: null
#     stream: s.stream (emitter) ->
#       if val = session.get path.split \.
#         emitter.emit val
#       map.cursor = session.select path.split \.
#       map.cursor.on \update, ->
#         emitter.emit map.cursor.get!
#       -> map.cursor.release!; delete map.cursor

window.session = (path) ->
  map =
    cursor: session.select path.split \.
    stream: s.stream (emitter) ->
      if val = session.get path.split \.
        emitter.emit val
      # This isn't right, fix it (properly create/dispose)
      map.cursor.on \update, ->
        emitter.emit map.cursor.get!
      -> map.cursor.release!; delete map.cursor

# window.ses = ->
#   "SES_#it"
# session-emitter = null
# window.session = s.stream (emitter) ->
#   session-emitter := emitter
#   ->
#     session-emitter := null
# session-extend = ->
#   return false if not it
#   extend session, it
#   patches = patch.generate session-observer
#   info \FLUSH, JSON.stringify patches
#   socket.emit \session, patches
#   true

# History
window.history = require \html5-history-api
current-route = ->
  /http(s)?\:\/\/[^\/]+\/([^\?\#]*)/.exec(history.location or window.location).2.replace(/\//g, '-')
window.go = ->
  # history.push-state null, null, "#/#{it.replace(/\-/g, '/')}"
  history.push-state null, null, "#{it.replace(/\-/g, '/')}"
q window .on \load, ->
  info current-route!
  session.set \route, current-route!
  # emitter.emit route: route.current!
q window .on \popstate, ->
  info current-route!
  session.set \route, current-route!
session.select \route
.on \update, ->
  go session.root.get \route
# window.route = s.stream (emitter) ->
#   q window .on \load, ->
#     info route.current!
#     session.set \route, route.current!
#     # emitter.emit route: route.current!
#   q window .on \popstate, ->
#     info route.current!
#     session.set \route, route.current!
#     # emitter.emit route: route.current!


register-component = (name, component) ->
  prototype = Object.create HTMLElement.prototype
  self = null
  prototype.attached-callback = ->
    # @state = @start!
    # state-extend = ~>
    #   return false if not it
    #   extend @state, it
    #   true
    state = {}
    cursors = {}
    info \RENDERING, this.tag-name, state
    # m.render this, (eval m.convert @view @state)
    m.render this, (eval m.convert @view state)
    appliers = @apply!
    akeys = keys appliers
    avals = values appliers
    [0 til akeys.length] |> each (i) ->
      akey = akeys[i].split \.
      avals[i].on-value ~>
        if cursor = cursors[head akey]
          cursor.set (tail akey), it
        else
          session.root.set akey, it
    watchers = @watch!
    wkeys = keys watchers
    wvals = values watchers
    [0 til wkeys.length] |> each (i) ->
      cursors[wkeys[i]] = wvals[i].cursor
      wvals[i] = wvals[i].stream.map -> (wkeys[i]): it
    s.merge wvals
    .on-value ~>
      info \ACT, it
      state <<< it
    #   # if not it.session
    #   #   session-extend @apply it
    #   if state-extend @react it
      info \RENDERING, this.tag-name, state
      m.render this, (eval m.convert @view state)
    @ready!
  prototype <<< do
    event: (query, name, transform) -> s.from-child-events this, query, name, transform
    ready: ->
    start: -> {}
    watch: -> {}
    apply: -> null
    react: -> null
  prototype <<< component
  document.register-element name, prototype: prototype
