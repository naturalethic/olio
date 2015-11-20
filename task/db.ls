require! \db

export reset = ->*
  yield db.reset!
  process.exit!

export list = ->*
  r = rethinkdbdash olio.config.db{host}
  r = r.db olio.config.db.name
  info yield r.table(olio.task.2)
  process.exit!
