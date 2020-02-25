# Deployer Toolkit!

To help support [Deployment Unit](deployment-unit.md) maintainance, a
toolkit is available to perform certain tasks, such as encryption.

The toolkit is available via Dockerhub.


```
docker pull vasdvp/deployer-toolkit:latest
```

#### Print help
```
docker run --rm vasdvp/deployer-toolkit:latest
```

> `/du` is a special mount point that toolkit uses for most operations.
> You'll need to mount your deployment unit directory to `/du`


#### Example usage
```
SECRET=sp00py
cd /somewhere/awesome-deployment

# Decrypt sensitive files
docker run --rm -v $(pwd):/du vasdvp/deployer-toolkit:latest decrypt -e $SECRET

# Prevent decrypted secrets from being committed
docker run --rm -v $(pwd):/du vasdvp/deployer-toolkit:latest gitsecrets

# Still have encrypted zips?
docker run --rm -v $(pwd):/du vasdvp/deployer-toolkit:latest unzip -e $SECRET

# DOS line endings are no bueno.
docker run --rm -v $(pwd):/du vasdvp/deployer-toolkit:latest dos2unix

# Encrypt sensitive files
docker run --rm -v $(pwd):/du vasdvp/deployer-toolkit:latest encrypt -e $SECRET

# Still need encrypted zips? Are you sure? They're lame.
docker run --rm -v $(pwd):/du vasdvp/deployer-toolkit:latest zip -e $SECRET
```


#### Notes
- The `gitsecrets` command only hooks git-secrets to your GitHub repository.
  If you are receiving the message: `git: 'secrets' is not a git command. See 'git --help'.`
  Follow the [install instructions](https://github.com/awslabs/git-secrets) to install git-secrets locally.
