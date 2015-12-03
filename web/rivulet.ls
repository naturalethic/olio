require! \kefir
require! \fast-json-patch : \patch
require! \object-path

# XXX: TODO: Deep deletions and full object tree updates are not emitted

module.exports = (socket, channel)->
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
    logger: null
    get: (path) ->
      object-path.get state, path
    set: (path, val) ->
      revised = rivulet!
      object-path.set revised, path, val
      rivulet revised
    del: (path) ->
      revised = rivulet!
      object-path.del revised, path
      rivulet revised
    observe: (path, func, depth = \flat) ->
      if not observers[depth][path]
        observers[depth][path] = {}
        observers[depth][path].stream = kefir.stream -> observers[depth][path].emitter = it
      if func
        observers[depth][path].stream
        .on-value ->
          set-timeout ->
            func rivulet!
      observers[depth][path].stream
    observe-atom: (path, func) -> rivulet.observe path, func, \atom
    observe-flat: (path, func) -> rivulet.observe path, func, \flat
    observe-deep: (path, func) -> rivulet.observe path, func, \deep
    patch: (diff, emit = true) ->
      return if not diff.length
      emit-queue.push diff if emit
      deep-emits = []
      flat-emits = []
      patch.apply state, diff
      emit-change = (change) ->
        change-path = compact(change.path.split '/').join '.'
        if observers.atom[change-path]
          observers.atom[change-path].emitter.emit change-path
        for path, observer of observers.deep
          continue if path in deep-emits
          if //#{path}//.test change-path
            observer.emitter.emit path
            deep-emits.push path
        for path, observer of observers.flat
          continue if path in flat-emits
          if //^#{path}(\.[^\.]+)?$//.test change-path
            observer.emitter.emit path
            flat-emits.push path
        # When object is added, do a deep emit of all its descendants
        if change.op is \add and typeof!(change.value) is \Object
          for key, val of change.value
            emit-change op: \add, path: change.path + "/#key", value: val
        if change.op is \add and typeof!(change.value) is \Array
          for val, key in change.value
            emit-change op: \add, path: change.path + "/#key", value: val
      for change in diff
        emit-change change
    merge: (partial) ->
      revised = rivulet! <<< partial
      rivulet revised
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


