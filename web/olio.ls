require './index.css'
window <<< require 'prelude-ls'
require 'livescript-utilities'
if console.log.apply
  <[ log info warn error ]> |> each (key) -> window[key] = -> console[key] ...&
else
  <[ log info warn error ]> |> each (key) -> window[key] = console[key]
window.q = require 'jquery'

# Templates
require 'webcomponents.js'
jade = require 'jade/runtime'
m = require 'mithril'
m.convert = require 'template-converter'

# FRP
kefir = require 'kefir'
window.s = ^^kefir
s.from-child-events = (target, event-name, query, transform = id) ->
  s.stream (emitter) ->
    handler = -> emitter.emit transform it
    q target .on event-name, query, handler
    -> q target .off event-name, query, handler

# History
window.history = require 'html5-history-api'
window.current-route = ->
  /http(s)?\:\/\/[^\/]+\/(\#\/)?(.*)/.exec(history.location or window.location).3.replace(/\//g, '-')
window.route-to = ->
  history.push-state null, null, "#/#{it.replace(/\-/g, '/')}"
q window .on 'load', ->
  q window .trigger q.Event 'route', route: current-route!
q window .on 'popstate', ->
  q window .trigger q.Event 'route', route: current-route!

register-component = (name, component) ->
  info name, component
  prototype = Object.create HTMLElement.prototype
  prototype.attached-callback = ->
    info \ATTACHED
    m.render this, (eval m.convert @view @start!)
    s.merge @intent!
    .map ~>
      info 'INTENT', it
      @model it
    .on-value ~>
      info 'MODEL', it
      m.render this, (eval m.convert @view it)
    @ready!
  prototype <<< do
    ready: ->
    start: -> {}
    intent: -> {}
    model: s.constant {}
  prototype <<< component
  document.register-element name, prototype: prototype
