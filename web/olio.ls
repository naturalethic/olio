window.global = window
window.q = window.$ = window.jQuery = require 'jquery'

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
    @local.content = @innerHTML
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
      html = @view @local
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
          value = data.0 if data.length == 1
          if options.extract
            value = object-path.get data.0, (camelize options.extract)
        value ?= event
        if options.as
          value = switch options.as
          | \number => Number value
        info name.to-upper-case!, (query or @tag-name.to-lower-case!), options, value
        options.set    and @set options.set-local, value
        options.call   and (if is-array value then options.call ...value else options.call value)
        options.render and @render!
      if query
        @q.on name, query, fn
      else
        @q.on name, fn
    start: ->
    ready: ->
  prototype <<< component
  document.register-element name, prototype: prototype
