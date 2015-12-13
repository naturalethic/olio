export build = ->*
  if olio.task.length < 4
    return info "Usage: #{olio.task.0} #{olio.task.1} <env> <product>"
  env = olio.task.2
  product = olio.task.3
  if product is \base
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
  spawn "docker build -t us.gcr.io/copsforhire.com/copsforhire/#{env}-#{product}:latest ops/#env/#product"

export push = ->*
  if olio.task.length < 4
    return info "Usage: #{olio.task.0} #{olio.task.1} <env> <product>"
  env = olio.task.2
  product = olio.task.3
  spawn "gcloud docker push us.gcr.io/copsforhire.com/copsforhire/#{env}-#{product}:latest"

export shell = ->*
  if olio.task.length < 4
    return info "Usage: #{olio.task.0} #{olio.task.1} <env> <product>"
  env = olio.task.2
  product = olio.task.3
  spawn "docker run --rm -ti us.gcr.io/copsforhire.com/copsforhire/#{env}-#{product} /bin/bash"

export zone = ->*
  spawn "gcloud config set compute/zone us-central1-c"

export clusters = ->*
  spawn "gcloud alpha container clusters list"

export use = ->*
  if olio.task.length < 3
    return info "Usage: #{olio.task.0} #{olio.task.1} <env>"
  env = olio.task.2
  spawn "gcloud config set container/cluster #env"
  spawn "gcloud container clusters get-credentials #env"
