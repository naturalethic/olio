export build = ->*
  if olio.task.length < 3
    return info "Usage: #{olio.task.0} <env> <product>"
  env = olio.task.1
  product = olio.task.2
  root = "ops/#env/#product/root"
  info "Syncing -> #root"
  exec "rm -rf #root"
  exec "mkdir -p #root"
  exec "rsync -maz gcloud.json #root"
  exec "rsync -maz lib #root"
  exec "rsync -maz notification #root"
  exec "rsync -maz olio.ls #root"
  exec "rsync -maz package.json #root"
  exec "rsync -maz react #root"
  exec "rsync -maz session.ls #root"
  exec "rsync -maz test #root"
  yield ex "docker build -t us.gcr.io/copsforhire.com/copsforhire/#{env}-#{product} ops/#env/#product"

export run-shell = ->*
  if olio.task.length < 3
    return info "Usage: #{olio.task.0} <env> <product>"
  env = olio.task.1
  product = olio.task.2
  yield ex "docker run --rm -ti us.gcr.io/copsforhire.com/copsforhire/#{env}-#{product} /bin/sh"
