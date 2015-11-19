require! \rethinkdbdash

export reset = (r) ->*
  disconnect-at-end = !r
  r ?= conn = rethinkdbdash olio.config.db{host}
  if olio.config.db.name not in (yield r.db-list!)
    info "Creating database '#{olio.config.db.name}'"
    yield r.db-create olio.config.db.name
  r = r.db olio.config.db.name
  for table in  olio.config.db.tables ++ <[ session ]>
    info "Creating or emptying table '#table'"
    try
      yield r.table(table).delete!
      yield r.table-create table
  r._r.get-pool-master!drain! if disconnect-at-end
