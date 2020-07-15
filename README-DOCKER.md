# BUILDING AN IMAGE

Building the docker image is automated via the use of `build.sh`. It makes it
easier to supply the Dockerfile variables and tag/push the image.

You must use `docker login` prior to pushing images to Docker Hub.


# build.sh USAGE

```
Usage: build.sh [OPTIONS] [DOCKER ARGS]

OPTIONS:

  -b|--branch REPO   Branch for client and stats repos (default: based on env)
  -e|--env ENV       Env to build/push (dev, staging, prod) (default: prod)
  -h|--help          This information
  -t|--tag TAG       Override image tag
  -p|--push          Automatically push to Docker hub
  -t|--tag           Specify explicit tag (overrides --env)

EXAMPLE:

  $ build.sh --env dev --branch master --tag jsmith/encryptme-pep --push
```


## DOCKER VARIABLES

If building natively with Docker there are a few options:

- repo_branch: which branch to use for the client and stats repos (default=master)
- build_time: an optional build-time (e.g. helps cache-bust file changes)


