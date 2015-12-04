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

proxify-base = (state, target, mutation) ->
  target.$state = state
  target.$mutation = mutation if mutation
  proxy = new Proxy target,
    own-keys: (target) ->
      keys target.$state
    enumerate: (target) ->
      keys(target.$state)[Symbol.iterator]!
    # has: (target, key) ->
    #   info \HAS
    #   ``key in target``
    # has-own: (target, key) ->
    #   info \HAS-OWN
    #   target.has-own-property key
    get: (target, key) ->
      if key is \$target
        target
      else if key.0 is \$ or key is \inspect
        target[key]
      else
        target.$state[key]
    set: (target, key, val) ->
      if key is \$state
        for k, v of val
          val[k] = proxify v, target.$mutation
          if target.$mutation and (typeof! v is \Object or typeof! v is \Array)
            val[k].$mutation = target.$mutation
        target.$state = val
      if key is \$mutation
        target.$mutation = val
        for k, v of target.$state
          switch typeof! v
          | \Object => v.$mutation = val
          | \Array  => v.$mutation = val
      else if key.0 is \$
        target[key] = val
      else
        val = val.$get! if val?$get
        target.$state[key] = proxify val, target.$mutation
        target.$mutation?!
    delete-property: (target, key) ->
      if key.0 is \$
        delete target[key]
      else
        delete target.$state[key]
        target.$mutation?!
      true
  target.$set-mutation = ->
    target.$mutation = it
  target.inspect = (depth, opts) -> util.inspect target.$state, opts <<< depth: depth
  proxy

proxify-object = (state, mutation) ->
  for key, val of state
    state[key] = proxify val
  target ?= {}
  proxy = proxify-base state, target, mutation
  target.$get = ->
    obj = {}
    for key, val of target.$state
      if val?$get
        obj[key] = val.$get!
      else
        obj[key] = val
    obj
  proxy

proxify-array = (state, mutation) ->
  for val, i in state
    state[i] = proxify val, mutation
  target = []
  proxy = proxify-base state, target, mutation
  target.$get = ->
    arr = []
    for val, i in target.$state
      if val?$get
        arr[i] = val.$get!
      else
        arr[i] = val
    arr
  proxy

proxify = (state, mutation) ->
  switch typeof! state
  | \Object   => proxify-object state, mutation
  | \Array    => proxify-array state, mutation
  | otherwise => state

module.exports = (state = {}, socket, channel) ->
  rivulet = proxify state
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
      if emit-to-socket
        diff = patch.compare(rivulet.$old-state, rivulet.$new-state)
        rivulet.$socket-emit-queue.push diff
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
              extraction-cache[path] = undefined
            catch
              extraction-cache[path] = new-extract
      rivulet.$old-state = rivulet.$get!
      for path, observer of observers
        if extraction-cache[path] is not undefined
          observer.emitter.emit extraction-cache[path]
    $socket-emit-queue: []
    $old-state: rivulet.$get!
  rivulet.$set-mutation ->
    rivulet.$new-state = rivulet.$get!
    rivulet.$broadcast!
  observers = {}
  if socket and channel
    rivulet.$socket = socket
    rivulet.$socket.on channel, (diff) ->
      rivulet.$logger 'Rivulet received', diff if rivulet.$logger
      state = rivulet.$get!
      patch.apply state, diff
      rivulet.$state = state
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
