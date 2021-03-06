export build = ->*
  if olio.task.length < 4
    return info "Usage: #{olio.task.0} #{olio.task.1} <env> <product>"
  env = olio.task.2
  product = olio.task.3
  if env != \base and product == \base
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
    exec "rsync -maz schema #root"
    exec "rsync -maz test #root"
  spawn "docker build -t us.gcr.io/#{olio.config.ops.project.replace /:/g, '/'}/#{env}-#{product}:latest ops/#env/#product"
  if env != \base and product == \base
    exec "rm -rf #root"
  if olio.option.push
    yield push!

export push = ->*
  if olio.task.length < 4
    return info "Usage: #{olio.task.0} #{olio.task.1} <env> <product>"
  env = olio.task.2
  product = olio.task.3
  spawn "gcloud docker push us.gcr.io/#{olio.config.ops.project.replace /:/g, '/'}/#{env}-#{product}:latest"

export push-static = ->*
  if olio.task.length < 3
    return info "Usage: #{olio.task.0} #{olio.task.1} <env>"
  env = olio.task.2
  spawn "gsutil -m rsync -d -r public gs://#{env}.copsforhire.com"

export fix-static = ->*
  if olio.task.length < 3
    return info "Usage: #{olio.task.0} #{olio.task.1} <env>"
  env = olio.task.2
  spawn "gsutil -m acl ch -r -u AllUsers:R gs://#{env}.copsforhire.com"
  spawn "gsutil -m web set -m index.html -e index.html gs://#{env}.copsforhire.com"

export shell = ->*
  if olio.task.length < 4
    return info "Usage: #{olio.task.0} #{olio.task.1} <env> <product>"
  env = olio.task.2
  product = olio.task.3
  spawn "docker run --rm -ti us.gcr.io/#{olio.config.ops.project.replace /:/g, '/'}/#{env}-#{product} /bin/bash"

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
