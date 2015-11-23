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
require! \rivulet
socket = socket-io!
window.$session = session = rivulet socket, \session
session.logger = (...args) ->
  if is-object(last args) or is-array(last args)
    obj = args.pop!
  args.push JSON.stringify obj
  info ...args

if id = session-storage.get-item \id
  session.set \id, id
session.observe \id, ->
  # info \OBSERVE-ID, session.get \id
  # return if !it.data.current-data or it.data.current-data is \destroy
  # info \SETTING-SESSION-STORAGE
  # session-storage.set-item \id, it.data.current-data

# window.destroy-session = ->
#   session-storage.remove-item \id
#   session.set \id, \destroy

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
session.observe \route, ->
  go session.get \route

# Disable all form submits
q document.body .on \submit, \form, false

register-component = (name, component) ->
  prototype = Object.create HTMLElement.prototype
  prototype.attached-callback = ->
    @q = q this
    @find = ~> @q.find it
    @merge = -> session.merge it
    @revise = -> session it
    render = ~>
      m.render this, (eval m.convert @view (@dummy! <<< session!))
    session(session! <<< @start!)
    s.merge (@watch |> map (path) -> (session.observe path).map -> (path): session.get(path))
    .on-value ~>
      @react session!, it
      info \Re-rendering, @tag-name
      render!
      @paint session!
    info \Rendering, @tag-name
    render!
    @paint session!
    obj-to-pairs @apply! |> each ([k, val]) ~>
      if not is-array val
        val = [ val ]
      for v in val
        v.on-value ~>
          if k is \react
            @react session!, it
          else
            session.set (camelize k), it
    @ready session!
  prototype.detached-callback = ->
    info \DETACHED, @tag-name
    # XXX: TODO: off-value any of the above on-values

  prototype <<< do
    event:           (query, name, transform) -> s.from-child-events this, query, name, transform
    event-value:     (query, name) -> s.from-child-events this, query, name, -> q it.target .val!
    value-on-change: (query) -> s.from-child-events this, query, \change, -> q it.target .val!
    truth-on-click:  (query) -> s.from-child-events this, query, \click, ->
      return (q event.target .prop \checked) if event.target.type in <[ checkbox radio ]>
      true
    action-on-click: (query, action) -> s.from-child-events this, query, \click, -> action
    watch: []
    dummy: -> {}
    start: -> {}
    apply: -> {}
    react: ->
    paint: ->
    ready: ->
  prototype <<< component
  document.register-element name, prototype: prototype
