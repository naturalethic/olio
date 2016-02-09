require! \world
require! \later
require! \transport

export watch = [ __filename, "#__dirname/../lib" ]

$info = (...args) ->
  date = (new Date).toISOString!split \T
  if is-string(args.0)
    args.0 = color(170, args.0)
  args.unshift "#{color(81, date.0)}#{color(239, 'T')}#{color(81, date.1)} #{color(22, 'INFO')}"
  if is-object(last args) or is-array(last args)
    obj = args.pop!
  info ...args
  pp obj if obj

ensure-world-record = ->*
  tx = yield world.transaction
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
    $info \Tick, color(220, ticker)
    tx = yield world.transaction!
    tx.$info = $info
    try
      yield tickers[ticker] tx, config
      yield tx.commit!
    catch e
      info e
      yield tx.rollback!
  catch e
    info e
  finally
    delete config.ticking

tickers =
  postmaster: (world, config) ->*
    ids = (yield world.query """
      SELECT id
        FROM document
       WHERE kind = 'notification'
         AND path = 'schedule'
         AND id NOT IN (SELECT id FROM document WHERE kind = 'notification' AND path = 'dispatched')
         AND str_to_date(search, '%Y-%m-%dT%H:%i:%S') < now()
    """) |> map -> it.id
    for id in ids
      $info \Dispatching, id
      yield transport.dispatch world, (yield world.get id)
