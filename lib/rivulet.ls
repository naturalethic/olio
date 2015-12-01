require! \kefir
require! \fast-json-patch : \patch
require! \object-path : objectpath
require! \JSONPath : jsonpath
require! \assert

proxify-object = (target) ->
  for key, val of target
    target[key] = proxify val
  new Proxy target,
    get: (_, key) ->
      target[key]
    set: (_, key, val) ->
      target[key] = proxify val

proxify-array = (target) ->
  for val, i in target
    target[i] = proxify val
  proxy = new Proxy target,
    get: (_, key) ->
      target[key]
    set: (_, key, val) ->
      target[key] = proxify val
  proxy

proxify = (target = {}) ->
  switch typeof! target
  | \Object   => proxify-object target
  | \Array    => proxify-array target
  | otherwise => target

module.exports = (state = {}, socket, channel) ->
  state = proxify state
  observers = {}
  emit-queue = []
  rivulet = new Proxy null,
    get: (_, key) ->
      state[key]
    set: (_, key, val) ->
      state[key] = val
  rivulet <<<
    $logger: null
    $observe: (path, func) ->
      if not observers[path]
        observers[path] = {}
        observers[path].stream = kefir.stream -> observers[path].emitter = it
      if func
        observers[path].stream
        .on-value func
      observers[path].stream
    $forget: (path, func) ->
      observers[path].stream.off-value func
    $patch: (diff, emit = true) ->
      return if not diff.length
      emit-queue.push diff if emit
      old-state = rivulet!
      patch.apply state, diff
      extraction-cache = {}
      for path, observer of observers
        if not extraction-cache[path]?
          if path == \$
            extraction-cache[path] = rivulet!
          else
            old-extract = json-extract old-state, path
            new-extract = json-extract state, path
            try
              assert.deep-equal old-extract, new-extract
              extraction-cache[path] = false
            catch
              extraction-cache[path] = new-extract
        if extraction-cache[path]
          observer.emitter.emit extraction-cache[path]
  if socket and channel
    rivulet.$socket = socket
    rivulet.$socket.on channel, ->
      rivulet.$logger 'Rivulet received', it if rivulet.$logger
      rivulet.$patch it, false
    emit-stream = rivulet.$observe '$'
    emit-stream.on-value ->
      while diff = emit-queue.pop!
        rivulet.$logger 'Rivulet sending', diff if rivulet.$logger
        socket.emit channel, diff
  rivulet


