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

# History
window.history = require \html5-history-api
window.route = s.stream (emitter) ->
  q window .on \load, ->
    emitter.emit route: route.current!
  q window .on \popstate, ->
    emitter.emit route: route.current!
route.current = ->
  /http(s)?\:\/\/[^\/]+\/(\#\/)?(.*)/.exec(history.location or window.location).3.replace(/\//g, '-')
route.go = ->
  history.push-state null, null, "#/#{it.replace(/\-/g, '/')}"

# Session
require! 'socket.io-client': socket-io
require! 'fast-json-patch/dist/json-patch-duplex.min': patch
socket = socket-io!
session = {}
session-observer = patch.observe session
socket.on \session, ->
  info \SESSION, session
  patch.apply session, it
  patch.generate session-observer
  if session-emitter
    session-emitter.emit session: session
session-emitter = null
window.session = s.stream (emitter) ->
  session-emitter := emitter
  ->
    session-emitter := null
session-extend = ->
  return false if not it
  extend session, it
  patches = patch.generate session-observer
  info \FLUSH, JSON.stringify patches
  socket.emit \session, patches
  true

register-component = (name, component) ->
  prototype = Object.create HTMLElement.prototype
  prototype.attached-callback = ->
    @state = @start!
    state-extend = ~>
      return false if not it
      extend @state, it
      true
    info \RENDERING, this.tag-name, @state
    m.render this, (eval m.convert @view @state)
    s.merge @watch!
    .on-value ~>
      info \ACT, it
      if not it.session
        session-extend @apply it
      if state-extend @react it
        info \RENDERING, this.tag-name, @state
        m.render this, (eval m.convert @view @state)
    @ready!
  prototype <<< do
    ready: ->
    start: -> {}
    watch: -> []
    apply: -> null
    react: -> null
  prototype <<< component
  document.register-element name, prototype: prototype
