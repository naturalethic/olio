require! \kefir
require! \fast-json-patch : \patch
# require! \object-path
# require! \deep-extend
# require! \jspath
require! \JSONPath : jsonpath
require! \assert

# XXX: TODO: Deep deletions and full object tree updates are not emitted

# Merges two or more JSON documents and returns the merged result.
# Merging takes place according to the following rules.
# Adjacent arrays are merged to a single array.
# Adjacent objects are merged to a single object.
# A scalar value is autowrapped as an array and merged as an array.
# An adjacent array and object are merged by autowrapping the object as an array and merging the two arrays.
json-merge = (a, b) ->
  for key, val of b
    if a[key]?
      if is-array(a[key]) and is-array(b[key])
        a[key] = a[key] ++ b[key]
      else if is-object(a[key]) and is-object(b[key])
        json-merge a[key], b[key]
      else if is-array(a[key]) and (is-object(b[key]) or is-number(b[key]) or is-string(b[key]))
        a[key] = a[key] ++ [ b[key] ]
      else if (is-object(a[key]) or is-number(a[key]) or is-string(a[key])) and is-array(b[key])
        a[key] = [ a[key] ] ++ b[key]
      else
        a[key] = b[key]
    else
      a[key] = b[key]
  a

json-remove =($, path) ->
  results = []
  for path in jsonpath json: $, path: path, result-type: \path
    results.push eval path
    eval "delete #path"
  return null if results.length is 0
  return results.0 if results.length is 1
  results

json-extract = (obj, path) ->
  jsonpath json: obj, path: path, wrap: false

module.exports = (socket, channel) ->
  state = {}
  observers = {}
  emit-queue = []
  rivulet = ->
    if it
      rivulet.patch patch.compare state, it
    else
      JSON.parse(JSON.stringify state)
  rivulet <<< do
    state: state
    logger: null
    # has: (path) ->
    #   object-path.has state, path
    # shy: (path, key) ->
    #   key = [ key ] if not is-array key
    #   obj = object-path.get state, path
    #   return true if not obj
    #   (key |> filter -> obj[camelize it]).length < key.length
    # get: (path) ->
    #   return null if not (obj = object-path.get state, path)
    #   JSON.parse(JSON.stringify(obj))
    # set: (path, val) ->
    #   revised = rivulet!
    #   object-path.set revised, path, val
    #   rivulet revised
    # add: (path, val) ->
    #   obj = object-path.get state, path
    #   revised = rivulet!
    #   object-path.push revised, path, val
    #   rivulet revised
    # del: (path) ->
    #   revised = rivulet!
    #   object-path.del revised, path
    #   rivulet revised
    remove: (path) -> json-remove state, path
    extract: (path) -> json-extract state, path
    observe: (path, func) ->
      if not observers[path]
        observers[path] = {}
        observers[path].stream = kefir.stream -> observers[path].emitter = it
      if func
        observers[path].stream
        .on-value (val) ->
          set-timeout ->
            func val
      observers[path].stream
    patch: (diff, emit = true) ->
      return if not diff.length
      emit-queue.push diff if emit
      old-state = rivulet!
      patch.apply state, diff
      extraction-cache = {}
      for path, observer of observers
        extraction-cache[path] ?=
          old: json-extract old-state, path
          new: json-extract state, path
        try
          if path is \$
            extraction-cache.new = state
            throw
          assert.deep-equal extraction-cache[path].old, extraction-cache[path].new
        catch
          observer.emitter.emit extraction-cache[path].new
      # emit-change = (change) ->
      #   for path, observer of observers
      #     notifications[path] ?= {}
      #     notifications[path]
      #   change-path = compact(change.path.split '/').join '.'
      #   if observers.atom[change-path]
      #     observers.atom[change-path].emitter.emit ({} <<< change) <<< path: change-path
      #   for path, observer of observers.flat
      #     flat-emits[path] ?= { observer: observer, changes: [] }
      #     if //^#{path}(\.[^\.]+)?$//.test change-path
      #       flat-emits[path].changes.push ({} <<< change) <<< path: change-path
      #   for path, observer of observers.deep
      #     deep-emits[path] ?= { observer: observer, changes: [] }
      #     if //#{path}//.test change-path
      #       deep-emits[path].changes.push ({} <<< change) <<< path: change-path
      #   # When object is added, do a deep emit of all its descendants
      #   if change.op is \add and typeof!(change.value) is \Object
      #     for key, val of change.value
      #       emit-change op: \add, path: change.path + "/#key", value: val
      #   if change.op is \add and typeof!(change.value) is \Array
      #     for val, key in change.value
      #       emit-change op: \add, path: change.path + "/#key", value: val
      # for change in diff
      #   emit-change change
      # for key, val of flat-emits
      #   continue if not val.changes.length
      #   val.observer.emitter.emit val.changes
      # for key, val of deep-emits
      #   continue if not val.changes.length
      #   val.observer.emitter.emit val.changes
    merge: (partial) ->
      rivulet json-merge rivulet!, partial
    # select: (cursor-path) ->
    #   throw 'Can only select objects' if not is-object(object-path.get state, cursor-path)
    #   cursor = ->
    #     if it
    #       rivulet.merge (object-path.set {}, cursor-path, it)
    #     else
    #       rivulet.get cursor-path
    #   cursor <<< do
    #     has: (path) ->
    #       rivulet.has "#cursor-path.#path"
    #     shy: (path, key) ->
    #       rivulet.shy "#cursor-path.#path"
    #     get: (path) ->
    #       rivulet.get "#cursor-path.#path"
    #     set: (path, val) ->
    #       rivulet.set "#cursor-path.#path", val
    #     del: (path) ->
    #       rivulet.del "#cursor-path.#path"
    #   cursor
  if socket and channel
    rivulet.socket = socket
    rivulet.socket.on channel, ->
      rivulet.logger 'Rivulet received', it if rivulet.logger
      rivulet.patch it, false
    emit-stream = rivulet.observe '$'
    emit-stream.on-value ->
      while diff = emit-queue.pop!
        rivulet.logger 'Rivulet sending', diff if rivulet.logger
        socket.emit channel, diff
  rivulet


