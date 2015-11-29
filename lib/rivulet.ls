require! \kefir
require! \fast-json-patch : \patch
require! \object-path
require! \deep-extend
# require! \jspath
require! \JSONPath : jsonpath

# XXX: TODO: Deep deletions and full object tree updates are not emitted

module.exports = (socket, channel) ->
  state = {}
  observers =
    atom: {}
    flat: {}
    deep: {}
  emit-queue = []
  rivulet = ->
    if it
      rivulet.patch patch.compare state, it
    else
      JSON.parse(JSON.stringify state)
  rivulet <<< do
    state: state
    logger: null
    has: (path) ->
      object-path.has state, path
    shy: (path, key) ->
      key = [ key ] if not is-array key
      obj = object-path.get state, path
      return true if not obj
      (key |> filter -> obj[camelize it]).length < key.length
    get: (path) ->
      return null if not (obj = object-path.get state, path)
      JSON.parse(JSON.stringify(obj))
    set: (path, val) ->
      revised = rivulet!
      object-path.set revised, path, val
      rivulet revised
    add: (path, val) ->
      obj = object-path.get state, path
      revised = rivulet!
      object-path.push revised, path, val
      rivulet revised
    del: (path) ->
      revised = rivulet!
      object-path.del revised, path
      rivulet revised
    extract: (path) ->
      # jspath.apply ".#{query.replace /\'/g, '"'}", state
      jsonpath json: state, path: path
    observe: (path, func, depth = \flat) ->
      if not observers[depth][path]
        observers[depth][path] = {}
        observers[depth][path].stream = kefir.stream -> observers[depth][path].emitter = it
      if func
        observers[depth][path].stream
        .on-value (val) ->
          set-timeout ->
            func rivulet, val
      observers[depth][path].stream
    observe-atom: (path, func) -> rivulet.observe path, func, \atom
    observe-flat: (path, func) -> rivulet.observe path, func, \flat
    observe-deep: (path, func) -> rivulet.observe path, func, \deep
    patch: (diff, emit = true) ->
      return if not diff.length
      emit-queue.push diff if emit
      flat-emits = {}
      deep-emits = {}
      patch.apply state, diff
      emit-change = (change) ->
        change-path = compact(change.path.split '/').join '.'
        if observers.atom[change-path]
          observers.atom[change-path].emitter.emit ({} <<< change) <<< path: change-path
        for path, observer of observers.flat
          flat-emits[path] ?= { observer: observer, changes: [] }
          if //^#{path}(\.[^\.]+)?$//.test change-path
            flat-emits[path].changes.push ({} <<< change) <<< path: change-path
        for path, observer of observers.deep
          deep-emits[path] ?= { observer: observer, changes: [] }
          if //#{path}//.test change-path
            deep-emits[path].changes.push ({} <<< change) <<< path: change-path
        # When object is added, do a deep emit of all its descendants
        if change.op is \add and typeof!(change.value) is \Object
          for key, val of change.value
            emit-change op: \add, path: change.path + "/#key", value: val
        if change.op is \add and typeof!(change.value) is \Array
          for val, key in change.value
            emit-change op: \add, path: change.path + "/#key", value: val
      for change in diff
        emit-change change
      for key, val of flat-emits
        continue if not val.changes.length
        val.observer.emitter.emit val.changes
      for key, val of deep-emits
        continue if not val.changes.length
        val.observer.emitter.emit val.changes
    merge: (partial) ->
      rivulet deep-extend rivulet!, partial
    select: (cursor-path) ->
      throw 'Can only select objects' if not is-object(object-path.get state, cursor-path)
      cursor = ->
        if it
          rivulet.merge (object-path.set {}, cursor-path, it)
        else
          rivulet.get cursor-path
      cursor <<< do
        has: (path) ->
          rivulet.has "#cursor-path.#path"
        shy: (path, key) ->
          rivulet.shy "#cursor-path.#path"
        get: (path) ->
          rivulet.get "#cursor-path.#path"
        set: (path, val) ->
          rivulet.set "#cursor-path.#path", val
        del: (path) ->
          rivulet.del "#cursor-path.#path"
      cursor
  if socket and channel
    rivulet.socket = socket
    rivulet.socket.on channel, ->
      rivulet.logger 'Rivulet received', it if rivulet.logger
      rivulet.patch it, false
    emit-stream = rivulet.observe-deep ''
    emit-stream.on-value ->
      while diff = emit-queue.pop!
        rivulet.logger 'Rivulet sending', diff if rivulet.logger
        socket.emit channel, diff
  rivulet


