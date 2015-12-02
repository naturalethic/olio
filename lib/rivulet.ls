require! \kefir
require! \fast-json-patch : \patch
require! \object-path : objectpath
require! \JSONPath : jsonpath
require! \assert
require! \util

json-extract = ($, path) ->
  if path = (jsonpath json: $, path: path, result-type: \path)?0
    eval path
  else
    null

proxify-base = (state, target, before-mutation, after-mutation) ->
  proxy = new Proxy target,
    own-keys: (target) ->
      keys state
    enumerate: (target) ->
      keys(state)[Symbol.iterator]!
    get: (target, key) ->
      if key.0 is \$ or key is \inspect
        target[key]
      else
        state[key]
    set: (target, key, val) ->
      if key.0 is \$
        target[key] = val
      else
        before-mutation!
        val = val.$get! if val?$get
        state[key] = proxify val, before-mutation, after-mutation
        after-mutation!
    delete-property: (target, key) ->
      if key.0 is \$
        delete target[key]
      else
        before-mutation!
        delete state[key]
        after-mutation!
      true
  target.inspect = (depth, opts) -> util.inspect state, opts <<< depth: depth
  proxy

proxify-object = (state, before-mutation, after-mutation) ->
  for key, val of state
    state[key] = proxify val, before-mutation, after-mutation
  target = {}
  proxy = proxify-base state, target, before-mutation, after-mutation
  target.$get = ->
    obj = {}
    for key, val of state
      if val?$get
        obj[key] = val.$get!
      else
        obj[key] = val
    obj
  proxy

proxify-array = (state, before-mutation, after-mutation) ->
  for val, i in state
    state[i] = proxify val, before-mutation, after-mutation
  target = []
  proxy = proxify-base state, target, before-mutation, after-mutation
  target.$get = ->
    arr = []
    for val, i in state
      if val?$get
        arr[i] = val.$get!
      else
        arr[i] = val
    arr
  proxy

proxify = (target = undefined, before-mutation = ->, after-mutation = ->) ->
  switch typeof! target
  | \Object   => proxify-object target, before-mutation, after-mutation
  | \Array    => proxify-array target, before-mutation, after-mutation
  | otherwise => target

module.exports = (state = {}, socket, channel) ->
  rivulet = new Proxy {},
    enumerate: (target) ->
      keys(rivulet.$state)[Symbol.iterator]!
    own-keys: (target) ->
      keys rivulet.$state
    get: (target, key) ->
      if key.0 is \$
        target[key]
      else
        rivulet.$state[key]
    set: (target, key, val) ->
      if key.0 is \$
        target[key] = val
      else
        rivulet.$state[key] = val
    delete-property: (target, key) ->
      if key.0 is \$
        delete target[key]
      else
        delete rivulet.$state[key]
      true
  rivulet <<<
    $logger: null
    $observe: (path, func) ->
      path = camelize path
      if not observers[path]
        observers[path] = {}
        observers[path].stream = kefir.stream -> observers[path].emitter = it
      if func
        observers[path].stream
        .on-value func
      observers[path].stream
    $forget: (path, func) ->
      path = camelize path
      observers[path].stream.off-value func
    $broadcast: (emit-to-socket = true) ->
      rivulet.$socket-emit-queue.push patch.compare(rivulet.$old-state, rivulet.$new-state) if emit-to-socket
      extraction-cache = {}
      for path, observer of observers
        if not extraction-cache[path]?
          if path == \$
            extraction-cache[path] = rivulet.$new-state
          else
            old-extract = json-extract rivulet.$old-state, path
            new-extract = json-extract rivulet.$new-state, path
            try
              assert.deep-equal old-extract, new-extract
              extraction-cache[path] = false
            catch
              extraction-cache[path] = new-extract
        if extraction-cache[path]
          observer.emitter.emit extraction-cache[path]
    $before-mutation: ->
      rivulet.$old-state = rivulet.$get!
    $after-mutation: ->
      rivulet.$new-state = rivulet.$get!
      rivulet.$broadcast!
    $get: -> rivulet.$state.$get!
    $state: proxify state, rivulet.$before-mutation, rivulet.$after-mutation
    $socket-emit-queue: []
  observers = {}
  if socket and channel
    rivulet.$socket = socket
    rivulet.$socket.on channel, (diff) ->
      rivulet.$logger 'Rivulet received', diff if rivulet.$logger
      # XXX: Warning -- if we swap out the state here, it could cause some who may have claimed a reference to have an orphaned one
      #      This is probably ok, even handy.
      rivulet.$old-state = rivulet.$get!
      state = rivulet.$get!
      patch.apply state, diff
      rivulet.$state = proxify state, rivulet.$before-mutation, rivulet.$after-mutation
      rivulet.$new-state = rivulet.$get!
      rivulet.$broadcast false
    emit-stream = rivulet.$observe '$'
    emit-stream.on-value debounce 1, ->
      return if empty rivulet.$socket-emit-queue
      diff = flatten rivulet.$socket-emit-queue
      rivulet.$logger 'Rivulet sending', diff if rivulet.$logger
      socket.emit channel, diff
      rivulet.$socket-emit-queue = []
  rivulet


