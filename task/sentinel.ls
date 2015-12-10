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

export sentinel = ->*
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
  try
    $info \Tick, ticker
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
    notifications = (yield world.query """
      select * from document
       where kind = 'notification'
         and json_extract(data, '$.dispatched') is null
         and str_to_date(json_unquote(data->'$.schedule'), '%Y-%m-%dT%H:%i:%S') < now()
    """) |> map -> world.cursor \notification, it.data
    for notification in notifications
      yield transport.dispatch world, notification
