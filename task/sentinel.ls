require! \world
require! \later
require! \transport

export watch = [ __filename, "#__dirname/../lib" ]

$info = (...args) ->
  date = (new Date).toISOString!split \T
  if is-string(args.0)
    args.0 = args.0.magenta
  args.unshift "#{date.0.cyan}#{'T'.grey}#{date.1.cyan} #{'INFO'.green}"
  if is-object(last args) or is-array(last args)
    obj = args.pop!
  info ...args
  pp obj if obj

ensure-world-record = ->*
  tx = yield world.transaction true
  try
    if not yield tx.select \sentinel
      yield tx.save \sentinel
    yield tx.commit!
  catch e
    info e
    yield tx.rollback!

export sentinel = ->*
  yield ensure-world-record!
  sentinel-config = olio.config?sentinel or {}
  keys sentinel-config |> each (ticker) ->
    config = sentinel-config[ticker]
    return if not config.schedule
    return if not tickers[ticker]
    co tick ticker, config
    later.set-interval (co.wrap ->* yield tick ticker, config), later.parse.text(config.schedule)

tick = (ticker, config) ->*
  return if config.ticking
  config.ticking = true
  if olio.config.sentinel.allow-background-reset
    yield ensure-world-record!
  try
    $info \Tick, ticker
    tx = yield world.transaction!
    tx.$info = $info
    try
      yield tickers[ticker] tx, config
      yield tx.commit!
    catch e
      yield tx.rollback!
  catch e
    info e
  finally
    delete config.ticking

tickers =
  postmaster: (world, config) ->*
    if yield world.secretary.indices.exists index: \document
      notifications = yield world.search-select \notification,
        bool:
          must: [
            range:
              schedule:
                lt: \now
          ]
          must_not: [
            term:
              dispatched: true
          ]
      for notification in notifications
        yield transport.dispatch world, notification
  secretary: (world, config) ->*
    sentinel = yield world.select \sentinel
    if not sentinel.secretary
      if yield world.secretary.indices.exists index: \document
        yield world.secretary.indices.delete index: \document
      sentinel.secretary = updated: new Date
      documents = yield world.query "select * from document"
      bulk = []
      for document in documents
        bulk.push index: { _index: \document, _type: document.kind, _id: document.id }
        bulk.push JSON.parse(document.data)
      yield world.secretary.bulk-async body: bulk
    else
      documents = yield world.query "select * from document where updated > ?", [ sentinel.secretary.updated ]
      if documents.length
        sentinel.secretary.updated = new Date
        bulk = []
        for document in documents
          bulk.push index: { _index: \document, _type: document.kind, _id: document.id }
          bulk.push JSON.parse(document.data)
        yield world.secretary.bulk-async body: bulk
