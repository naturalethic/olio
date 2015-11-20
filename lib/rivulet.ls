require! \kefir
require! \fast-json-patch : \patch
require! \object-path

# XXX: TODO: The patch does not itemize deep object adds in the diff.  These changes won't be emitted.
#            Solution might be to walk object / array adds and emit changes on them.
#            However, in order to do this for deletions, or updates that replace whole object, must
#            keep a copy of the old object to know whats been deleted.

module.exports = ->
  state = {}
  observers =
    atom: {}
    flat: {}
    deep: {}
  rivulet = ->
    if it
      rivulet.patch patch.compare state, it
    else
      JSON.parse(JSON.stringify state)
  <<< do
    get: (path) ->
      object-path.get state, path
    set: (path, val) ->
      revised = rivulet!
      object-path.set revised, path, val
      rivulet revised
    del: (path) ->
      object-path.del state, path
    observe: (path, depth = \atom) ->
      if not observers[depth][path]
        observers[depth][path] = {}
        observers[depth][path].stream = kefir.stream -> observers[depth][path].emitter = it
      observers[depth][path].stream
    # observe-atom: (path, depth = \atom) ->
    observe-deep: (path) -> rivulet.observe path, \deep
    observe-flat: (path) -> rivulet.observe path, \flat
    patch: (diff) ->
      rivulet.last = diff
      deep-emits = []
      flat-emits = []
      patch.apply state, diff
      for change in diff
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
